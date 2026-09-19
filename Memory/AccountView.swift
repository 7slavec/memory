import AVFoundation
import Speech
import SwiftData
import SwiftUI
import UserNotifications
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct AccountView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Войти"
        case signUp = "Создать аккаунт"
        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var account: AccountSyncController
    @AppStorage(AppAppearance.storageKey) private var appAppearance: AppAppearance = .system
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var microphoneStatus: AVAuthorizationStatus = .notDetermined
    @State private var speechStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if !account.isConfigured {
                        notConfiguredView
                    } else if account.isSignedIn {
                        signedInView
                    } else {
                        authenticationView
                    }
                }
                .padding(24)
                .frame(maxWidth: 560, alignment: .top)
                .frame(maxWidth: .infinity)
            }
            .background(MemoryTheme.background)
            .navigationTitle(account.isSignedIn ? "Профиль" : "Аккаунт")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Закрыть")
                }
            }
            .task { await refreshPermissions() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await refreshPermissions() }
            }
        }
#if os(macOS)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 680, idealHeight: 760)
#endif
        .alert("Не получилось", isPresented: isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Неизвестная ошибка")
        }
    }

    private var notConfiguredView: some View {
        VStack(spacing: 18) {
            accountIcon(systemName: "icloud.slash")
            Text("Синхронизация почти готова")
                .font(.title3.weight(.semibold))
            Text("Осталось подключить бесплатный проект Supabase. До этого Norka продолжит работать локально, как и раньше.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 48)
    }

    private var authenticationView: some View {
        VStack(spacing: 20) {
            accountIcon(systemName: "person.crop.circle.badge.plus")

            VStack(spacing: 6) {
                Text("Одинаковые записи везде")
                    .font(.title3.weight(.semibold))
                Text("Войдите с одной почтой на Mac и iPhone. Без интернета записи останутся доступными и синхронизируются позже.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Picker("Режим", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            VStack(spacing: 12) {
                TextField("Почта", text: $email)
                    .textContentType(.emailAddress)
#if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
#endif
                SecureField("Пароль — минимум 6 символов", text: $password)
                    .textContentType(mode == .signUp ? .newPassword : .password)
            }
            .textFieldStyle(.roundedBorder)

            Button(action: submit) {
                HStack(spacing: 9) {
                    if isWorking { ProgressView().controlSize(.small) }
                    Text(mode.rawValue)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(MemoryTheme.accent)
            .disabled(!canSubmit || isWorking)

            if case .needsEmailConfirmation = account.state {
                Label("Проверьте почту и подтвердите регистрацию, затем войдите.", systemImage: "envelope.badge")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var signedInView: some View {
        VStack(alignment: .leading, spacing: 24) {
            profileHero

            settingsSection(title: "Оформление") {
                HStack(spacing: 14) {
                    settingsIcon("circle.lefthalf.filled", color: MemoryTheme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Тема приложения")
                            .font(.body.weight(.semibold))
                        Text(appAppearance.details)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                Picker("Тема приложения", selection: $appAppearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            settingsSection(title: "По умолчанию") {
                HStack(spacing: 14) {
                    settingsIcon("bell.badge.fill", color: MemoryTheme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Когда напоминать")
                            .font(.body.weight(.semibold))
                        Text("Для новых записей с датой")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Picker("Стандартное уведомление", selection: defaultReminderBinding) {
                        ForEach(ReminderLeadTime.allCases) { option in
                            Text(option.compactTitle).tag(option.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                Divider().padding(.leading, 50)

                Text("В отдельной записи можно установить несколько уведомлений или полностью их отключить.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            settingsSection(title: "Разрешения") {
                PermissionRow(
                    icon: "bell.fill",
                    title: "Уведомления",
                    status: notificationPermissionTitle,
                    color: notificationPermissionColor,
                    actionTitle: notificationActionTitle,
                    action: handleNotificationAction
                )

                Divider().padding(.leading, 50)

                PermissionRow(
                    icon: "waveform",
                    title: "Голосовой ввод",
                    status: voicePermissionTitle,
                    color: voicePermissionColor,
                    actionTitle: voiceActionTitle,
                    action: openVoiceSettings
                )
            }

            settingsSection(title: "Синхронизация") {
                HStack(spacing: 14) {
                    settingsIcon(statusIcon, color: syncStatusColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(account.statusText)
                            .font(.body.weight(.semibold))
                        Text(syncDetails)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if account.state == .syncing {
                        ProgressView().controlSize(.small)
                    }
                }

                Divider().padding(.leading, 50)

                Button {
                    Task {
                        await account.synchronize(
                            modelContext: modelContext,
                            showsProgress: true
                        )
                    }
                } label: {
                    Label("Синхронизировать сейчас", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(MemoryTheme.accent)
                .disabled(account.state == .syncing)
            }

            settingsSection(title: "Аккаунт") {
                Button(role: .destructive) {
                    Task { await signOut() }
                } label: {
                    HStack(spacing: 14) {
                        settingsIcon("rectangle.portrait.and.arrow.right", color: .red)
                        Text("Выйти на этом устройстве")
                            .font(.body.weight(.medium))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
            }
        }
    }

    private var profileHero: some View {
        HStack(spacing: 16) {
            Text(profileInitial)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 66, height: 66)
                .background(MemoryTheme.accent.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text("Аккаунт Norka")
                    .font(.title3.weight(.bold))
                Text(account.email ?? "Без почты")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Label("Записи доступны на всех устройствах", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(MemoryTheme.accent)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .memoryCard()
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 13) {
                content()
            }
            .padding(16)
            .memoryCard()
        }
    }

    private func settingsIcon(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 36, height: 36)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func accountIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(MemoryTheme.accent)
            .frame(width: 68, height: 68)
            .background(MemoryTheme.accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var statusIcon: String {
        switch account.state {
        case .syncing: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.triangle.fill"
        default: "checkmark.circle.fill"
        }
    }

    private var syncStatusColor: Color {
        if case .failed = account.state { return .red }
        return MemoryTheme.accent
    }

    private var syncDetails: String {
        switch account.state {
        case let .synced(date):
            return "Последняя проверка: \(Self.syncDateFormatter.string(from: date))"
        case let .failed(message):
            return message
        case .syncing:
            return "Проверяем изменения на всех устройствах"
        default:
            return "Записи доступны на устройстве даже без сети"
        }
    }

    private var profileInitial: String {
        guard let first = account.email?.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return "N"
        }
        return String(first).uppercased()
    }

    private var notificationPermissionTitle: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: "Разрешены"
        case .denied: "Выключены в системе"
        case .notDetermined: "Ещё не запрашивались"
        @unknown default: "Статус неизвестен"
        }
    }

    private var notificationPermissionColor: Color {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: MemoryTheme.accent
        case .denied: .red
        default: .secondary
        }
    }

    private var notificationActionTitle: String? {
        switch notificationStatus {
        case .notDetermined: "Разрешить"
        case .denied: "Настройки"
        default: nil
        }
    }

    private var voicePermissionTitle: String {
        if voicePermissionNeedsSettings {
            return "Нужен доступ"
        }
        if microphoneStatus == .authorized && speechStatus == .authorized {
            return "Разрешён"
        }
        return "Запросится при использовании"
    }

    private var voicePermissionColor: Color {
        if voicePermissionNeedsSettings {
            return .red
        }
        if microphoneStatus == .authorized && speechStatus == .authorized {
            return MemoryTheme.accent
        }
        return .secondary
    }

    private var voiceActionTitle: String? {
        voicePermissionNeedsSettings ? "Настройки" : nil
    }

    private var voicePermissionNeedsSettings: Bool {
        microphoneStatus == .denied || microphoneStatus == .restricted
            || speechStatus == .denied || speechStatus == .restricted
    }

    private func refreshPermissions() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        speechStatus = SFSpeechRecognizer.authorizationStatus()
    }

    private func handleNotificationAction() {
        if notificationStatus == .notDetermined {
            Task {
                _ = try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                await refreshPermissions()
            }
        } else {
            openNotificationSettings()
        }
    }

    private func openNotificationSettings() {
#if os(iOS)
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
#elseif os(macOS)
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
#endif
    }

    private func openVoiceSettings() {
#if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
#elseif os(macOS)
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
#endif
    }

    private static let syncDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter
    }()

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6
    }

    private var defaultReminderBinding: Binding<Int> {
        Binding(
            get: { account.defaultReminderMinutes },
            set: { value in
                Task {
                    do {
                        try await account.setDefaultReminderMinutes(value)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        )
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func submit() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                switch mode {
                case .signIn:
                    try await account.signIn(email: cleanEmail, password: password)
                case .signUp:
                    try await account.signUp(email: cleanEmail, password: password)
                }
                if account.isSignedIn {
                    await account.synchronize(modelContext: modelContext)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func signOut() async {
        isWorking = true
        do {
            try await account.signOut()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let status: String
    let color: Color
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(status)
                    .font(.caption)
                    .foregroundStyle(color)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let actionTitle {
                Button(actionTitle, action: action)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(color)
            }
        }
    }
}
