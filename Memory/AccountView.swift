import SwiftData
import SwiftUI

struct AccountView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Войти"
        case signUp = "Создать аккаунт"
        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var account: AccountSyncController
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
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
            .frame(maxWidth: 470, maxHeight: .infinity, alignment: .top)
            .frame(maxWidth: .infinity)
            .background(MemoryTheme.background)
            .navigationTitle("Аккаунт")
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
        }
#if os(macOS)
        .frame(width: 520, height: 560)
#else
        .presentationDetents([.medium, .large])
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
            Text("Осталось подключить бесплатный проект Supabase. До этого Memory продолжит работать локально, как и раньше.")
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
        VStack(spacing: 20) {
            accountIcon(systemName: "checkmark.icloud.fill")

            VStack(spacing: 5) {
                Text("Синхронизация включена")
                    .font(.title3.weight(.semibold))
                Text(account.email ?? "Аккаунт Memory")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Image(systemName: statusIcon)
                    .foregroundStyle(MemoryTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.statusText).font(.body.weight(.medium))
                    Text("Записи доступны на этом устройстве даже без сети")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .memoryCard()

            Button {
                Task { await account.synchronize(modelContext: modelContext) }
            } label: {
                Label("Синхронизировать сейчас", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(MemoryTheme.accent)
            .disabled(account.state == .syncing)

            Button("Выйти на этом устройстве", role: .destructive) {
                Task { await signOut() }
            }
            .disabled(isWorking)
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

    private var statusIcon: String {
        account.state == .syncing ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill"
    }

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6
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
