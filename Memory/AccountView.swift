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

    private enum AuthenticationField: Hashable {
        case email
        case password
        case passwordConfirmation
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var account: AccountSyncController
    @Query(sort: \Item.timestamp, order: .reverse) private var items: [Item]
    @AppStorage(AppAppearance.storageKey) private var appAppearance: AppAppearance = .system
    @AppStorage(ReminderScheduler.applicationNotificationsEnabledKey)
    private var applicationNotificationsEnabled = true
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var isEmbeddedAuthenticationPresented = false
    @State private var isVoiceLabPresented = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var microphoneStatus: AVAuthorizationStatus = .notDetermined
    @State private var speechStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @FocusState private var authenticationField: AuthenticationField?
    let embedded: Bool
    let onOpenArchive: (() -> Void)?
    let showsDismissButton: Bool
    let onContinueLocally: (() -> Void)?
    let onAuthenticationCompleted: (() -> Void)?
    let forcesAuthentication: Bool

    init(
        embedded: Bool = false,
        onOpenArchive: (() -> Void)? = nil,
        showsDismissButton: Bool = true,
        onContinueLocally: (() -> Void)? = nil,
        onAuthenticationCompleted: (() -> Void)? = nil,
        forcesAuthentication: Bool = false
    ) {
        self.embedded = embedded
        self.onOpenArchive = onOpenArchive
        self.showsDismissButton = showsDismissButton
        self.onContinueLocally = onContinueLocally
        self.onAuthenticationCompleted = onAuthenticationCompleted
        self.forcesAuthentication = forcesAuthentication
    }

    var body: some View {
        Group {
            if embedded {
                accountContent
            } else {
                NavigationStack {
                    ZStack(alignment: .topTrailing) {
                        accountContent

                        if showsDismissButton {
                            Button { dismiss() } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 42, height: 42)
                                    .background(Color.primary.opacity(0.055))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Закрыть")
                            .padding(.top, 12)
                            .padding(.trailing, 18)
                        }
                    }
#if os(iOS)
                    .toolbar(.hidden, for: .navigationBar)
#endif
                }
            }
        }
        .task {
            if email.isEmpty && !forcesAuthentication {
                email = account.lastSignedInEmail ?? ""
            }
            await refreshPermissions()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshPermissions() }
        }
        .onChange(of: account.isSignedIn) { _, isSignedIn in
            if isSignedIn {
                isEmbeddedAuthenticationPresented = false
            }
        }
#if os(macOS)
        .frame(
            minWidth: embedded ? 0 : 560,
            idealWidth: 620,
            minHeight: embedded ? 0 : 680,
            idealHeight: 760
        )
#endif
        .alert("Не получилось", isPresented: isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Неизвестная ошибка")
        }
        .sheet(isPresented: $isVoiceLabPresented) {
            VoiceLabView {
                isVoiceLabPresented = false
            }
        }
    }

    private var accountContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if embedded {
                    Text(isEmbeddedAuthenticationPresented && !account.isSignedIn ? "Аккаунт" : "Профиль")
                        .font(.system(size: 30, weight: .medium, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Group {
                    if forcesAuthentication {
                        authenticationView
                    } else if account.isSignedIn {
                        signedInView
                    } else if embedded && !isEmbeddedAuthenticationPresented {
#if os(macOS)
                        desktopProfileView
#else
                        authenticationView
#endif
                    } else if !account.isConfigured {
                        notConfiguredView
                    } else {
                        authenticationView
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: embedded ? 700 : 620, alignment: .top)
            .frame(maxWidth: .infinity)
        }
        .background(MemoryTheme.background)
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
        VStack(spacing: 18) {
#if os(macOS)
            if embedded {
                HStack {
                    Button {
                        authenticationField = nil
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEmbeddedAuthenticationPresented = false
                        }
                    } label: {
                        Label("Назад в профиль", systemImage: "arrow.left")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(Color.primary.opacity(0.045))
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }
            }
#endif

            authenticationFormSurface {
                VStack(spacing: 20) {
                    if mode == .signUp,
                       case .needsEmailConfirmation = account.state {
                        emailConfirmationView
                    } else {
                        authenticationForm
                    }

                    if let onContinueLocally {
                        VStack(spacing: 10) {
                            HStack(spacing: 12) {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(height: 1)
                                Text("или")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Rectangle()
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(height: 1)
                            }

                            Button(action: onContinueLocally) {
                                VStack(spacing: 3) {
                                    Text("Продолжить локально")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("Данные останутся на этом устройстве")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Color.primary.opacity(0.045))
                                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                                }
                                .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: 420)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: embedded ? 520 : 500, alignment: .top)
    }

    private var authenticationForm: some View {
        VStack(spacing: 24) {
            VStack(spacing: 14) {
                Image("NorkaLogo")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(.primary)
                    .frame(width: 112, height: 34)
                    .accessibilityHidden(true)

                VStack(spacing: 7) {
                    Text(mode == .signIn ? "С возвращением" : "Создайте аккаунт")
                        .font(.system(size: 27, weight: .medium, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text(mode == .signIn
                         ? "Ваши напоминания будут доступны на всех устройствах."
                         : "Одна почта — все записи на iPhone и Mac.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 12) {
                authenticationFieldSurface(icon: "envelope.fill") {
                    TextField("Почта", text: $email)
                        .textFieldStyle(.plain)
                        .textContentType(.emailAddress)
                        .focused($authenticationField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { authenticationField = .password }
#if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
#endif
                }

                authenticationFieldSurface(icon: "lock.fill") {
                    SecureField(mode == .signIn ? "Пароль" : "Пароль — от 6 символов", text: $password)
                        .textFieldStyle(.plain)
                        .textContentType(mode == .signUp ? .newPassword : .password)
                        .focused($authenticationField, equals: .password)
                        .submitLabel(mode == .signIn ? .go : .next)
                        .onSubmit {
                            if mode == .signIn {
                                submit()
                            } else {
                                authenticationField = .passwordConfirmation
                            }
                        }
                }

                if mode == .signUp {
                    authenticationFieldSurface(
                        icon: "checkmark.shield.fill",
                        isInvalid: passwordConfirmationIsInvalid
                    ) {
                        SecureField("Повторите пароль", text: $passwordConfirmation)
                            .textFieldStyle(.plain)
                            .textContentType(.newPassword)
                            .focused($authenticationField, equals: .passwordConfirmation)
                            .submitLabel(.go)
                            .onSubmit(submit)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))

                    if passwordConfirmationIsInvalid {
                        Text("Пароли не совпадают")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .transition(.opacity)
                    }
                }
            }

            Button(action: submit) {
                HStack(spacing: 9) {
                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Text(mode.rawValue)
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(MemoryTheme.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(MemoryTheme.accent.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit || isWorking)
            .opacity(canSubmit && !isWorking ? 1 : 0.46)

            HStack(spacing: 5) {
                Text(mode == .signIn ? "Нет аккаунта?" : "Уже есть аккаунт?")
                    .foregroundStyle(.secondary)

                Button(mode == .signIn ? "Создать" : "Войти") {
                    switchAuthenticationMode()
                }
                .buttonStyle(.plain)
                .foregroundStyle(MemoryTheme.accent)
                .fontWeight(.semibold)
            }
            .font(.subheadline)
        }
        .frame(maxWidth: 420)
    }

    private var emailConfirmationView: some View {
        VStack(spacing: 22) {
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(MemoryTheme.accent)
                .frame(width: 72, height: 72)
                .background(MemoryTheme.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(spacing: 8) {
                Text("Проверьте почту")
                    .font(.system(size: 27, weight: .medium, design: .rounded))

                Text("Мы отправили ссылку для подтверждения на \(email). После этого вернитесь и войдите.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Вернуться ко входу") {
                withAnimation(.easeInOut(duration: 0.22)) {
                    mode = .signIn
                    password = ""
                    passwordConfirmation = ""
                }
            }
            .buttonStyle(.plain)
            .font(.body.weight(.semibold))
            .foregroundStyle(MemoryTheme.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(MemoryTheme.accent.gradient)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(maxWidth: 420)
    }

    @ViewBuilder private func authenticationFormSurface<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
#if os(macOS)
        content()
            .padding(30)
            .memoryCard()
            .frame(maxWidth: 480)
#else
        content()
            .frame(maxWidth: 460)
#endif
    }

    private func authenticationFieldSurface<Content: View>(
        icon: String,
        isInvalid: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isInvalid ? Color.red : MemoryTheme.accent)
                .frame(width: 22)

            content()
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 52)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(isInvalid ? Color.red.opacity(0.55) : Color.primary.opacity(0.07), lineWidth: 1)
        }
    }

    @ViewBuilder private var signedInView: some View {
#if os(macOS)
        desktopProfileView
#else
        legacySignedInView
#endif
    }

#if os(macOS)
    private var desktopProfileView: some View {
        VStack(alignment: .leading, spacing: 26) {
            desktopProfileHero

            desktopSettingsSection(title: "Создание") {
                HStack(spacing: 14) {
                    settingsIcon(account.defaultEntryKind.icon, color: MemoryTheme.accent)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Новая запись")
                            .font(.body.weight(.medium))
                        Text("Если в тексте нет явной подсказки")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Picker("Новая запись", selection: defaultEntryKindBinding) {
                        ForEach(EntryKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }

            desktopSettingsSection(title: "Уведомления") {
                HStack(spacing: 14) {
                    settingsIcon("bell.fill", color: MemoryTheme.accent)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Уведомления")
                            .font(.body.weight(.medium))
                        Text(applicationNotificationsEnabled ? "Включены" : "Выключены")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Toggle("Уведомления", isOn: applicationNotificationsBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                Divider().padding(.leading, 50)

                HStack(spacing: 14) {
                    settingsIcon("clock.fill", color: MemoryTheme.accent)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Когда напоминать")
                            .font(.body.weight(.medium))
                        Text("Для новых записей")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Picker("Стандартное уведомление", selection: defaultReminderBinding) {
                        ForEach(ReminderLeadTime.allCases) { option in
                            Text(option.compactTitle).tag(option.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            desktopSettingsSection(title: "Оформление") {
                HStack(spacing: 14) {
                    settingsIcon("circle.lefthalf.filled", color: MemoryTheme.accent)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Тема приложения")
                            .font(.body.weight(.medium))
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

            desktopSettingsSection(title: "Голосовой ввод") {
                Button {
                    isVoiceLabPresented = true
                } label: {
                    HStack(spacing: 14) {
                        settingsIcon("waveform.badge.magnifyingglass", color: MemoryTheme.accent)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Voice Lab")
                                .font(.body.weight(.medium))
                            Text("Все настройки и тесты голосового ввода")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 12)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Открывает лабораторию голосового ввода")
            }

            if let onOpenArchive {
                desktopSettingsSection(title: "Записи") {
                    Button(action: onOpenArchive) {
                        HStack(spacing: 14) {
                            settingsIcon("archivebox.fill", color: MemoryTheme.accent)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Архив")
                                    .font(.body.weight(.medium))
                                Text("Выполненные напоминания")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 12)

                            if completedAccountItemsCount > 0 {
                                Text("\(completedAccountItemsCount)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(MemoryTheme.accent)
                                    .padding(.horizontal, 9)
                                    .frame(minHeight: 26)
                                    .background(MemoryTheme.accent.opacity(0.11))
                                    .clipShape(Capsule())
                            }

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Открывает выполненные напоминания")
                }
            }

            if account.isSignedIn {
                Button(role: .destructive) {
                    Task { await signOut() }
                } label: {
                    HStack(spacing: 10) {
                        if isWorking {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                        }
                        Text("Выйти")
                    }
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isEmbeddedAuthenticationPresented = true
                    }
                } label: {
                    Text("Войти или создать аккаунт")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MemoryTheme.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(MemoryTheme.accent.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Открывает вход и регистрацию")
            }
        }
    }

    private var desktopProfileHero: some View {
        VStack(spacing: 14) {
            Text(profileInitial)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(MemoryTheme.onAccent)
                .frame(width: 92, height: 92)
                .background(MemoryTheme.accent.gradient)
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: MemoryTheme.accent.opacity(0.2), radius: 20, y: 8)

            HStack(spacing: 7) {
                Text(account.email ?? "Локальный профиль")
                    .font(.system(size: 21, weight: .medium, design: .rounded))
                    .lineLimit(1)

                Image(systemName: account.isSignedIn ? statusIcon : "icloud.slash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(account.isSignedIn ? syncStatusColor : Color.secondary)
                    .accessibilityLabel(account.isSignedIn ? account.statusText : "Локальный профиль")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func desktopSettingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 13) {
                content()
            }
            .padding(17)
            .memoryCard()
        }
    }
#endif

    private var legacySignedInView: some View {
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
                    settingsIcon(account.defaultEntryKind.icon, color: MemoryTheme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Новая запись")
                            .font(.body.weight(.semibold))
                        Text("Когда тип не указан в тексте")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                }

                Picker("Новая запись", selection: defaultEntryKindBinding) {
                    ForEach(EntryKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Divider().padding(.leading, 50)

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
        VStack(spacing: 12) {
            Text(profileInitial)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(MemoryTheme.onAccent)
                .frame(width: 82, height: 82)
                .background(MemoryTheme.accent.gradient)
                .clipShape(Circle())
                .shadow(color: MemoryTheme.accent.opacity(0.22), radius: 18, y: 8)

            VStack(spacing: 5) {
                Text(account.email ?? "Без почты")
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Label("Записи доступны на всех устройствах", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(MemoryTheme.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
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
        email.trimmingCharacters(in: .whitespacesAndNewlines).contains("@")
            && password.count >= 6
            && (mode == .signIn || passwordConfirmation == password)
    }

    private var passwordConfirmationIsInvalid: Bool {
        mode == .signUp
            && !passwordConfirmation.isEmpty
            && passwordConfirmation != password
    }

    private func switchAuthenticationMode() {
        errorMessage = nil
        passwordConfirmation = ""
        authenticationField = nil

        withAnimation(.easeInOut(duration: 0.22)) {
            mode = mode == .signIn ? .signUp : .signIn
        }
    }

    private var completedAccountItemsCount: Int {
        items.lazy.filter {
            $0.deletedAt == nil
                && $0.ownerID == account.userID
                && $0.isCompleted
        }.count
    }

    private var applicationNotificationsBinding: Binding<Bool> {
        Binding(
            get: { applicationNotificationsEnabled },
            set: { setApplicationNotificationsEnabled($0) }
        )
    }

    private func setApplicationNotificationsEnabled(_ isEnabled: Bool) {
        applicationNotificationsEnabled = isEnabled
        ReminderScheduler.setApplicationNotificationsEnabled(isEnabled)

        for item in items where item.ownerID == account.userID {
            if isEnabled,
               item.deletedAt == nil,
               !item.isCompleted,
               item.notificationsEnabled,
               let dueDate = item.dueDate {
                let id = item.id
                let title = item.title
                let details = item.details
                let offsets = item.effectiveReminderOffsets
                Task {
                    do {
                        try await ReminderScheduler.schedule(
                            id: id,
                            title: title,
                            details: details,
                            at: dueDate,
                            offsets: offsets
                        )
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            } else {
                ReminderScheduler.cancel(id: item.id)
            }
        }
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

    private var defaultEntryKindBinding: Binding<EntryKind> {
        Binding(
            get: { account.defaultEntryKind },
            set: { value in
                Task {
                    do {
                        try await account.setDefaultEntryKind(value)
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
        guard canSubmit, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        authenticationField = nil
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
                    onAuthenticationCompleted?()
                    if !embedded && showsDismissButton {
                        dismiss()
                    }
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
            if !embedded {
                dismiss()
            }
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
