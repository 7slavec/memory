import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

enum QuickDuePreset: String, CaseIterable, Identifiable {
    case none, today, tomorrow
    var id: Self { self }
    var title: String { self == .none ? "Без срока" : self == .today ? "Сегодня" : "Завтра" }
    var icon: String { self == .none ? "tray" : self == .today ? "sun.max" : "sunrise" }

    var date: Date? {
        let calendar = Calendar.current
        switch self {
        case .none: return nil
        case .today:
            let evening = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: .now) ?? .now
            return evening > .now ? evening : calendar.date(byAdding: .hour, value: 1, to: .now)
        case .tomorrow:
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) else { return nil }
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        }
    }
}

private enum QuickCaptureFocus: Hashable {
    case title
    case description
}

enum QuickCapturePresentation {
    case standard
#if os(macOS)
    case desktopWorkspace
    case desktopInline
#endif
}

private struct PendingVoiceClarification {
    let decision: VoiceClarificationDecision
    let draft: ReminderDraft
    let details: String?
    let fallbackDate: Date?
    let referenceDate: Date
}

private struct VoiceClarificationOption: Identifiable {
    let id: String
    let title: String
    let caption: String?
    let dueDate: Date?
}

private struct QuickCaptureSurfaceModifier: ViewModifier {
    let isMinimal: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isMinimal {
            content
                .background(MemoryTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            content.memoryCard()
        }
    }
}

struct QuickCaptureCard: View {
    @EnvironmentObject private var account: AccountSyncController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var voiceInput = VoiceInputController()
    @AppStorage(VoicePipelineSettings.structuredInterpreterEnabledKey)
    private var isStructuredInterpreterEnabled = false
    @AppStorage(VoicePipelineSettings.deepSeekInterpreterEnabledKey)
    private var isDeepSeekInterpreterEnabled = false
    @AppStorage(VoicePipelineSettings.clarificationEnabledKey)
    private var isVoiceClarificationEnabled = true
    @State private var draft = ""
    @State private var preset: QuickDuePreset
    @State private var ignoredSmartExpression: String?
    @State private var ignoredKindExpression: String?
    @State private var entryKindOverride: EntryKind?
    @State private var smartResult: ParsedMemoryInput?
    @State private var details = ""
    @State private var isDescriptionPresented = false
    @State private var isVoicePulsing = false
    @State private var smartParsingTask: Task<Void, Never>?
    @State private var voiceSubmissionTask: Task<Void, Never>?
    @State private var shouldSubmitVoiceWhenStopped = false
    @State private var isFinalizingVoiceSubmission = false
    @State private var voiceProcessingStartedAt = Date.now
    @State private var pendingVoiceClarification: PendingVoiceClarification?
    @State private var isRecordsComposerPresented = false
    @State private var lastOrbDrag = Date.distantPast
    @GestureState private var isOrbDragging = false
    @FocusState private var focusedField: QuickCaptureFocus?
    let defaultPreset: QuickDuePreset
    let presentation: QuickCapturePresentation
    let isDocked: Bool
    let isHome: Bool
    let isRecordsPage: Bool
    let isPageSwiping: Bool
    let externalKeyboardVisible: Bool
    let priorityItem: Item?
    let isPriorityOverdue: Bool
    let additionalPriorityCount: Int
    let priorityLinkedCount: Int
    let onOpenPriorityLinkedRecord: (Item) -> Void
    let autofocus: Bool
    let detailCommitSignal: Int
    let remoteVoiceInterpreter: ((String, Date, Calendar) async throws -> VoiceCaptureResult)?
    let onTogglePriority: () -> Void
    let onEditPriority: () -> Void
    let onShowAll: () -> Void
    let onDismiss: () -> Void
    let onOpenDetails: (String, String?, EntryKind, Date?, Date?) -> Void
    let onReviewBatch: (VoiceBatchReview) -> Void
    let onAdd: (String, String?, EntryKind, Date?, Date?, [Int]?) -> UUID?

    init(
        defaultPreset: QuickDuePreset,
        presentation: QuickCapturePresentation = .standard,
        isDocked: Bool = false,
        isHome: Bool = false,
        isRecordsPage: Bool = false,
        isPageSwiping: Bool = false,
        externalKeyboardVisible: Bool = false,
        priorityItem: Item? = nil,
        isPriorityOverdue: Bool = false,
        additionalPriorityCount: Int = 0,
        priorityLinkedCount: Int = 0,
        onOpenPriorityLinkedRecord: @escaping (Item) -> Void = { _ in },
        autofocus: Bool = false,
        detailCommitSignal: Int = 0,
        remoteVoiceInterpreter: ((String, Date, Calendar) async throws -> VoiceCaptureResult)? = nil,
        onTogglePriority: @escaping () -> Void = {},
        onEditPriority: @escaping () -> Void = {},
        onShowAll: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {},
        onOpenDetails: @escaping (String, String?, EntryKind, Date?, Date?) -> Void = { _, _, _, _, _ in },
        onReviewBatch: @escaping (VoiceBatchReview) -> Void = { _ in },
        onAdd: @escaping (String, String?, EntryKind, Date?, Date?, [Int]?) -> UUID?
    ) {
        _preset = State(initialValue: defaultPreset)
        self.defaultPreset = defaultPreset
        self.presentation = presentation
        self.isDocked = isDocked
        self.isHome = isHome
        self.isRecordsPage = isRecordsPage
        self.isPageSwiping = isPageSwiping
        self.externalKeyboardVisible = externalKeyboardVisible
        self.priorityItem = priorityItem
        self.isPriorityOverdue = isPriorityOverdue
        self.additionalPriorityCount = additionalPriorityCount
        self.priorityLinkedCount = priorityLinkedCount
        self.onOpenPriorityLinkedRecord = onOpenPriorityLinkedRecord
        self.autofocus = autofocus
        self.detailCommitSignal = detailCommitSignal
        self.remoteVoiceInterpreter = remoteVoiceInterpreter
        self.onTogglePriority = onTogglePriority
        self.onEditPriority = onEditPriority
        self.onShowAll = onShowAll
        self.onDismiss = onDismiss
        self.onOpenDetails = onOpenDetails
        self.onReviewBatch = onReviewBatch
        self.onAdd = onAdd
    }

    var body: some View {
        Group {
#if os(macOS)
            if presentation == .desktopWorkspace {
                desktopCaptureBody
            } else if isHome {
                homeBody
            } else {
                compactBody
            }
#else
            if isHome {
                homeBody
                    .memoryPageVisibility(!isRecordsPage, hiddenX: MemoryMotion.pageDistance)
            } else {
                compactBody
            }
#endif
        }
        .overlay(alignment: .bottom) {
            if isHome {
                sharedCaptureChrome
                    .frame(maxWidth: .infinity)
                    .memoryPageVisibility(isRecordsPage && !isRecordsComposerPresented &&
                                          !externalKeyboardVisible && pendingVoiceClarification == nil,
                                          hiddenX: -MemoryMotion.pageDistance)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 18) {
            if isHome,
               pendingVoiceClarification == nil {
                homeComposer
                    .frame(maxWidth: 620)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity)
                    .background {
                        MemoryTheme.background
                            .ignoresSafeArea(edges: .bottom)
                    }
                    .memoryPageVisibility(!isRecordsPage || isRecordsComposerPresented,
                                          hiddenX: MemoryMotion.pageDistance)
                }
        }
        .animation(.spring(response: 0.46, dampingFraction: 0.9), value: smartResult != nil)
        .animation(reduceMotion ? nil : MemoryTheme.motion, value: voiceInput.isListening)
        .animation(reduceMotion ? nil : MemoryTheme.motion, value: isFinalizingVoiceSubmission)
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: pendingVoiceClarification != nil)
        .animation(.easeInOut(duration: 0.22), value: isDescriptionPresented)
        .animation(.spring(response: 0.46, dampingFraction: 0.9), value: isComposerExpanded)
        .onChange(of: draft) { oldValue, newValue in
            if !voiceInput.isListening,
               Self.isSingleInsertedLineBreak(from: oldValue, to: newValue) {
                draft = oldValue
                submit()
                return
            }

            smartParsingTask?.cancel()
            if isVoicePreviewActive,
               VoiceCapturePreview.classify(newValue) != .single {
                // One inferred date/type must not describe an uncertain batch.
                smartResult = nil
                return
            }
            smartParsingTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(voiceInput.isListening ? 160 : 70))
                guard !Task.isCancelled else { return }
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                smartResult = ignoredSmartExpression == newValue
                    ? nil
                    : NaturalLanguageDateParser.parse(trimmed)
            }
        }
        .onAppear {
            guard autofocus else { return }
            DispatchQueue.main.async {
                focusedField = .title
            }
        }
        .onChange(of: details) { oldValue, newValue in
            guard !voiceInput.isListening,
                  Self.isSingleInsertedLineBreak(from: oldValue, to: newValue) else { return }
            details = oldValue
            submit()
        }
        .onChange(of: detailCommitSignal) { _, _ in
            resetAfterDetailedCommit()
        }
        .onChange(of: voiceInput.transcript) { _, newValue in
            guard !newValue.isEmpty else { return }
            ignoredSmartExpression = nil
            draft = newValue
        }
        .onChange(of: voiceInput.isListening) { wasListening, isListening in
            if isListening {
                isFinalizingVoiceSubmission = false
                isVoicePulsing = true
            } else {
                isVoicePulsing = false
                if wasListening && shouldSubmitVoiceWhenStopped {
                    voiceProcessingStartedAt = .now
                    isFinalizingVoiceSubmission = true
                    voiceSubmissionTask?.cancel()
                    voiceSubmissionTask = Task { @MainActor in
                        await Task.yield()
                        guard !Task.isCancelled,
                              shouldSubmitVoiceWhenStopped,
                              !voiceInput.isListening else { return }
                        await submitVoiceRecording()
                        shouldSubmitVoiceWhenStopped = false
                        withAnimation(.easeOut(duration: 0.2)) {
                            isFinalizingVoiceSubmission = false
                        }
                    }
                }
            }
        }
        .onChange(of: isRecordsPage) { _, recordsPage in
            focusedField = nil
            isRecordsComposerPresented = false
            if recordsPage && voiceInput.isListening {
                shouldSubmitVoiceWhenStopped = false
                voiceInput.stop()
            }
        }
        .onDisappear {
            shouldSubmitVoiceWhenStopped = false
            isFinalizingVoiceSubmission = false
            voiceSubmissionTask?.cancel()
            smartParsingTask?.cancel()
            voiceInput.stop()
            pendingVoiceClarification = nil
        }
        .alert("Голосовой ввод", isPresented: isShowingVoiceError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(voiceInput.errorMessage ?? "Не удалось распознать речь.")
        }
    }


    private var sharedCaptureChrome: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                withAnimation(MemoryMotion.page(reduceMotion: reduceMotion)) {
                    isRecordsComposerPresented = true
                }
                DispatchQueue.main.async { focusedField = .title }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(MemoryTheme.onAccent)
                    .frame(width: 58, height: 58)
                    .background(MemoryTheme.accent)
                    .clipShape(Circle())
                    .overlay {
                        Circle().stroke(MemoryTheme.onAccent.opacity(0.16), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Добавить напоминание")
            .zIndex(20)
        }
        .frame(maxWidth: 620)
        .padding(.horizontal, 22)
        .padding(.bottom, 10)
    }

#if os(macOS)
    private var desktopCaptureBody: some View {
        VStack(spacing: 28) {
            desktopOrbCluster(size: 240)
            compactBody
                .frame(maxWidth: 540)
                .opacity(isFinalizingVoiceSubmission || pendingVoiceClarification != nil ? 0 : 1)
                .allowsHitTesting(!isFinalizingVoiceSubmission && pendingVoiceClarification == nil)
                .accessibilityHidden(isFinalizingVoiceSubmission || pendingVoiceClarification != nil)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 18)
        .padding(.horizontal, 28)
    }

    private func desktopOrbCluster(size: CGFloat) -> some View {
        VStack(spacing: 18) {
            Button(action: handleVoiceTap) {
                GlassVoiceOrb(
                    isListening: voiceInput.isListening,
                    isProcessing: isFinalizingVoiceSubmission,
                    isPulsing: isVoicePulsing || isFinalizingVoiceSubmission,
                    size: size
                )
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isFinalizingVoiceSubmission || pendingVoiceClarification != nil)
            .accessibilityLabel(voiceOrbAccessibilityLabel)

            ZStack {
                if pendingVoiceClarification != nil {
                    voiceClarificationCard
                        .transition(.opacity.combined(with: .offset(y: 8)))
                } else if isFinalizingVoiceSubmission {
                    voiceProcessingStatus.transition(.opacity)
                }
            }

        }
    }
#endif

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: isDocked ? 10 : 14) {
            HStack(spacing: isDocked ? 10 : 12) {
                if presentation != .standard && !voiceInput.isListening {
                    Button(action: submit) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(trimmedDraft.isEmpty ? Color.secondary : MemoryTheme.onAccent)
                            .frame(width: compactControlSize, height: compactControlSize)
                            .background(
                                trimmedDraft.isEmpty
                                    ? Color.secondary.opacity(0.1)
                                    : MemoryTheme.accent
                            )
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmedDraft.isEmpty)
                    .accessibilityLabel("Добавить напоминание")
                } else if isDocked {
                    voiceButton(size: compactControlSize)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(MemoryTheme.accent)
                        .frame(width: compactControlSize, height: compactControlSize)
                        .background(MemoryTheme.accent.opacity(0.12))
                        .clipShape(Circle())
                }

                TextField(
                    voiceInput.isListening ? "Говорите…" : "Что нужно запомнить?",
                    text: $draft,
                    axis: .vertical
                )
                    .textFieldStyle(.plain)
                    .lineLimit(1...(voiceInput.isListening ? 9 : 3))
                    .focused($focusedField, equals: .title)
                    .allowsHitTesting(!voiceInput.isListening && !isFinalizingVoiceSubmission)
                    .accessibilityIdentifier("quickCaptureField")
                    .onSubmit(handleSubmitKey)
#if os(iOS)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.sentences)
#endif

                if !isDocked && presentation == .standard {
                    voiceButton(size: compactControlSize)
                }

                if !voiceInput.isListening && isComposerExpanded {
                    detailsDisclosureButton(size: compactControlSize)
                }

                if showsCancelButton {
                    Button(action: cancelDraft) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: compactControlSize, height: compactControlSize)
                            .background(Color.secondary.opacity(0.09))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Отменить ввод")
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }

            captureMetadataChips

            if isDescriptionPresented {
                TextField("Описание, ссылка или важные детали", text: $details, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...5)
                    .focused($focusedField, equals: .description)
#if os(iOS)
                    .submitLabel(.done)
                    .onSubmit(handleSubmitKey)
#endif
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                    }
                    .accessibilityIdentifier("quickCaptureDescriptionField")
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

        }
        .padding(usesMinimalDesktopChrome ? 12 : (isDocked ? 12 : 18))
        .modifier(QuickCaptureSurfaceModifier(isMinimal: usesMinimalDesktopChrome))
    }

    private var homeBody: some View {
        GeometryReader { proxy in
            let isEditing = focusedField != nil
            // The same orb and composer survive all voice phases.
            let orbSize: CGFloat = isEditing ? 140 : min(240, max(180, proxy.size.height * 0.48))
            VStack(spacing: 20) {
                homeVoiceOrb(orbSize: orbSize)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if pendingVoiceClarification != nil {
                    voiceClarificationCard
                        .transition(.opacity.combined(with: .offset(y: 10)))
                }
                if isFinalizingVoiceSubmission {
                    voiceProcessingStatus
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }
                homePrioritySection
                    .opacity(isEditing || voiceInput.isListening || isFinalizingVoiceSubmission ? 0 : 1)
                    .allowsHitTesting(!isEditing && !voiceInput.isListening && !isFinalizingVoiceSubmission)
                    .accessibilityHidden(isEditing || voiceInput.isListening || isFinalizingVoiceSubmission)
                    .offset(y: voiceInput.isListening ? 12 : 0)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, MemoryTheme.pageInset)
            .animation(reduceMotion ? nil : MemoryTheme.motion, value: isEditing)
        }
    }

    private func homeVoiceOrb(orbSize: CGFloat) -> some View {
        Button(action: handleHomeVoiceTap) {
            GlassVoiceOrb(
                isListening: voiceInput.isListening,
                isProcessing: isFinalizingVoiceSubmission,
                isPulsing: isVoicePulsing || isFinalizingVoiceSubmission,
                size: orbSize,
                isVisible: !isRecordsPage
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isFinalizingVoiceSubmission || pendingVoiceClarification != nil)
        .highPriorityGesture(
            DragGesture(minimumDistance: 8)
                .updating($isOrbDragging) { _, dragging, _ in
                    dragging = true
                }
                .onEnded { _ in lastOrbDrag = .now }
        )
        .accessibilityIdentifier("homeVoiceOrb")
        .accessibilityLabel(voiceOrbAccessibilityLabel)
    }

    private var voiceProcessingStatus: some View {
        VStack(spacing: 6) {
            if reduceMotion {
                processingStatusText(processingMessages[0])
            } else {
                TimelineView(.periodic(from: voiceProcessingStartedAt, by: 1.05)) { context in
                    let elapsed = max(0, context.date.timeIntervalSince(voiceProcessingStartedAt))
                    let index = Int(elapsed / 1.05) % processingMessages.count
                    processingStatusText(processingMessages[index])
                        .id(index)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.24), value: index)
                }
            }

            Text("Собираю заголовок, контекст и время")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 380)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Вникаю в контекст. Собираю заголовок, контекст и время")
    }

    private func processingStatusText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 19, weight: .medium, design: .rounded))
            .multilineTextAlignment(.center)
    }

    @ViewBuilder private var voiceClarificationCard: some View {
        if let pendingVoiceClarification {
            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text(
                        pendingVoiceClarification.decision == .time
                            ? "Во сколько напомнить?"
                            : "Когда напомнить?"
                    )
                    .font(.system(size: 19, weight: .medium, design: .rounded))

                    Text(pendingVoiceClarification.draft.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    ForEach(clarificationOptions(for: pendingVoiceClarification)) { option in
                        Button {
                            resolveVoiceClarification(option)
                        } label: {
                            VStack(spacing: 2) {
                                Text(option.title)
                                    .font(.caption.weight(.semibold))
                                if let caption = option.caption {
                                    Text(caption)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .padding(.horizontal, 6)
                            .background(Color.secondary.opacity(0.085))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: 430)
            .background(MemoryTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func clarificationOptions(
        for clarification: PendingVoiceClarification
    ) -> [VoiceClarificationOption] {
        switch clarification.decision {
        case .date:
            return [
                VoiceClarificationOption(
                    id: "today",
                    title: "Сегодня",
                    caption: QuickDuePreset.today.date.map(shortTime),
                    dueDate: QuickDuePreset.today.date
                ),
                VoiceClarificationOption(
                    id: "tomorrow",
                    title: "Завтра",
                    caption: QuickDuePreset.tomorrow.date.map(shortTime),
                    dueDate: QuickDuePreset.tomorrow.date
                ),
                VoiceClarificationOption(
                    id: "none",
                    title: "Без срока",
                    caption: nil,
                    dueDate: nil
                )
            ]
        case .time:
            return [
                timeClarificationOption(id: "morning", title: "Утром", hour: 8, clarification: clarification),
                timeClarificationOption(id: "lunch", title: "В обед", hour: 13, clarification: clarification),
                timeClarificationOption(id: "evening", title: "Вечером", hour: 19, clarification: clarification)
            ]
        }
    }

    private func timeClarificationOption(
        id: String,
        title: String,
        hour: Int,
        clarification: PendingVoiceClarification
    ) -> VoiceClarificationOption {
        let calendar = Calendar.current
        let baseDate = clarification.draft.dueDate ?? clarification.referenceDate
        var date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: baseDate)
        if clarification.draft.dueDate == nil,
           let candidate = date,
           candidate <= clarification.referenceDate {
            date = calendar.date(byAdding: .day, value: 1, to: candidate)
        }
        return VoiceClarificationOption(
            id: id,
            title: title,
            caption: date.map(shortTime),
            dueDate: date
        )
    }

    private func shortTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func resolveVoiceClarification(_ option: VoiceClarificationOption) {
        guard let clarification = pendingVoiceClarification else { return }
        commitVoiceDraft(
            clarification.draft,
            details: clarification.details,
            dueDate: option.dueDate,
            referenceDate: clarification.referenceDate
        )
        withAnimation(.easeOut(duration: 0.2)) {
            pendingVoiceClarification = nil
        }
    }

    private var processingMessages: [String] {
        ["Вникаю в контекст…", "Отделяю главное…", "Уточняю время…"]
    }

    private var voiceOrbAccessibilityLabel: String {
        if isFinalizingVoiceSubmission { return "Вникаю в контекст" }
        return voiceInput.isListening ? "Остановить запись" : "Начать голосовой ввод"
    }

    private var homePrioritySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isPriorityOverdue ? "Требует внимания" : "Ближайшее")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    if additionalPriorityCount > 0 {
                        Text("Ещё просрочено: \(additionalPriorityCount)")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }

                Spacer()
            }

            if let priorityItem {
                HomePriorityCard(
                    item: priorityItem,
                    isOverdue: isPriorityOverdue,
                    onToggle: onTogglePriority,
                    onEdit: onEditPriority,
                    linkedCount: priorityLinkedCount,
                    onOpenLinkedRecord: onOpenPriorityLinkedRecord
                )
            } else {
                HStack(spacing: 13) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(MemoryTheme.accent)
                        .frame(width: 36, height: 36)
                        .background(MemoryTheme.accent.opacity(0.1))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Всё под контролем")
                            .font(.body.weight(.semibold))
                        Text("Ближайших напоминаний пока нет")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(17)
                .memoryCard()
            }
        }
    }

    private var homeComposer: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 10) {
                if !voiceInput.isListening {
                    Button(action: submit) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(trimmedDraft.isEmpty ? Color.secondary : MemoryTheme.onAccent)
                            .frame(width: 40, height: 40)
                            .background(
                                trimmedDraft.isEmpty
                                    ? Color.secondary.opacity(0.1)
                                    : MemoryTheme.accent
                            )
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmedDraft.isEmpty)
                    .accessibilityLabel("Добавить напоминание")
                    .transition(.scale.combined(with: .opacity))
                }

                TextField(
                    isFinalizingVoiceSubmission ? "Обрабатываю…" : voiceInput.isListening ? "Говорите…" : "Записать мысль",
                    text: $draft,
                    axis: .vertical
                )
                    .textFieldStyle(.plain)
                    .lineLimit(1...(voiceInput.isListening ? 9 : 3))
                    .fixedSize(horizontal: false, vertical: true)
                    .focused($focusedField, equals: .title)
                    .allowsHitTesting(!voiceInput.isListening)
#if os(iOS)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.sentences)
#endif
                    .onSubmit(handleSubmitKey)
                    .accessibilityIdentifier("quickCaptureField")
                    .padding(.vertical, 9)
                    .contentTransition(.interpolate)

                if !voiceInput.isListening && (focusedField == .title || !trimmedDraft.isEmpty) {
                    detailsDisclosureButton(size: 40)

                    Button(action: cancelDraft) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 40, height: 40)
                            .background(Color.secondary.opacity(0.09))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Отменить ввод")
                    .transition(.scale.combined(with: .opacity))
                }
            }

            captureMetadataChips

            if !voiceInput.isListening && isDescriptionPresented {
                TextField("Описание, ссылка или важные детали", text: $details, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...2)
                    .focused($focusedField, equals: .description)
#if os(iOS)
                    .submitLabel(.done)
                    .onSubmit(handleSubmitKey)
#endif
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .accessibilityIdentifier("quickCaptureDescriptionField")
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.07), radius: 22, y: 10)
    }

    private func handleHomeVoiceTap() {
        guard !isPageSwiping, !isOrbDragging, Date.now.timeIntervalSince(lastOrbDrag) > 0.3 else { return }
        handleVoiceTap()
    }

    private func handleVoiceTap() {
        dismissKeyboard()

        if voiceInput.isListening {
            voiceInput.stop()
            return
        }

        voiceSubmissionTask?.cancel()
        isFinalizingVoiceSubmission = false
        shouldSubmitVoiceWhenStopped = true
        Task { @MainActor in
            await voiceInput.toggle(currentText: draft)
            if !voiceInput.isListening && voiceInput.errorMessage != nil {
                shouldSubmitVoiceWhenStopped = false
            }
        }
    }

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedDetails: String { details.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var inferredEntryKind: EntryKind? {
        guard ignoredKindExpression != draft else { return nil }
        return EntryKindInference.infer(from: trimmedDraft, hasDate: resolvedDueDate != nil)
    }

    private var effectiveEntryKind: EntryKind {
        entryKindOverride ?? inferredEntryKind ?? account.defaultEntryKind
    }

    private var resolvedDueDate: Date? {
        smartResult?.dueDate ?? preset.date
    }

    private var resolvedEventEndDate: Date? {
        nil
    }

    private var isVoicePreviewActive: Bool {
        voiceInput.isListening || isFinalizingVoiceSubmission || shouldSubmitVoiceWhenStopped
    }

    private var capturePreviewState: VoiceCapturePreview {
        isVoicePreviewActive ? VoiceCapturePreview.classify(trimmedDraft) : .single
    }

    @ViewBuilder private var captureMetadataChips: some View {
        if !trimmedDraft.isEmpty && capturePreviewState != .uncertain {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if case .multiple(let count) = capturePreviewState {
                        Text(VoiceEntryCountLabel.short(count))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MemoryTheme.accent)
                            .padding(.horizontal, 11)
                            .frame(height: 32)
                            .background(MemoryTheme.accent.opacity(0.1))
                            .clipShape(Capsule())
                            .accessibilityLabel("Предварительно: \(VoiceEntryCountLabel.short(count))")
                    } else if capturePreviewState == .single {
                        if let smartResult {
                            HStack(spacing: 5) {
                                Text(smartDateLabel(for: smartResult.dueDate))
                                    .font(.caption.weight(.semibold))
                                if !voiceInput.isListening {
                                    Button {
                                        ignoredSmartExpression = draft
                                        self.smartResult = nil
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .frame(width: 20, height: 20)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Убрать распознанную дату")
                                }
                            }
                            .foregroundStyle(MemoryTheme.accent)
                            .padding(.leading, 11)
                            .padding(.trailing, voiceInput.isListening ? 11 : 5)
                            .frame(height: 32)
                            .background(MemoryTheme.accent.opacity(0.1))
                            .clipShape(Capsule())
                            .accessibilityIdentifier("smartDateSuggestion")
                        }
                        if !isVoicePreviewActive || inferredEntryKind != nil || entryKindOverride != nil {
                            Button {
                                ignoredKindExpression = draft
                                entryKindOverride = effectiveEntryKind == .event ? .reminder : .event
                            } label: {
                                Text(effectiveEntryKind.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(entryKindChipColor)
                                    .padding(.horizontal, 11)
                                    .frame(height: 32)
                                    .background(entryKindChipColor.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(voiceInput.isListening)
                            .accessibilityLabel("Тип записи: \(effectiveEntryKind.title)")
                            .accessibilityHint("Нажмите, чтобы изменить")
                        }
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var entryKindChipColor: Color {
        effectiveEntryKind == .event ? MemoryTheme.warm : MemoryTheme.accent
    }

    private func detailsDisclosureButton(size: CGFloat) -> some View {
        Button(action: openDetailedEditor) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .background(Color.secondary.opacity(0.09))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Подробные настройки")
        .accessibilityHint("Открывает полный редактор записи")
    }

    private func openDetailedEditor() {
        let title = smartResult?.title ?? trimmedDraft
        let kind = effectiveEntryKind
        onOpenDetails(
            title,
            Item.normalizedDetails(trimmedDetails),
            kind,
            resolvedDueDate,
            resolvedEventEndDate
        )
        focusedField = nil
    }

    private var showsCancelButton: Bool {
#if os(macOS)
        !trimmedDraft.isEmpty || presentation == .desktopInline
#else
        !trimmedDraft.isEmpty
#endif
    }

    private var compactControlSize: CGFloat { isDocked ? 44 : 40 }

    private var usesMinimalDesktopChrome: Bool {
#if os(macOS)
        presentation == .desktopInline
#else
        false
#endif
    }
    private var isComposerExpanded: Bool {
        guard !voiceInput.isListening else { return false }
        return focusedField != nil
            || !trimmedDraft.isEmpty
            || smartResult != nil
            || isDescriptionPresented
            || !trimmedDetails.isEmpty
    }

    private func voiceButton(size: CGFloat) -> some View {
        Button {
            handleVoiceTap()
        } label: {
            Image(systemName: voiceInput.isListening ? "stop.fill" : "mic.fill")
                .font(.system(size: isDocked ? 17 : 14, weight: .semibold))
                .foregroundStyle(voiceInput.isListening ? MemoryTheme.onAccent : MemoryTheme.accent)
                .frame(width: size, height: size)
                .background(
                    voiceInput.isListening
                        ? Color.red.opacity(0.88)
                        : MemoryTheme.accent.opacity(isDocked ? 0.16 : 0.12)
                )
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(voiceInput.isListening ? "Остановить запись" : "Голосовой ввод")
    }

    private var isShowingVoiceError: Binding<Bool> {
        Binding(
            get: { voiceInput.errorMessage != nil },
            set: { if !$0 { voiceInput.errorMessage = nil } }
        )
    }

    private func isSelected(_ option: QuickDuePreset) -> Bool {
        smartResult == nil && preset == option
    }

    private func smartDateLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let time = MemoryDateFormatting.time(date)
        if calendar.isDateInToday(date) { return "Сегодня · \(time)" }
        if calendar.isDateInTomorrow(date) { return "Завтра · \(time)" }
        return "\(MemoryDateFormatting.editorDate(date)) · \(time)"
    }

    private func handleSubmitKey() {
        if trimmedDraft.isEmpty {
            dismissKeyboard()
        } else {
            submit()
        }
    }

    private static func isSingleInsertedLineBreak(from oldValue: String, to newValue: String) -> Bool {
        guard newValue.count == oldValue.count + 1 else { return false }

        for index in newValue.indices where newValue[index] == "\n" || newValue[index] == "\r" {
            var candidate = newValue
            candidate.remove(at: index)
            if candidate == oldValue { return true }
        }

        return false
    }

    private func dismissKeyboard() {
        focusedField = nil
    }

    private func toggleDescription() {
        if isDescriptionPresented {
            focusedField = .title
            withAnimation(.easeInOut(duration: 0.22)) {
                isDescriptionPresented = false
            }
        } else {
            withAnimation(.easeInOut(duration: 0.22)) {
                isDescriptionPresented = true
            }
            DispatchQueue.main.async {
                focusedField = .description
            }
        }
    }

    @MainActor
    private func submitVoiceRecording() async {
        let spokenText = voiceInput.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spokenText.isEmpty else { return }

        smartParsingTask?.cancel()
        let referenceDate = Date.now
        let calendar = Calendar.current
        let parsedResult = NaturalLanguageDateParser.parse(
            spokenText,
            now: referenceDate,
            calendar: calendar
        )
        let locallySplit = VoiceUtteranceSplitter.split(spokenText)
        let localResult: VoiceCaptureResult?
        if isStructuredInterpreterEnabled || locallySplit.count > 1 {
            localResult = VoiceCaptureResult.local(
                spokenText,
                now: referenceDate,
                calendar: calendar,
                defaultKind: account.defaultEntryKind
            )
        } else {
            localResult = nil
        }
        let interpreted = await enhancedVoiceDraft(
            for: spokenText,
            fallback: localResult,
            now: referenceDate,
            calendar: calendar
        )
        let normalizedDetails = Item.normalizedDetails(trimmedDetails)
        let fallbackDate = preset.date
        if let interpreted, interpreted.entries.count > 1 {
            let reconciledEntries = interpreted.entries.map { entry -> VoiceCaptureEntry in
                let parsed = NaturalLanguageDateParser.parse(
                    entry.sourceText, now: referenceDate, calendar: calendar
                )
                // A date from the semantic parser belongs to this entry; do not
                // overwrite it with a date from another part of the utterance.
                let draft = entry.draft.dueDate == nil && parsed?.dueDate != nil
                    ? VoiceDraftReconciler.reconcile(semantic: entry.draft, deterministic: parsed)
                    : entry.draft
                return VoiceCaptureEntry(
                    sourceText: entry.sourceText,
                    draft: draft,
                    kind: entry.kind,
                    endDate: entry.endDate,
                    linkGroup: entry.linkGroup
                )
            }
            resetVoiceComposer()
            let reviewEntries = reconciledEntries.map {
                VoiceReviewEntry($0, defaultReminderMinutes: account.defaultReminderMinutes(for: $0.kind))
            }
            onReviewBatch(VoiceBatchReview(referenceDate: referenceDate, entries: reviewEntries))
            return
        }

        let interpretedEntry = interpreted?.entries.first
        let reconciledDraft = interpretedEntry.map {
            VoiceDraftReconciler.reconcile(semantic: $0.draft, deterministic: parsedResult)
        }
        let finalDraft: ReminderDraft

        if let reconciledDraft {
            finalDraft = ReminderDraft(
                transcript: spokenText,
                title: reconciledDraft.title,
                details: normalizedDetails ?? reconciledDraft.details,
                dueDate: reconciledDraft.dueDate,
                reminderOffsets: reconciledDraft.reminderOffsets,
                confidence: reconciledDraft.confidence,
                ambiguities: reconciledDraft.ambiguities
            )
        } else if let parsedResult {
            finalDraft = ReminderDraft(
                transcript: spokenText,
                title: parsedResult.title,
                details: normalizedDetails,
                dueDate: parsedResult.dueDate,
                reminderOffsets: parsedResult.reminderOffsets,
                confidence: .high,
                ambiguities: []
            )
        } else {
            finalDraft = ReminderDraft(
                transcript: spokenText,
                title: spokenText,
                details: normalizedDetails,
                dueDate: nil,
                reminderOffsets: [],
                confidence: .medium,
                ambiguities: [.missingDate]
            )
        }

        resetVoiceComposer()

        if interpretedEntry?.kind == .event && finalDraft.dueDate == nil {
            onReviewBatch(VoiceBatchReview(
                referenceDate: referenceDate,
                entries: [VoiceReviewEntry(VoiceCaptureEntry(
                    sourceText: spokenText,
                    draft: finalDraft,
                    kind: .event,
                    endDate: interpretedEntry?.endDate
                ), defaultReminderMinutes: account.defaultReminderMinutes(for: .event))]
            ))
            return
        }

        if isVoiceClarificationEnabled,
           let decision = VoiceClarificationPolicy.decision(for: finalDraft) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                pendingVoiceClarification = PendingVoiceClarification(
                    decision: decision,
                    draft: finalDraft,
                    details: finalDraft.details,
                    fallbackDate: fallbackDate,
                    referenceDate: referenceDate
                )
            }
            return
        }

        commitVoiceDraft(
            finalDraft,
            details: finalDraft.details,
            dueDate: finalDraft.dueDate ?? fallbackDate,
            kind: interpretedEntry?.kind,
            endDate: interpretedEntry?.endDate,
            referenceDate: referenceDate
        )
    }

    private func resetVoiceComposer() {
        draft = ""
        details = ""
        isDescriptionPresented = false
        preset = defaultPreset
        ignoredSmartExpression = nil
        ignoredKindExpression = nil
        entryKindOverride = nil
        smartResult = nil
        dismissKeyboard()
    }

    private func commitVoiceDraft(
        _ voiceDraft: ReminderDraft,
        details: String?,
        dueDate: Date?,
        kind: EntryKind? = nil,
        endDate: Date? = nil,
        referenceDate: Date
    ) {
        let inferredKind = EntryKindInference.infer(
            from: voiceDraft.transcript,
            hasDate: dueDate != nil
        )
        let entryKind: EntryKind = dueDate == nil
            ? .reminder
            : (kind ?? inferredKind ?? account.defaultEntryKind)
        let itemID = onAdd(
            voiceDraft.title,
            details,
            entryKind,
            dueDate,
            entryKind == .event ? endDate : nil,
            voiceDraft.reminderOffsets.isEmpty ? nil : voiceDraft.reminderOffsets
        )
        if let itemID {
            VoicePersonalizationStore.beginCapture(
                itemID: itemID,
                transcript: voiceDraft.transcript,
                title: voiceDraft.title,
                details: details,
                dueDate: dueDate,
                referenceDate: referenceDate
            )
        }
    }

    @MainActor
    private func enhancedVoiceDraft(
        for spokenText: String,
        fallback: VoiceCaptureResult?,
        now: Date,
        calendar: Calendar
    ) async -> VoiceCaptureResult? {
        guard isDeepSeekInterpreterEnabled,
              let remoteVoiceInterpreter else { return fallback }

        do {
            return try await withThrowingTaskGroup(of: VoiceCaptureResult.self) { group in
                group.addTask {
                    try await remoteVoiceInterpreter(spokenText, now, calendar)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(5))
                    throw VoiceSemanticError.timedOut
                }

                guard let result = try await group.next() else {
                    throw VoiceSemanticError.emptyResult
                }
                group.cancelAll()
                if let fallback, fallback.entries.count > 1, result.entries.count == 1 {
                    return fallback
                }
                return result
            }
        } catch {
            return fallback
        }
    }

    private func cancelDraft() {
        shouldSubmitVoiceWhenStopped = false
        isFinalizingVoiceSubmission = false
        voiceSubmissionTask?.cancel()
        smartParsingTask?.cancel()
        voiceInput.stop()
        draft = ""
        details = ""
        isDescriptionPresented = false
        preset = defaultPreset
        ignoredSmartExpression = nil
        ignoredKindExpression = nil
        entryKindOverride = nil
        smartResult = nil
        dismissKeyboard()
        if isRecordsPage {
            withAnimation(.easeInOut(duration: 0.2)) {
                isRecordsComposerPresented = false
            }
        }
#if os(macOS)
        if presentation == .desktopInline {
            onDismiss()
        }
#endif
    }

    private func resetAfterDetailedCommit() {
        draft = ""
        details = ""
        isDescriptionPresented = false
        preset = defaultPreset
        ignoredSmartExpression = nil
        ignoredKindExpression = nil
        entryKindOverride = nil
        smartResult = nil
        focusedField = nil

        if isRecordsPage {
            withAnimation(.easeInOut(duration: 0.2)) {
                isRecordsComposerPresented = false
            }
        }
#if os(macOS)
        if presentation == .desktopInline {
            onDismiss()
        }
#endif
    }

    private func submit() {
        guard !trimmedDraft.isEmpty else { return }
        if effectiveEntryKind == .event, resolvedDueDate == nil {
            openDetailedEditor()
            return
        }
        shouldSubmitVoiceWhenStopped = false
        isFinalizingVoiceSubmission = false
        voiceSubmissionTask?.cancel()
        smartParsingTask?.cancel()
        voiceInput.stop()
        if let smartResult {
            _ = onAdd(
                smartResult.title,
                Item.normalizedDetails(trimmedDetails),
                effectiveEntryKind,
                smartResult.dueDate,
                nil,
                smartResult.reminderOffsets.isEmpty ? nil : smartResult.reminderOffsets
            )
        } else {
            _ = onAdd(
                trimmedDraft,
                Item.normalizedDetails(trimmedDetails),
                effectiveEntryKind,
                preset.date,
                nil,
                nil
            )
        }
        draft = ""
        details = ""
        isDescriptionPresented = false
        preset = defaultPreset
        ignoredSmartExpression = nil
        ignoredKindExpression = nil
        entryKindOverride = nil
        dismissKeyboard()
        if isRecordsPage {
            withAnimation(.easeInOut(duration: 0.2)) {
                isRecordsComposerPresented = false
            }
        }
    }
}
