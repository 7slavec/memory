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

    let isConfigured: Bool
    private let client: SupabaseClient?
    private var isSynchronizing = false

    init() {
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
            setSession(userID: session.user.id, email: session.user.email)
        } catch {
            userID = nil
            email = nil
            state = .ready
        }
    }

    func signIn(email: String, password: String) async throws {
        guard let client else { throw AccountSyncError.notConfigured }
        let session = try await client.auth.signIn(email: email, password: password)
        setSession(userID: session.user.id, email: session.user.email)
    }

    func signUp(email: String, password: String) async throws {
        guard let client else { throw AccountSyncError.notConfigured }
        let response = try await client.auth.signUp(email: email, password: password)
        if let session = response.session {
            setSession(userID: session.user.id, email: session.user.email)
        } else {
            self.email = email
            state = .needsEmailConfirmation
        }
    }

    func signOut() async throws {
        guard let client else { return }
        try await client.auth.signOut(scope: .local)
        userID = nil
        email = nil
        state = .ready
    }

    func synchronize(modelContext: ModelContext) async {
        guard !isSynchronizing,
              let client,
              let userID,
              let userUUID = UUID(uuidString: userID) else { return }

        isSynchronizing = true
        state = .syncing
        defer { isSynchronizing = false }

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
                    if remote.updatedDate > local.updatedAt {
                        remote.apply(to: local)
                    } else if local.updatedAt > remote.updatedDate {
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
            }

            try modelContext.save()
            state = .synced(.now)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func markLocalChange(modelContext: ModelContext) {
        Task { await synchronize(modelContext: modelContext) }
    }

    private func setSession(userID: UUID, email: String?) {
        self.userID = userID.uuidString.lowercased()
        self.email = email
        state = .ready
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
