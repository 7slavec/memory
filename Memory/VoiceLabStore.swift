import Combine
import Foundation

struct VoiceLabExample: Codable, Identifiable, Equatable {
    let id: UUID
    var transcript: String
    var expectedTranscript: String?
    var expectedTitle: String
    var expectedDetails: String?
    var expectedDueDate: Date?
    var referenceDate: Date
    var timeZoneIdentifier: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        transcript: String,
        expectedTranscript: String? = nil,
        expectedTitle: String,
        expectedDetails: String? = nil,
        expectedDueDate: Date? = nil,
        referenceDate: Date = .now,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        createdAt: Date = .now
    ) {
        self.id = id
        self.transcript = transcript
        self.expectedTranscript = expectedTranscript
        self.expectedTitle = expectedTitle
        self.expectedDetails = expectedDetails
        self.expectedDueDate = expectedDueDate
        self.referenceDate = referenceDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.createdAt = createdAt
    }

    func evaluation(using interpreter: some VoiceIntentInterpreting) -> VoiceLabEvaluation {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ru_RU")
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current

        let actual = interpreter.interpret(
            transcript,
            now: referenceDate,
            calendar: calendar
        ).draft
        let transcriptMatches = transcript.normalizedForVoiceLab
            == (expectedTranscript ?? transcript).normalizedForVoiceLab
        let titleMatches = actual?.title.normalizedForVoiceLab == expectedTitle.normalizedForVoiceLab
        let detailsMatches = actual?.details.normalizedForVoiceLab == expectedDetails.normalizedForVoiceLab
        let dateMatches: Bool
        switch (actual?.dueDate, expectedDueDate) {
        case (nil, nil):
            dateMatches = true
        case let (actual?, expected?):
            // Relative phrases are captured and corrected a few seconds apart.
            // Treat that UI delay as the same intent instead of a parser failure.
            dateMatches = abs(actual.timeIntervalSince(expected)) <= 90
        default:
            dateMatches = false
        }

        return VoiceLabEvaluation(
            transcriptMatches: transcriptMatches,
            titleMatches: titleMatches,
            detailsMatch: detailsMatches,
            dateMatches: dateMatches
        )
    }
}

struct VoiceLabEvaluation: Equatable {
    let transcriptMatches: Bool
    let titleMatches: Bool
    let detailsMatch: Bool
    let dateMatches: Bool

    var isExactMatch: Bool {
        transcriptMatches && titleMatches && detailsMatch && dateMatches
    }
}

@MainActor
final class VoiceLabStore: ObservableObject {
    @Published private(set) var examples: [VoiceLabExample] = []

    nonisolated static let defaultStorageKey = "norka.voice.lab.examples"

    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = VoiceLabStore.defaultStorageKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        load()
    }

    func save(_ example: VoiceLabExample) {
        if let index = examples.firstIndex(where: { $0.id == example.id }) {
            examples[index] = example
        } else {
            examples.insert(example, at: 0)
        }
        persist()
    }

    func remove(_ example: VoiceLabExample) {
        examples.removeAll { $0.id == example.id }
        persist()
    }

    func addStarterExamplesIfNeeded() {
        guard examples.isEmpty else { return }
        examples = Self.starterExamples
        persist()
    }

    func refresh() {
        load()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let storedExamples = try? JSONDecoder().decode([VoiceLabExample].self, from: data) else {
            return
        }
        examples = storedExamples
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(examples) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func persistedExamples(defaults: UserDefaults = .standard) -> [VoiceLabExample] {
        guard let data = defaults.data(forKey: defaultStorageKey),
              let examples = try? JSONDecoder().decode([VoiceLabExample].self, from: data) else {
            return []
        }
        return examples
    }

    static func similarExamples(
        to transcript: String,
        limit: Int = 3,
        defaults: UserDefaults = .standard
    ) -> [VoiceLabExample] {
        let queryTokens = similarityTokens(transcript)
        guard !queryTokens.isEmpty else { return [] }

        return persistedExamples(defaults: defaults)
            .compactMap { example -> (VoiceLabExample, Double)? in
                let candidateTokens = similarityTokens(example.transcript)
                let intersection = queryTokens.intersection(candidateTokens).count
                guard intersection > 0 else { return nil }
                let union = max(1, queryTokens.union(candidateTokens).count)
                let score = Double(intersection) / Double(union)
                return (example, score)
            }
            .sorted {
                if $0.1 == $1.1 { return $0.0.createdAt > $1.0.createdAt }
                return $0.1 > $1.1
            }
            .prefix(max(0, limit))
            .map(\.0)
    }

    private static func similarityTokens(_ value: String) -> Set<String> {
        let ignored: Set<String> = [
            "мне", "надо", "нужно", "напомни", "пожалуйста", "чтобы",
            "короче", "слушай", "вообще", "просто", "это", "там"
        ]
        let words = value
            .lowercased(with: Locale(identifier: "ru_RU"))
            .replacingOccurrences(of: "ё", with: "е")
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).inverted)
            .filter { $0.count >= 3 && !ignored.contains($0) }
        return Set(words.map { String($0.prefix(6)) })
    }

    private static var starterExamples: [VoiceLabExample] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ru_RU")
        calendar.timeZone = TimeZone(identifier: "Europe/Samara") ?? .current
        let referenceDate = calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 21,
            hour: 12
        )) ?? .now

        func date(day: Int, hour: Int, minute: Int = 0) -> Date? {
            calendar.date(from: DateComponents(
                year: 2026,
                month: 9,
                day: day,
                hour: hour,
                minute: minute
            ))
        }

        return [
            VoiceLabExample(
                transcript: "Позвонить маме завтра в 10:30",
                expectedTranscript: "Позвонить маме завтра в 10:30",
                expectedTitle: "Позвонить маме",
                expectedDueDate: date(day: 22, hour: 10, minute: 30),
                referenceDate: referenceDate,
                timeZoneIdentifier: calendar.timeZone.identifier
            ),
            VoiceLabExample(
                transcript: "Проверить духовку через 20 минут",
                expectedTranscript: "Проверить духовку через 20 минут",
                expectedTitle: "Проверить духовку",
                expectedDueDate: referenceDate.addingTimeInterval(20 * 60),
                referenceDate: referenceDate,
                timeZoneIdentifier: calendar.timeZone.identifier
            ),
            VoiceLabExample(
                transcript: "Посмотреть фильм в пятницу вечером",
                expectedTranscript: "Посмотреть фильм в пятницу вечером",
                expectedTitle: "Посмотреть фильм",
                expectedDueDate: date(day: 25, hour: 19),
                referenceDate: referenceDate,
                timeZoneIdentifier: calendar.timeZone.identifier
            ),
            VoiceLabExample(
                transcript: "Записать хорошую идею",
                expectedTranscript: "Записать хорошую идею",
                expectedTitle: "Записать хорошую идею",
                referenceDate: referenceDate,
                timeZoneIdentifier: calendar.timeZone.identifier
            )
        ]
    }
}

struct VoiceLearningPromptExample: Encodable, Sendable {
    let transcript: String
    let title: String
    let details: String?
    let dueDate: String?
    let referenceDate: String
    let timeZone: String
}

private struct PendingVoiceLearningCapture: Codable {
    let itemID: UUID
    let transcript: String
    let proposedTitle: String
    let proposedDetails: String?
    let proposedDueDate: Date?
    let referenceDate: Date
    let timeZoneIdentifier: String
    let createdAt: Date
}

@MainActor
enum VoicePersonalizationStore {
    private static let pendingStorageKey = "norka.voice.learning.pending"
    private static let retentionInterval: TimeInterval = 7 * 24 * 60 * 60

    static func beginCapture(
        itemID: UUID,
        transcript: String,
        title: String,
        details: String?,
        dueDate: Date?,
        referenceDate: Date,
        timeZone: TimeZone = .current,
        defaults: UserDefaults = .standard
    ) {
        var pending = loadPending(defaults: defaults)
        let cutoff = Date.now.addingTimeInterval(-retentionInterval)
        pending.removeAll { $0.createdAt < cutoff || $0.itemID == itemID }
        pending.append(PendingVoiceLearningCapture(
            itemID: itemID,
            transcript: transcript,
            proposedTitle: title,
            proposedDetails: details,
            proposedDueDate: dueDate,
            referenceDate: referenceDate,
            timeZoneIdentifier: timeZone.identifier,
            createdAt: .now
        ))
        persist(pending, defaults: defaults)
    }

    static func confirmCorrection(
        itemID: UUID,
        title: String,
        details: String?,
        dueDate: Date?,
        defaults: UserDefaults = .standard
    ) {
        var pending = loadPending(defaults: defaults)
        guard let capture = pending.first(where: { $0.itemID == itemID }) else { return }
        pending.removeAll { $0.itemID == itemID }
        persist(pending, defaults: defaults)

        let store = VoiceLabStore(defaults: defaults)
        store.save(VoiceLabExample(
            transcript: capture.transcript,
            expectedTranscript: capture.transcript,
            expectedTitle: title,
            expectedDetails: details,
            expectedDueDate: dueDate,
            referenceDate: capture.referenceDate,
            timeZoneIdentifier: capture.timeZoneIdentifier
        ))
    }

    static func discardCaptures(
        for itemIDs: [UUID],
        defaults: UserDefaults = .standard
    ) {
        guard !itemIDs.isEmpty else { return }
        let ids = Set(itemIDs)
        var pending = loadPending(defaults: defaults)
        pending.removeAll { ids.contains($0.itemID) }
        persist(pending, defaults: defaults)
    }

    private static func loadPending(defaults: UserDefaults) -> [PendingVoiceLearningCapture] {
        guard let data = defaults.data(forKey: pendingStorageKey),
              let values = try? JSONDecoder().decode([PendingVoiceLearningCapture].self, from: data) else {
            return []
        }
        return values
    }

    private static func persist(
        _ values: [PendingVoiceLearningCapture],
        defaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        defaults.set(data, forKey: pendingStorageKey)
    }
}

private extension Optional where Wrapped == String {
    var normalizedForVoiceLab: String? {
        self?.normalizedForVoiceLab
    }
}

private extension String {
    var normalizedForVoiceLab: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased(with: Locale(identifier: "ru_RU"))
    }
}
