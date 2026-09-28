import Foundation

enum VoiceInterpretationConfidence: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high

    var title: String {
        switch self {
        case .low: "Нужно проверить"
        case .medium: "Похоже, всё верно"
        case .high: "Уверенно"
        }
    }
}

enum VoiceInterpretationAmbiguity: String, Codable, Hashable, Sendable {
    case missingDate
    case ambiguousDate
    case ambiguousTime
    case unclearReference
    case multipleActions
    case emptyTitle

    var title: String {
        switch self {
        case .missingDate: "Дата не найдена"
        case .ambiguousDate: "Дату нужно уточнить"
        case .ambiguousTime: "Время нужно уточнить"
        case .unclearReference: "Неясно, о чём идёт речь"
        case .multipleActions: "Найдено несколько действий"
        case .emptyTitle: "Не удалось выделить заголовок"
        }
    }
}

enum VoiceClarificationDecision: Equatable, Sendable {
    case date
    case time
}

enum VoiceClarificationPolicy {
    static func decision(for draft: ReminderDraft) -> VoiceClarificationDecision? {
        if draft.ambiguities.contains(.ambiguousTime) {
            return .time
        }
        if draft.ambiguities.contains(.ambiguousDate) {
            return .date
        }
        guard draft.ambiguities.contains(.missingDate) else { return nil }

        // A plain reminder without a date is a valid inbox item. Interrupt the
        // fast capture flow only when the user did mention a vague deadline or
        // the semantic result itself is uncertain.
        if draft.confidence == .low || containsVagueTemporalCue(draft.transcript) {
            return .date
        }
        return nil
    }

    private static func containsVagueTemporalCue(_ value: String) -> Bool {
        let normalized = value.lowercased(with: Locale(identifier: "ru_RU"))
        let cues = [
            "потом", "позже", "скоро", "на днях", "как-нибудь",
            "ближе к", "в начале недели", "в конце недели",
            "на этой неделе", "на следующей неделе"
        ]
        return cues.contains { normalized.contains($0) }
    }
}

struct ReminderDraft: Equatable, Sendable {
    let transcript: String
    let title: String
    let details: String?
    let dueDate: Date?
    let reminderOffsets: [Int]
    let confidence: VoiceInterpretationConfidence
    let ambiguities: Set<VoiceInterpretationAmbiguity>
}

struct VoiceCaptureEntry: Equatable, Sendable {
    let sourceText: String
    let draft: ReminderDraft
    let kind: EntryKind
    let endDate: Date?
    var linkGroup: Int? = nil
}

struct VoiceCaptureResult: Equatable, Sendable {
    let entries: [VoiceCaptureEntry]

    init(entries: [VoiceCaptureEntry]) {
        self.entries = entries
    }

    static func local(
        _ transcript: String,
        now: Date,
        calendar: Calendar,
        defaultKind: EntryKind
    ) -> VoiceCaptureResult {
        let parts = VoiceUtteranceSplitter.split(transcript)
        let entries = parts.compactMap { part -> VoiceCaptureEntry? in
            guard let draft = LocalVoiceIntentInterpreter().interpret(
                part, now: now, calendar: calendar
            ).draft else { return nil }
            let kind = EntryKindInference.infer(from: part, hasDate: draft.dueDate != nil)
                ?? defaultKind
            return VoiceCaptureEntry(sourceText: part, draft: draft, kind: kind, endDate: nil)
        }
        return VoiceCaptureResult(entries: entries)
    }
}

enum VoiceUtteranceSplitter {
    // Only explicit new-item markers are safe offline. A plain "и" can be
    // two steps of the same task, so the semantic service handles that case.
    static func split(_ transcript: String) -> [String] {
        let pattern = #"(?i)(?:[,;.]+\s*|\s+)(?:и\s+ещ[её]|а\s+ещ[её]|отдельно|ещ[её]\s+одно|следующ(?:ее|ий))\s*[:,-]?\s*"#
        let marked = transcript.replacingOccurrences(
            of: pattern,
            with: "\n",
            options: .regularExpression
        )
        let parts = marked.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.count > 6 { return [transcript] }
        return parts
    }
}

enum VoiceCapturePreview: Equatable {
    case single
    case uncertain
    case multiple(Int)

    static func classify(_ transcript: String) -> Self {
        let parts = VoiceUtteranceSplitter.split(transcript)
        if parts.count > 1 { return .multiple(parts.count) }

        if transcript.range(of: #"[.!?;]\s+\p{L}"#, options: .regularExpression) != nil {
            return .uncertain
        }

        // A connector may join one thought or two separate records. Until the
        // semantic result arrives, do not label the whole phrase as one item.
        let normalized = " " + transcript.lowercased()
            .replacingOccurrences(of: #"[,.!?;:-]+"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ") + " "
        let uncertainMarkers = [
            " и ", " потом ", " затем ", " также ", " еще ", " ещё ", " плюс ",
            " во первых ", " во вторых ", " первое ", " второе "
        ]
        return uncertainMarkers.contains(where: normalized.contains) ? .uncertain : .single
    }
}

enum VoiceDraftReconciler {
    static func reconcile(
        semantic draft: ReminderDraft,
        deterministic parsed: ParsedMemoryInput?
    ) -> ReminderDraft {
        guard let parsed else { return draft }

        var ambiguities = draft.ambiguities
        ambiguities.remove(.missingDate)
        ambiguities.remove(.ambiguousDate)
        ambiguities.remove(.ambiguousTime)
        let reminderOffsets = parsed.reminderOffsets.isEmpty
            ? draft.reminderOffsets
            : parsed.reminderOffsets

        return ReminderDraft(
            transcript: draft.transcript,
            title: draft.title,
            details: draft.details,
            dueDate: parsed.dueDate,
            reminderOffsets: reminderOffsets,
            confidence: draft.confidence,
            ambiguities: ambiguities
        )
    }
}

enum VoiceInterpretationResult: Equatable, Sendable {
    case success(ReminderDraft)
    case empty

    var draft: ReminderDraft? {
        guard case let .success(draft) = self else { return nil }
        return draft
    }
}

enum VoiceSemanticError: Error {
    case timedOut
    case emptyResult
}

protocol VoiceIntentInterpreting: Sendable {
    func interpret(
        _ transcript: String,
        now: Date,
        calendar: Calendar
    ) -> VoiceInterpretationResult
}

struct LocalVoiceIntentInterpreter: VoiceIntentInterpreting {
    func interpret(
        _ transcript: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> VoiceInterpretationResult {
        let normalizedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTranscript.isEmpty else { return .empty }

        if let parsed = NaturalLanguageDateParser.parse(
            normalizedTranscript,
            now: now,
            calendar: calendar
        ) {
            let structuredText = LocalReminderTextStructurer.structure(parsed.title)
            return .success(ReminderDraft(
                transcript: normalizedTranscript,
                title: structuredText.title,
                details: structuredText.details,
                dueDate: parsed.dueDate,
                reminderOffsets: parsed.reminderOffsets,
                confidence: .high,
                ambiguities: []
            ))
        }

        let structuredText = LocalReminderTextStructurer.structure(normalizedTranscript)
        return .success(ReminderDraft(
            transcript: normalizedTranscript,
            title: structuredText.title,
            details: structuredText.details,
            dueDate: nil,
            reminderOffsets: [],
            confidence: .medium,
            ambiguities: [.missingDate]
        ))
    }
}

struct StructuredReminderText: Equatable, Sendable {
    let title: String
    let details: String?
}

enum LocalReminderTextStructurer {
    static func structure(_ input: String) -> StructuredReminderText {
        let source = collapsed(input)
        guard !source.isEmpty else {
            return StructuredReminderText(title: input, details: nil)
        }

        var title = source
        var details: [String] = []

        if let marker = lastMatch(
            pattern: #"(?i)\b(?:(?:мне\s+)?(?:нужно|надо)(?:\s+будет)?(?:\s+сразу)?|не\s+забыть)\s+"#,
            in: title
        ),
           let markerRange = Range(marker.range, in: title) {
            let context = cleanDetails(String(title[..<markerRange.lowerBound]))
            let action = cleanTitle(String(title[markerRange.upperBound...]))
            if let context { details.append(context) }
            if !action.isEmpty { title = action }
        }

        if let split = split(
            title,
            separators: [" потому что ", " так как ", " поскольку "]
        ) {
            title = cleanTitle(split.leading)
            if let context = cleanDetails(split.trailing) { details.append(context) }
        }

        if title.lowercased(with: russianLocale).hasPrefix("позвонить "),
           let split = split(title, separators: [" и уточнить ", " уточнить "]) {
            title = cleanTitle(split.leading)
            if let context = cleanDetails("Уточнить " + split.trailing) { details.append(context) }
        }

        title = cleanTitle(title)
        if title.isEmpty { title = source }

        let combinedDetails = details
            .map { cleanTitle($0) }
            .filter { !$0.isEmpty && $0.normalizedForComparison != title.normalizedForComparison }
            .joined(separator: ". ")

        return StructuredReminderText(
            title: capitalizedSentence(title),
            details: combinedDetails.isEmpty ? nil : capitalizedSentence(combinedDetails)
        )
    }

    private static let russianLocale = Locale(identifier: "ru_RU")

    private static func collapsed(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func cleanTitle(_ value: String) -> String {
        var result = collapsed(value)
        let leadingFillers = #"(?i)^(?:(?:а|и|я|мне|пожалуйста|сразу|тогда)\s+|(?:нужно|надо)(?:\s+будет)?\s+|не\s+забыть\s+)+"#
        result = result.replacingOccurrences(
            of: leadingFillers,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)\s+(?:пожалуйста|нужно\s+будет)$"#,
            with: "",
            options: .regularExpression
        )
        return collapsed(result)
    }

    private static func cleanDetails(_ value: String) -> String? {
        var result = collapsed(value)
        result = result.replacingOccurrences(
            of: #"(?i)^(?:у\s+меня|я|мне)\s+"#,
            with: "",
            options: .regularExpression
        )
        result = collapsed(result)
        return result.isEmpty ? nil : result
    }

    private static func split(
        _ value: String,
        separators: [String]
    ) -> (leading: String, trailing: String)? {
        let candidates = separators.compactMap { separator -> Range<String.Index>? in
            value.range(
                of: separator,
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: russianLocale
            )
        }
        guard let candidate = candidates.min(by: { $0.lowerBound < $1.lowerBound }) else {
            return nil
        }
        return (
            String(value[..<candidate.lowerBound]),
            String(value[candidate.upperBound...])
        )
    }

    private static func lastMatch(pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        return expression.matches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ).last
    }

    private static func capitalizedSentence(_ value: String) -> String {
        guard let first = value.first else { return value }
        return String(first).uppercased(with: russianLocale) + value.dropFirst()
    }
}

private extension String {
    var normalizedForComparison: String {
        lowercased(with: Locale(identifier: "ru_RU"))
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }
}

enum VoicePipelineSettings {
    static let structuredInterpreterEnabledKey = "norka.voice.structuredInterpreterEnabled"
    static let deepSeekInterpreterEnabledKey = "norka.voice.deepSeekInterpreterEnabled"
    static let clarificationEnabledKey = "norka.voice.clarificationEnabled"
    static let personalLearningEnabledKey = "norka.voice.personalLearningEnabled"
}
