import SwiftData
import SwiftUI
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
    @EnvironmentObject private var account: AccountSyncController
    @Query(sort: \Item.timestamp, order: .reverse) private var items: [Item]
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var isEmbeddedAuthenticationPresented = false
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
    }

    @ViewBuilder private var accountContent: some View {
        if !forcesAuthentication && (account.isSignedIn || (embedded && !isEmbeddedAuthenticationPresented)) {
            ProfileScreen(
                archiveCount: items.filter { $0.ownerID == account.userID && $0.deletedAt == nil && !RecordLinkIndex.canAdd($0) }.count,
                onOpenArchive: onOpenArchive,
                onSignIn: { isEmbeddedAuthenticationPresented = true }
            )
        } else {
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

    private func accountIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(MemoryTheme.accent)
            .frame(width: 68, height: 68)
            .background(MemoryTheme.accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

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

}
