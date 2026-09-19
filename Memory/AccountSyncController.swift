import Foundation
import SwiftData
import Supabase
import Combine

@MainActor
final class AccountSyncController: ObservableObject {
    enum State: Equatable {
        case localOnly
        case ready
        case syncing
        case synced(Date)
        case needsEmailConfirmation
        case failed(String)
    }

    @Published private(set) var userID: String?
    @Published private(set) var email: String?
    @Published private(set) var state: State
    @Published private(set) var defaultReminderMinutes: Int

    let isConfigured: Bool
    private let client: SupabaseClient?
    private var isSynchronizing = false
    private var needsAnotherSynchronization = false
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeUserID: String?
    private var realtimeListenerTasks: [Task<Void, Never>] = []
    private let deviceID = UUID().uuidString.lowercased()
    private static let defaultReminderKey = "defaultReminderMinutes"

    init() {
        let storedDefault = UserDefaults.standard.object(forKey: Self.defaultReminderKey) as? Int
        defaultReminderMinutes = ReminderLeadTime(rawValue: storedDefault ?? 0)?.rawValue ?? 0

        if let configuration = SupabaseConfiguration.current {
            client = SupabaseClient(
                supabaseURL: configuration.url,
                supabaseKey: configuration.publishableKey
            )
            isConfigured = true
            state = .ready
        } else {
            client = nil
            isConfigured = false
            state = .localOnly
        }
    }

    var isSignedIn: Bool { userID != nil }

    var statusText: String {
        if !isConfigured { return "Синхронизация ещё не подключена" }
        if !isSignedIn { return "Только на этом устройстве" }
        switch state {
        case .syncing: return "Синхронизация…"
        case .synced: return "Данные синхронизированы"
        case .needsEmailConfirmation: return "Подтвердите почту"
        case .failed: return "Не удалось синхронизировать"
        default: return "Синхронизация включена"
        }
    }

    func restoreSession() async {
        guard let client else { return }
        do {
            let session = try await client.auth.session
            await setSession(userID: session.user.id, email: session.user.email)
        } catch {
            userID = nil
            email = nil
            state = .ready
        }
    }

    func signIn(email: String, password: String) async throws {
        guard let client else { throw AccountSyncError.notConfigured }
        let session = try await client.auth.signIn(email: email, password: password)
        await setSession(userID: session.user.id, email: session.user.email)
    }

    func signUp(email: String, password: String) async throws {
        guard let client else { throw AccountSyncError.notConfigured }
        let response = try await client.auth.signUp(email: email, password: password)
        if let session = response.session {
            await setSession(userID: session.user.id, email: session.user.email)
        } else {
            self.email = email
            state = .needsEmailConfirmation
        }
    }

    func signOut() async throws {
        guard let client else { return }
        await stopRealtime()
        try await client.auth.signOut(scope: .local)
        userID = nil
        email = nil
        state = .ready
    }

    func synchronize(modelContext: ModelContext, showsProgress: Bool = false) async {
        guard let client,
              let userID,
              let userUUID = UUID(uuidString: userID) else { return }

        if isSynchronizing {
            needsAnotherSynchronization = true
            return
        }

        isSynchronizing = true
        defer { isSynchronizing = false }

        await ensureRealtime(modelContext: modelContext, userID: userID, userUUID: userUUID)

        repeat {
            needsAnotherSynchronization = false
            if showsProgress {
                state = .syncing
            }

            do {
                let remoteItems: [RemoteTask] = try await client
                    .from("tasks")
                    .select()
                    .eq("user_id", value: userID)
                    .execute()
                    .value

                let allLocalItems = try modelContext.fetch(FetchDescriptor<Item>())

                // The first account used on this device adopts existing local-only records.
                for item in allLocalItems where item.ownerID == nil {
                    item.ownerID = userID
                    item.updatedAt = .now
                }

                let localItems = allLocalItems.filter { $0.ownerID == userID }
                var localByID = Dictionary(uniqueKeysWithValues: localItems.map { ($0.id, $0) })
                var uploads: [RemoteTask] = []

                for remote in remoteItems {
                    if let local = localByID.removeValue(forKey: remote.id) {
                        if SupabaseDate.isMeaningfullyNewer(remote.updatedDate, than: local.updatedAt) {
                            remote.apply(to: local)
                        } else if SupabaseDate.isMeaningfullyNewer(local.updatedAt, than: remote.updatedDate) {
                            uploads.append(RemoteTask(item: local, userID: userUUID))
                        }
                    } else {
                        modelContext.insert(remote.makeLocalItem())
                    }
                }

                uploads.append(contentsOf: localByID.values.map {
                    RemoteTask(item: $0, userID: userUUID)
                })

                if !uploads.isEmpty {
                    try await client
                        .from("tasks")
                        .upsert(uploads)
                        .execute()
                    await broadcastTasksChanged()
                }

                try modelContext.save()
                state = .synced(.now)
            } catch {
                state = .failed(error.localizedDescription)
                needsAnotherSynchronization = false
            }
        } while needsAnotherSynchronization
    }

    func markLocalChange(modelContext: ModelContext) {
        Task { await synchronize(modelContext: modelContext) }
    }

    func setDefaultReminderMinutes(_ minutes: Int) async throws {
        guard let normalized = ReminderLeadTime(rawValue: minutes)?.rawValue else { return }
        let previousValue = defaultReminderMinutes

        defaultReminderMinutes = normalized
        UserDefaults.standard.set(normalized, forKey: Self.defaultReminderKey)

        guard let client, let userID else { return }

        do {
            try await client
                .from("profiles")
                .update(ProfileSettingsUpdate(defaultReminderMinutes: normalized))
                .eq("id", value: userID)
                .execute()
        } catch {
            defaultReminderMinutes = previousValue
            UserDefaults.standard.set(previousValue, forKey: Self.defaultReminderKey)
            throw error
        }
    }

    private func setSession(userID: UUID, email: String?) async {
        let nextUserID = userID.uuidString.lowercased()
        if self.userID != nextUserID {
            await stopRealtime()
        }
        self.userID = nextUserID
        self.email = email
        state = .ready
        await loadProfileSettings(userID: nextUserID)
    }

    private func loadProfileSettings(userID: String) async {
        guard let client else { return }
        do {
            let settings: ProfileSettings = try await client
                .from("profiles")
                .select("default_reminder_minutes")
                .eq("id", value: userID)
                .single()
                .execute()
                .value

            let normalized = ReminderLeadTime(rawValue: settings.defaultReminderMinutes)?.rawValue ?? 0
            defaultReminderMinutes = normalized
            UserDefaults.standard.set(normalized, forKey: Self.defaultReminderKey)
        } catch {
            // The local preference remains available while the profile cannot be loaded.
        }
    }

    private func ensureRealtime(
        modelContext: ModelContext,
        userID: String,
        userUUID: UUID
    ) async {
        guard let client else { return }
        if realtimeChannel != nil, realtimeUserID == userID { return }

        await stopRealtime()

        let channel = client.channel("memory:\(userID)") {
            $0.broadcast.acknowledgeBroadcasts = true
        }
        let broadcastEvents = channel.broadcastStream(event: "tasks_changed")
        let databaseEvents = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "tasks",
            filter: .eq("user_id", value: userUUID)
        )

        realtimeChannel = channel
        realtimeUserID = userID

        do {
            try await channel.subscribeWithError()

            realtimeListenerTasks = [
                Task { [weak self] in
                    for await _ in broadcastEvents {
                        guard !Task.isCancelled else { break }
                        await self?.synchronize(modelContext: modelContext)
                    }
                },
                Task { [weak self] in
                    for await _ in databaseEvents {
                        guard !Task.isCancelled else { break }
                        await self?.synchronize(modelContext: modelContext)
                    }
                }
            ]
        } catch {
            realtimeChannel = nil
            realtimeUserID = nil
            await client.removeChannel(channel)
        }
    }

    private func broadcastTasksChanged() async {
        guard let realtimeChannel else { return }
        try? await realtimeChannel.broadcast(
            event: "tasks_changed",
            message: ["device_id": deviceID]
        )
    }

    private func stopRealtime() async {
        realtimeListenerTasks.forEach { $0.cancel() }
        realtimeListenerTasks.removeAll()

        let channel = realtimeChannel
        realtimeChannel = nil
        realtimeUserID = nil

        if let client, let channel {
            await client.removeChannel(channel)
        }
    }
}

private struct ProfileSettings: Decodable {
    let defaultReminderMinutes: Int

    enum CodingKeys: String, CodingKey {
        case defaultReminderMinutes = "default_reminder_minutes"
    }
}

private struct ProfileSettingsUpdate: Encodable {
    let defaultReminderMinutes: Int

    enum CodingKeys: String, CodingKey {
        case defaultReminderMinutes = "default_reminder_minutes"
    }
}

enum AccountSyncError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Supabase ещё не подключён к приложению."
        }
    }
}
