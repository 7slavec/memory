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
    @Published private(set) var defaultEntryKind: EntryKind
    @Published private(set) var lastSignedInEmail: String?
    @Published private(set) var linkSyncError: String?

    let isConfigured: Bool
    private let client: SupabaseClient?
    private var isSynchronizing = false
    private var needsAnotherSynchronization = false
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeUserID: String?
    private var linkRealtimeEnabled = false
    private var realtimeListenerTasks: [Task<Void, Never>] = []
    private let deviceID = UUID().uuidString.lowercased()
    private static let defaultReminderKey = "defaultReminderMinutes"
    private static let defaultEntryKindKey = "defaultEntryKind"
    private static let lastSignedInEmailKey = "lastSignedInEmail"

    init() {
        let storedDefault = UserDefaults.standard.object(forKey: Self.defaultReminderKey) as? Int
        defaultReminderMinutes = ReminderLeadTime(rawValue: storedDefault ?? 0)?.rawValue ?? 0
        defaultEntryKind = UserDefaults.standard.string(forKey: Self.defaultEntryKindKey)
            .flatMap(EntryKind.init(rawValue:)) ?? .reminder
        lastSignedInEmail = UserDefaults.standard.string(forKey: Self.lastSignedInEmailKey)

        if !VoiceReviewTesting.usesIsolatedStorage, !DesignCatalogMode.isEnabled, let configuration = SupabaseConfiguration.current {
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

        if let cachedSession = client.auth.currentSession {
            setCachedSession(
                userID: cachedSession.user.id,
                email: cachedSession.user.email
            )
        }

        do {
            let session = try await client.auth.session
            await setSession(userID: session.user.id, email: session.user.email)
        } catch {
            if client.auth.currentSession != nil {
                state = .failed(error.localizedDescription)
            } else {
                userID = nil
                email = nil
                state = .ready
            }
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
        linkSyncError = nil
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

                guard self.userID == userID else { return }

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
                do {
                    let remoteLinks: [RemoteRecordLink] = try await client.from("task_links")
                        .select().eq("user_id", value: userID).execute().value
                    guard self.userID == userID else { return }
                    let linkUploads = try RecordLinkReconciler.merge(remoteLinks, userID: userUUID, context: modelContext)
                    if !linkUploads.isEmpty {
                        try await client.from("task_links").upsert(linkUploads).execute()
                        await broadcastTasksChanged()
                    }
                    linkSyncError = nil
                    state = .synced(.now)
                    if !linkRealtimeEnabled {
                        linkRealtimeEnabled = true
                        await stopRealtime()
                        await ensureRealtime(modelContext: modelContext, userID: userID, userUUID: userUUID)
                    }
                } catch {
                    // Ordinary records have already synced. Keep links locally and retry later.
                    let schemaUnavailable = (error as? PostgrestError)?.code == "PGRST205"
                        || (error as? PostgrestError)?.code == "42P01"
                    linkSyncError = schemaUnavailable
                        ? "Синхронизация связей ещё не подключена"
                        : "Связи сохранены на устройстве. Повторить синхронизацию"
                    state = schemaUnavailable ? .synced(.now) : .failed("Не удалось синхронизировать связи")
                    needsAnotherSynchronization = false
                }
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

    func setDefaultEntryKind(_ kind: EntryKind) async throws {
        let previousValue = defaultEntryKind
        defaultEntryKind = kind
        UserDefaults.standard.set(kind.rawValue, forKey: Self.defaultEntryKindKey)

        guard let client, let userID else { return }

        do {
            try await client
                .from("profiles")
                .update(ProfileEntryKindUpdate(defaultEntryKind: kind.rawValue))
                .eq("id", value: userID)
                .execute()
        } catch {
            defaultEntryKind = previousValue
            UserDefaults.standard.set(previousValue.rawValue, forKey: Self.defaultEntryKindKey)
            throw error
        }
    }

    func interpretVoiceRemotely(
        _ transcript: String,
        now: Date,
        calendar: Calendar
    ) async throws -> VoiceCaptureResult {
        guard let client else { throw AccountSyncError.notConfigured }
        guard isSignedIn else { throw AccountSyncError.authenticationRequired }

        let session = try await client.auth.session
        client.functions.setAuth(token: session.accessToken)

        let learningExamples: [VoiceLearningPromptExample]
        if UserDefaults.standard.bool(forKey: VoicePipelineSettings.personalLearningEnabledKey) {
            learningExamples = VoiceLabStore.similarExamples(to: transcript).map { example in
                VoiceLearningPromptExample(
                    transcript: example.transcript,
                    title: example.expectedTitle,
                    details: example.expectedDetails,
                    dueDate: example.expectedDueDate.map(Self.voiceDateFormatter.string),
                    referenceDate: Self.voiceDateFormatter.string(from: example.referenceDate),
                    timeZone: example.timeZoneIdentifier
                )
            }
        } else {
            learningExamples = []
        }

        let response: RemoteVoiceCaptureResponse = try await client.functions.invoke(
            "interpret-voice",
            options: FunctionInvokeOptions(
                body: RemoteVoiceInterpretationRequest(
                    transcript: transcript,
                    referenceDate: Self.voiceDateFormatter.string(from: now),
                    timeZone: calendar.timeZone.identifier,
                    locale: calendar.locale?.identifier ?? "ru_RU",
                    examples: learningExamples
                ),
                timeoutInterval: 8
            )
        )

        return try response.captureResult(
            transcript: transcript,
            dateFormatter: Self.voiceDateFormatter,
            defaultKind: defaultEntryKind
        )
    }

    private func setSession(userID: UUID, email: String?) async {
        let nextUserID = userID.uuidString.lowercased()
        if self.userID != nextUserID {
            await stopRealtime()
            linkSyncError = nil
        }
        self.userID = nextUserID
        self.email = email
        rememberEmail(email)
        state = .ready
        await loadProfileSettings(userID: nextUserID)
    }

    private func setCachedSession(userID: UUID, email: String?) {
        self.userID = userID.uuidString.lowercased()
        self.email = email
        rememberEmail(email)
        state = .ready
    }

    private func rememberEmail(_ email: String?) {
        guard let email, !email.isEmpty else { return }
        lastSignedInEmail = email
        UserDefaults.standard.set(email, forKey: Self.lastSignedInEmailKey)
    }

    private func loadProfileSettings(userID: String) async {
        guard let client else { return }
        do {
            let settings: ProfileSettings = try await client
                .from("profiles")
                .select("default_reminder_minutes, default_entry_kind")
                .eq("id", value: userID)
                .single()
                .execute()
                .value

            let normalized = ReminderLeadTime(rawValue: settings.defaultReminderMinutes)?.rawValue ?? 0
            defaultReminderMinutes = normalized
            UserDefaults.standard.set(normalized, forKey: Self.defaultReminderKey)
            let entryKind = settings.defaultEntryKind.flatMap(EntryKind.init(rawValue:)) ?? .reminder
            defaultEntryKind = entryKind
            UserDefaults.standard.set(entryKind.rawValue, forKey: Self.defaultEntryKindKey)
        } catch {
            // The local preference remains available while the profile cannot be loaded.
        }
    }

    private static let voiceDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

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
        // Do not let an undeployed optional table break realtime for existing records.
        let linkEvents = linkRealtimeEnabled ? channel.postgresChange(
            AnyAction.self, schema: "public", table: "task_links",
            filter: .eq("user_id", value: userUUID)
        ) : nil

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
            if let linkEvents {
                realtimeListenerTasks.append(Task { [weak self] in
                    for await _ in linkEvents {
                        guard !Task.isCancelled else { break }
                        await self?.synchronize(modelContext: modelContext)
                    }
                })
            }
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
    let defaultEntryKind: String?

    enum CodingKeys: String, CodingKey {
        case defaultReminderMinutes = "default_reminder_minutes"
        case defaultEntryKind = "default_entry_kind"
    }
}

private struct ProfileEntryKindUpdate: Encodable {
    let defaultEntryKind: String

    enum CodingKeys: String, CodingKey {
        case defaultEntryKind = "default_entry_kind"
    }
}

private struct ProfileSettingsUpdate: Encodable {
    let defaultReminderMinutes: Int

    enum CodingKeys: String, CodingKey {
        case defaultReminderMinutes = "default_reminder_minutes"
    }
}

private struct RemoteVoiceInterpretationRequest: Encodable {
    let transcript: String
    let referenceDate: String
    let timeZone: String
    let locale: String
    let examples: [VoiceLearningPromptExample]
}

struct RemoteVoiceCaptureResponse: Decodable {
    let entries: [RemoteVoiceInterpretation]?
    let linkGroups: VoiceLinkGroups?
    let title: String?
    let details: String?
    let dueDate: String?
    let reminderOffsets: [Int]?
    let confidence: VoiceInterpretationConfidence?
    let ambiguities: [VoiceInterpretationAmbiguity]?

    func captureResult(
        transcript: String,
        dateFormatter: ISO8601DateFormatter,
        defaultKind: EntryKind
    ) throws -> VoiceCaptureResult {
        let sourceEntries: [RemoteVoiceInterpretation]
        if let entries {
            sourceEntries = entries
        } else if let title, let confidence {
            sourceEntries = [RemoteVoiceInterpretation(
                sourceText: transcript,
                title: title,
                details: details,
                dueDate: dueDate,
                endDate: nil,
                kind: nil,
                reminderOffsets: reminderOffsets ?? [],
                confidence: confidence,
                ambiguities: ambiguities ?? []
            )]
        } else {
            throw VoiceSemanticError.emptyResult
        }
        guard !sourceEntries.isEmpty, sourceEntries.count <= 6 else {
            throw VoiceSemanticError.emptyResult
        }
        let plainDateFormatter = ISO8601DateFormatter()
        let membership = linkGroups?.membership(entryCount: sourceEntries.count, transcript: transcript) ?? [:]
        let captured = try sourceEntries.enumerated().map { index, entry -> VoiceCaptureEntry in
            let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { throw VoiceSemanticError.emptyResult }
            let dueDate = entry.dueDate.flatMap {
                dateFormatter.date(from: $0) ?? plainDateFormatter.date(from: $0)
            }
            if entry.dueDate != nil && dueDate == nil { throw VoiceSemanticError.emptyResult }
            let endDate = entry.endDate.flatMap {
                dateFormatter.date(from: $0) ?? plainDateFormatter.date(from: $0)
            }
            if entry.endDate != nil && endDate == nil { throw VoiceSemanticError.emptyResult }
            let sourceText = entry.sourceText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let spokenPart = sourceText?.isEmpty == false ? sourceText! : transcript
            let kind = entry.kind ?? EntryKindInference.infer(
                from: spokenPart, hasDate: dueDate != nil
            ) ?? defaultKind
            return VoiceCaptureEntry(
                sourceText: spokenPart,
                draft: ReminderDraft(
                    transcript: spokenPart,
                    title: title,
                    details: Item.normalizedDetails(entry.details),
                    dueDate: dueDate,
                    reminderOffsets: dueDate == nil
                        ? [] : ReminderLeadTime.normalized(entry.reminderOffsets),
                    confidence: entry.confidence,
                    ambiguities: Set(entry.ambiguities)
                ),
                kind: kind,
                endDate: kind == .event ? endDate : nil,
                linkGroup: membership[index]
            )
        }
        return VoiceCaptureResult(entries: captured)
    }
}

struct RemoteVoiceInterpretation: Decodable {
    let sourceText: String?
    let title: String
    let details: String?
    let dueDate: String?
    let endDate: String?
    let kind: EntryKind?
    let reminderOffsets: [Int]
    let confidence: VoiceInterpretationConfidence
    let ambiguities: [VoiceInterpretationAmbiguity]
}

enum AccountSyncError: LocalizedError {
    case notConfigured
    case authenticationRequired

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Supabase ещё не подключён к приложению."
        case .authenticationRequired:
            "Для облачного улучшения голоса нужно войти в аккаунт."
        }
    }
}
