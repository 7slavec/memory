import SwiftUI

struct VoiceLabView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var account: AccountSyncController
    @StateObject private var store = VoiceLabStore()
    @StateObject private var voiceInput = VoiceInputController()
    @AppStorage(VoicePipelineSettings.structuredInterpreterEnabledKey)
    private var isStructuredInterpreterEnabled = false
    @AppStorage(VoicePipelineSettings.deepSeekInterpreterEnabledKey)
    private var isDeepSeekInterpreterEnabled = false
    @AppStorage(VoicePipelineSettings.clarificationEnabledKey)
    private var isVoiceClarificationEnabled = true
    @AppStorage(VoicePipelineSettings.personalLearningEnabledKey)
    private var isPersonalVoiceLearningEnabled = false
    @State private var transcript = ""
    @State private var expectedTranscript = ""
    @State private var expectedTitle = ""
    @State private var expectedDetails = ""
    @State private var expectedDueDate = Date.now.addingTimeInterval(3_600)
    @State private var expectsDueDate = false
    @State private var referenceDate = Date.now
    @State private var editingExampleID: UUID?
    @State private var showsSavedFeedback = false
    @FocusState private var isTranscriptFocused: Bool

    let onClose: () -> Void

    private let interpreter = LocalVoiceIntentInterpreter()

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    overviewCard
                    inputCard

                    if let draft = currentDraft {
                        resultCard(draft)
                        expectedResultCard(draft)
                    }

                    savedExamplesSection
                }
                .frame(maxWidth: 720)
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(MemoryTheme.background.ignoresSafeArea())
        .tint(MemoryTheme.accent)
        .onChange(of: voiceInput.transcript) { _, newValue in
            guard !newValue.isEmpty else { return }
            transcript = newValue
        }
        .onDisappear {
            voiceInput.stop()
        }
        .onAppear {
            // Local interpretation is the stable fallback for every Voice Lab mode,
            // so it no longer needs a separate user-facing switch.
            isStructuredInterpreterEnabled = true
            store.refresh()
        }
        .alert("Голосовой ввод", isPresented: isShowingVoiceError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(voiceInput.errorMessage ?? "Не удалось распознать речь.")
        }
#if os(macOS)
        .frame(minWidth: 620, idealWidth: 760, minHeight: 680, idealHeight: 820)
#endif
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Color.primary.opacity(0.055))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Назад")

            VStack(alignment: .leading, spacing: 2) {
                Text("Voice Lab")
                    .font(.system(size: 21, weight: .medium, design: .rounded))
                Text("Проверка понимания речи")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if showsSavedFeedback {
                Label("Сохранено", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MemoryTheme.accent)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .padding(.horizontal, 22)
        .frame(height: 88)
        .background(MemoryTheme.background)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.45)
        }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MemoryTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(MemoryTheme.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Безопасный контур проверки")
                        .font(.body.weight(.semibold))
                    Text("Локальный разбор работает всегда. Облачные функции можно подключать отдельно.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(MemoryTheme.accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Для текущего теста")
                        .font(.subheadline.weight(.semibold))
                    Text("Включите DeepSeek и «Уточнения». «Мои примеры» пока оставьте выключенными.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(MemoryTheme.accent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Toggle(isOn: $isDeepSeekInterpreterEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DeepSeek")
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(account.isSignedIn
                         ? "Точнее выделяет главное"
                         : "Доступно после входа в аккаунт")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!account.isConfigured || !account.isSignedIn)
            .onChange(of: isDeepSeekInterpreterEnabled) { _, isEnabled in
                if isEnabled {
                    isStructuredInterpreterEnabled = true
                }
            }
            .accessibilityHint("Включает облачный семантический разбор; при ошибке используется локальный")

            Divider().opacity(0.45)

            Toggle(isOn: $isVoiceClarificationEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Уточнения")
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text("Спросит, если срок неясен")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider().opacity(0.45)

            Toggle(isOn: $isPersonalVoiceLearningEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Мои примеры")
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text("Передаёт исправления в DeepSeek")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!isDeepSeekInterpreterEnabled)
        }
        .padding(18)
        .memoryCard()
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Фраза")
                    .font(.system(size: 17, weight: .medium, design: .rounded))

                Spacer(minLength: 12)

                Button(action: toggleRecording) {
                    Image(systemName: voiceInput.isListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(voiceInput.isListening ? Color.red : MemoryTheme.accent)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(voiceInput.isListening ? "Остановить запись" : "Записать пример")
            }

            TextEditor(text: $transcript)
                .font(.body)
                .focused($isTranscriptFocused)
                .frame(minHeight: 92, maxHeight: 150)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Color.primary.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if transcript.isEmpty {
                        Text("Например: завтра вечером позвонить маме")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 17)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }

            HStack {
                Text(voiceInput.isListening ? "Слушаю…" : "Можно говорить или печатать")
                    .font(.caption)
                    .foregroundStyle(voiceInput.isListening ? MemoryTheme.accent : .secondary)

                Spacer(minLength: 12)

                if !transcript.isEmpty {
                    Button("Очистить", action: resetEditor)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .memoryCard()
    }

    private func resultCard(_ draft: ReminderDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Как поняла Norka")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                Spacer(minLength: 10)
                Text(draft.confidence.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(confidenceColor(draft.confidence))
                    .padding(.horizontal, 9)
                    .frame(minHeight: 26)
                    .background(confidenceColor(draft.confidence).opacity(0.11))
                    .clipShape(Capsule())
            }

            resultRow(title: "Заголовок", value: draft.title)
            resultRow(title: "Описание", value: draft.details ?? "—")
            resultRow(title: "Дата", value: draft.dueDate.map(Self.dateFormatter.string) ?? "Без срока")

            if !draft.ambiguities.isEmpty {
                FlowLayout(spacing: 7) {
                    ForEach(Array(draft.ambiguities), id: \.self) { ambiguity in
                        Label(ambiguity.title, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .frame(minHeight: 28)
                            .background(Color.primary.opacity(0.045))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(18)
        .memoryCard()
        .onAppear {
            guard expectedTitle.isEmpty else { return }
            copyDraftToExpected(draft)
        }
    }

    private func expectedResultCard(_ draft: ReminderDraft) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Как должно быть")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                    Text("Исправление станет проверочным примером")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 10)

                Button("Взять результат") {
                    copyDraftToExpected(draft)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(MemoryTheme.accent)
            }

            labTextField("Что было сказано", text: $expectedTranscript)
            labTextField("Заголовок", text: $expectedTitle)
            labTextField("Описание — необязательно", text: $expectedDetails)

            Toggle("Есть дата и время", isOn: $expectsDueDate)
                .font(.subheadline.weight(.medium))

            if expectsDueDate {
                DatePicker(
                    "Ожидаемая дата",
                    selection: $expectedDueDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
            }

            Button(action: saveCurrentExample) {
                Label(
                    editingExampleID == nil ? "Сохранить проверку" : "Обновить проверку",
                    systemImage: "checkmark"
                )
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(canSaveExample ? MemoryTheme.accent : Color.secondary.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSaveExample)
        }
        .padding(18)
        .memoryCard()
    }

    private var savedExamplesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Проверки")
                        .font(.system(size: 19, weight: .medium, design: .rounded))
                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                if store.examples.isEmpty {
                    Button("Добавить примеры") {
                        store.addStarterExamplesIfNeeded()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(MemoryTheme.accent)
                }
            }

            if store.examples.isEmpty {
                Text("Сохраните первую фразу или добавьте стартовый набор. Здесь будет видно, какие сценарии уже работают эталонно, а какие ещё нужно улучшить.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .memoryCard()
            } else {
                metricsGrid

                VStack(spacing: 10) {
                    ForEach(store.examples) { example in
                        exampleRow(example)
                    }
                }
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            metricCell("Речь", matches: evaluations.filter(\.transcriptMatches).count)
            metricCell("Заголовок", matches: evaluations.filter(\.titleMatches).count)
            metricCell("Контекст", matches: evaluations.filter(\.detailsMatch).count)
            metricCell("Дата", matches: evaluations.filter(\.dateMatches).count)
        }
    }

    private func metricCell(_ title: String, matches: Int) -> some View {
        let total = max(store.examples.count, 1)
        let percent = Int((Double(matches) / Double(total) * 100).rounded())

        return VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(percent)%")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("\(matches) из \(total)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func exampleRow(_ example: VoiceLabExample) -> some View {
        let evaluation = example.evaluation(using: interpreter)

        return HStack(spacing: 8) {
            Button {
                load(example)
            } label: {
                HStack(spacing: 13) {
                    Image(systemName: evaluation.isExactMatch ? "checkmark" : "exclamationmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(evaluation.isExactMatch ? MemoryTheme.accent : MemoryTheme.warm)
                        .frame(width: 34, height: 34)
                        .background((evaluation.isExactMatch ? MemoryTheme.accent : MemoryTheme.warm).opacity(0.12))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(example.transcript)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(evaluation.isExactMatch ? "Совпадает с эталоном" : mismatchText(evaluation))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                store.remove(example)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Удалить проверку")
        }
        .padding(15)
        .memoryCard()
    }

    private func resultRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labTextField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text, axis: .vertical)
            .lineLimit(1...3)
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(Color.primary.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var currentDraft: ReminderDraft? {
        interpreter.interpret(
            transcript,
            now: referenceDate,
            calendar: .current
        ).draft
    }

    private var canSaveExample: Bool {
        !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !expectedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !expectedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var evaluations: [VoiceLabEvaluation] {
        store.examples.map { $0.evaluation(using: interpreter) }
    }

    private var summaryText: String {
        guard !store.examples.isEmpty else { return "Пока нет сохранённых сценариев" }
        return "\(store.examples.count) примеров · отдельная оценка каждого слоя"
    }

    private var isShowingVoiceError: Binding<Bool> {
        Binding(
            get: { voiceInput.errorMessage != nil },
            set: { if !$0 { voiceInput.errorMessage = nil } }
        )
    }

    private func confidenceColor(_ confidence: VoiceInterpretationConfidence) -> Color {
        switch confidence {
        case .high: MemoryTheme.accent
        case .medium: MemoryTheme.warm
        case .low: .red
        }
    }

    private func toggleRecording() {
        isTranscriptFocused = false
        if !voiceInput.isListening {
            transcript = ""
            resetExpectedFields()
            referenceDate = .now
        }
        Task {
            await voiceInput.toggle(currentText: "")
        }
    }

    private func copyDraftToExpected(_ draft: ReminderDraft) {
        expectedTranscript = transcript
        expectedTitle = draft.title
        expectedDetails = draft.details ?? ""
        expectsDueDate = draft.dueDate != nil
        expectedDueDate = draft.dueDate ?? Date.now.addingTimeInterval(3_600)
    }

    private func saveCurrentExample() {
        guard canSaveExample else { return }
        let example = VoiceLabExample(
            id: editingExampleID ?? UUID(),
            transcript: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
            expectedTranscript: expectedTranscript.trimmingCharacters(in: .whitespacesAndNewlines),
            expectedTitle: expectedTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            expectedDetails: Item.normalizedDetails(expectedDetails),
            expectedDueDate: expectsDueDate ? expectedDueDate : nil,
            referenceDate: referenceDate,
            timeZoneIdentifier: TimeZone.current.identifier
        )
        store.save(example)
        editingExampleID = example.id

        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            showsSavedFeedback = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                showsSavedFeedback = false
            }
        }
    }

    private func load(_ example: VoiceLabExample) {
        voiceInput.stop()
        editingExampleID = example.id
        transcript = example.transcript
        expectedTranscript = example.expectedTranscript ?? example.transcript
        expectedTitle = example.expectedTitle
        expectedDetails = example.expectedDetails ?? ""
        expectsDueDate = example.expectedDueDate != nil
        expectedDueDate = example.expectedDueDate ?? Date.now.addingTimeInterval(3_600)
        referenceDate = example.referenceDate
        isTranscriptFocused = false
    }

    private func resetEditor() {
        voiceInput.stop()
        editingExampleID = nil
        transcript = ""
        referenceDate = .now
        resetExpectedFields()
    }

    private func resetExpectedFields() {
        expectedTitle = ""
        expectedTranscript = ""
        expectedDetails = ""
        expectedDueDate = Date.now.addingTimeInterval(3_600)
        expectsDueDate = false
    }

    private func mismatchText(_ evaluation: VoiceLabEvaluation) -> String {
        var components: [String] = []
        if !evaluation.transcriptMatches { components.append("распознавание") }
        if !evaluation.titleMatches { components.append("заголовок") }
        if !evaluation.detailsMatch { components.append("описание") }
        if !evaluation.dateMatches { components.append("дата") }
        return "Нужно улучшить: " + components.joined(separator: ", ")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM, HH:mm"
        return formatter
    }()
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let availableWidth = proposal.width ?? .infinity
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var measuredWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > availableWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            measuredWidth = max(measuredWidth, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }

        return (
            CGSize(width: min(measuredWidth, availableWidth), height: y + lineHeight),
            points
        )
    }
}
