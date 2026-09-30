import SwiftUI
import SwiftData

struct ProfileScreen: View {
    @EnvironmentObject private var account: AccountSyncController
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var localPage = ProfilePage.profile
    @State private var showsAvatar = false
    @State private var isWorking = false
    @State private var error: String?
    let archiveCount: Int
    var isVisible = true
    var onBack: (() -> Void)? = nil
    var onOpenArchive: (() -> Void)? = nil
    var navigation: Binding<ProfilePage>? = nil
    var showsHeader = true
    var archiveContent: AnyView? = nil
    let onSignIn: () -> Void

    private var page: ProfilePage { navigation?.wrappedValue ?? localPage }
    private func navigate(_ destination: ProfilePage) {
        if let navigation { navigation.wrappedValue = destination }
        else { localPage = destination }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader { header }
            ZStack(alignment: .topLeading) {
                profileScroll { overview }
                    .memoryPageVisibility(page == .profile, hiddenX: -MemoryMotion.pageDistance)
                if page != .profile {
                    Group {
                        switch page {
                        case .profile: EmptyView()
                        case .notifications: profileScroll { ProfileNotificationsPage() }
                        case .sync: profileScroll { synchronization }
                        case .archive: archiveContent
                        case .voiceLab: VoiceLabView(showsHeader: false) { navigate(.profile) }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .id(page)
                    .transition(MemoryMotion.forward(reduceMotion: reduceMotion))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            .animation(MemoryMotion.page(reduceMotion: reduceMotion), value: page)
        }
        .background(MemoryTheme.background)
        .task(id: isVisible) {
            guard isVisible else { return }
            // Keep account publications and network setup outside the page transition.
            do { try await Task.sleep(for: .milliseconds(350)) }
            catch { return }
            await account.refreshPersonalization()
        }
        .onChange(of: isVisible) { _, visible in if !visible { navigate(.profile) } }
        .alert("Не получилось", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func profileScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content().frame(maxWidth: 560)
                .padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 32)
                .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack {
            if page != .profile || onBack != nil {
                Button {
                    if page == .profile { onBack?() } else { navigate(.profile) }
                } label: {
                    Image(systemName: "arrow.left").font(.system(size: 18))
                        .frame(width: 44, height: 44).background(MemoryTheme.card, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("Назад")
            } else { Color.clear.frame(width: 44, height: 44) }
            Spacer()
            Text(page.rawValue).font(.system(size: 17, weight: .medium))
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 22).padding(.vertical, 10)
    }

    private var overview: some View {
        VStack(spacing: 16) {
            VStack(spacing: 16) {
                Button { showsAvatar = true } label: {
                    ProfileAvatarView(avatar: account.personalization.avatar, size: 96)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "pencil").font(.system(size: 12, weight: .medium))
                                .frame(width: 28, height: 28).background(MemoryTheme.raised, in: Circle())
                        }
                }
                .buttonStyle(.plain).accessibilityLabel("Изменить аватар")
                .accessibilityValue("\(account.personalization.avatar.animal.title), \(account.personalization.avatar.fur.title), \(account.personalization.avatar.tint.title)")
                .popover(isPresented: $showsAvatar, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                    AvatarEditor()
                        .presentationCompactAdaptation(.popover)
                        .presentationBackground(.ultraThinMaterial)
                }
                Text(account.email ?? "Локальный профиль")
                    .font(.system(size: 22, weight: .medium)).multilineTextAlignment(.center)
                    .textSelection(.enabled)
                Button { navigate(.sync) } label: {
                    Label(account.profileStatusText, systemImage: account.profileSyncSymbol)
                        .font(.system(size: 13)).foregroundStyle(account.profileHasSyncError ? MemoryTheme.danger : .secondary)
                }
                .buttonStyle(.plain).accessibilityHint("Открывает состояние синхронизации")
            }
            .frame(maxWidth: .infinity).padding(.bottom, 16)

            VStack(spacing: 0) {
                ProfileNavigationRow(title: "Уведомления", icon: "bell") { navigate(.notifications) }
                ProfileThemePicker()
            }.memoryCard()

            VStack(spacing: 0) {
                if archiveContent != nil || onOpenArchive != nil {
                    ProfileNavigationRow(title: "Архив", icon: "archivebox", value: archiveCount == 0 ? nil : "\(archiveCount)") {
                        if archiveContent != nil { navigate(.archive) } else { onOpenArchive?() }
                    }
                }
                ProfileNavigationRow(title: "Voice Lab", icon: "waveform") { navigate(.voiceLab) }
            }.memoryCard()

            Button {
                if !account.isSignedIn { onSignIn(); return }
                isWorking = true
                Task {
                    do { try await account.signOut() }
                    catch { self.error = error.localizedDescription }
                    isWorking = false
                }
            } label: {
                HStack(spacing: 8) {
                    if isWorking { ProgressView().controlSize(.small) }
                    else { Image(systemName: account.isSignedIn ? "rectangle.portrait.and.arrow.right" : "person.crop.circle") }
                    Text(account.isSignedIn ? "Выйти" : "Войти в аккаунт")
                }.frame(maxWidth: .infinity)
            }
            .buttonStyle(MemoryActionStyle())
            .disabled(isWorking || account.isSavingPersonalization)
            .padding(.top, 16)
        }
    }

    private var synchronization: some View {
        VStack(spacing: 16) {
            VStack(spacing: 16) {
                Image(systemName: account.profileSyncSymbol).font(.system(size: 38))
                Text(account.profileStatusText).font(.system(size: 20, weight: .medium))
                if let message = account.personalizationError ?? account.linkSyncError {
                    Text(message).font(.system(size: 14)).foregroundStyle(MemoryTheme.danger)
                } else if case let .failed(message) = account.state {
                    Text(message).font(.system(size: 14)).foregroundStyle(MemoryTheme.danger)
                }
            }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(24).memoryCard()
            if account.isSignedIn {
                Button {
                    isWorking = true
                    Task {
                        await account.synchronize(modelContext: modelContext, showsProgress: true)
                        await account.refreshPersonalization()
                        isWorking = false
                    }
                } label: { Label("Синхронизировать", systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(MemoryActionStyle(prominent: true)).disabled(isWorking || account.state == .syncing)
            } else {
                Button("Войти в аккаунт", action: onSignIn).buttonStyle(MemoryActionStyle(prominent: true))
            }
        }
    }
}

extension AccountSyncController {
    var profileStatusText: String {
        profileHasSyncError ? "Не всё синхронизировано" : statusText
    }
    var profileHasSyncError: Bool {
        if case .failed = state { return true }
        return linkSyncError != nil || personalizationError != nil
    }
    var profileSyncSymbol: String {
        guard isSignedIn else { return "icloud.slash" }
        if profileHasSyncError { return "exclamationmark.icloud" }
        if state == .syncing { return "arrow.triangle.2.circlepath.icloud" }
        return "checkmark.icloud"
    }
}
