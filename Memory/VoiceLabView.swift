import SwiftUI

struct VoiceLabView: View {
    @EnvironmentObject private var account: AccountSyncController
    @StateObject private var store = VoiceLabStore()
    @State private var statistics = VoiceLabStatistics(examples: [])
    @AppStorage(VoicePipelineSettings.structuredInterpreterEnabledKey)
    private var isStructuredInterpreterEnabled = false
    @AppStorage(VoicePipelineSettings.deepSeekInterpreterEnabledKey)
    private var isDeepSeekInterpreterEnabled = false
    @AppStorage(VoicePipelineSettings.clarificationEnabledKey)
    private var isVoiceClarificationEnabled = true
    @AppStorage(VoicePipelineSettings.personalLearningEnabledKey)
    private var isPersonalVoiceLearningEnabled = false

    var showsHeader = true
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
            HStack(spacing: 14) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Color.primary.opacity(0.055), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Назад")
                Text("Voice Lab")
                    .font(.system(size: 21, weight: .medium, design: .rounded))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .frame(height: 88)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    statisticsCard
                    settingsCard
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
        }
        .background(MemoryTheme.background.ignoresSafeArea())
        .tint(MemoryTheme.accent)
        .onAppear {
            guard !VoiceReviewTesting.usesIsolatedStorage else { return }
            isStructuredInterpreterEnabled = true
            store.refresh()
            statistics = VoiceLabStatistics(examples: store.examples)
        }
        .onChange(of: store.examples) { _, examples in
            statistics = VoiceLabStatistics(examples: examples)
        }
    }

    private var statisticsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Локальный разбор").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metric("Без ошибок", matches: statistics.exact)
                metric("Заголовок", matches: statistics.titles)
                metric("Описание", matches: statistics.details)
                metric("Дата", matches: statistics.dates)
            }
            Text("Проверено примеров: \(statistics.total)").font(.subheadline)
            Text("Это проверка локального разбора, не оценка DeepSeek. Исправления записей сохраняются автоматически.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).memoryCard()
    }

    private func metric(_ title: String, matches: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(statistics.percentage(matches).map { "\($0)%" } ?? "—")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("DeepSeek", isOn: $isDeepSeekInterpreterEnabled)
                .disabled(!account.isConfigured || !account.isSignedIn)
                .onChange(of: isDeepSeekInterpreterEnabled) { _, enabled in
                    if enabled { isStructuredInterpreterEnabled = true }
                }
                .accessibilityHint("Облачное понимание речи; при ошибке используется локальный разбор")
            if !account.isSignedIn {
                Text("DeepSeek доступен после входа в аккаунт.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider().opacity(0.45)
            Toggle("Уточнения", isOn: $isVoiceClarificationEnabled)
                .accessibilityHint("Спросить, если срок неясен")
            Divider().opacity(0.45)
            Toggle("Мои примеры", isOn: $isPersonalVoiceLearningEnabled)
                .disabled(!isDeepSeekInterpreterEnabled)
            Text("При включении ваши исправления используются как примеры в запросах к DeepSeek.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.body.weight(.medium)).toggleStyle(.switch)
        .padding(18).memoryCard()
    }
}
