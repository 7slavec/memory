import Foundation
import Testing
@testable import Memory

@MainActor
struct NavigationAvatarTests {
    @Test func swipeGateExpiresWithoutAStateUpdateOrTimer() {
        let gate = PageInteractionGate()
        #expect(!gate.isSuppressed(at: 10))
        gate.begin(at: 10)
        #expect(gate.isSuppressed(at: 10))
        gate.end(at: 10)
        #expect(gate.isSuppressed(at: 10.12))
        #expect(!gate.isSuppressed(at: 10.17))
        gate.begin(at: 11)
        #expect(gate.isSuppressed(at: 11))
        gate.end(at: 11)
        #expect(!gate.isSuppressed(at: 11.17))
        gate.begin(at: 12)
        #expect(!gate.isSuppressed(at: 14))
    }

    @Test func quickAvatarChoicesCoalesceToOneWrite() async throws {
        var writes: [ProfileAvatar] = []
        let queue = ProfileAvatarSaveQueue(debounce: .milliseconds(5), persist: { writes.append($0) })
        queue.submit(.standard)
        queue.submit(ProfileAvatar(animal: .dog, tint: .mint))
        let latest = ProfileAvatar(animal: .rabbit, tint: .sky, fur: .cobalt)
        queue.submit(latest)
        try await waitUntil { queue.pending == nil }
        #expect(writes == [latest])
    }

    @Test func slowSaveCannotOverwriteTheLatestSelection() async throws {
        var writes: [ProfileAvatar] = []
        var release: CheckedContinuation<Void, Never>?
        let queue = ProfileAvatarSaveQueue(debounce: .milliseconds(5), persist: { value in
            writes.append(value)
            if writes.count == 1 { await withCheckedContinuation { release = $0 } }
        })
        queue.submit(.standard)
        try await waitUntil { release != nil }
        queue.submit(ProfileAvatar(animal: .dog, tint: .mint))
        let latest = ProfileAvatar(animal: .rabbit, tint: .sky)
        queue.submit(latest)
        #expect(queue.pending == latest)
        release?.resume()
        try await waitUntil { queue.pending == nil }
        #expect(writes == [.standard, latest])
    }

    @Test func failureKeepsSelectionAndCanRetry() async throws {
        enum Offline: Error { case unavailable }
        var attempts = 0
        var failed = false
        let queue = ProfileAvatarSaveQueue(debounce: .milliseconds(5), persist: { _ in
            attempts += 1
            if attempts == 1 { throw Offline.unavailable }
        }, didFail: { failed = true })
        queue.submit(.standard)
        try await waitUntil { failed }
        #expect(queue.pending == .standard)
        queue.retry()
        try await waitUntil { queue.pending == nil }
        #expect(attempts == 2)
    }

    @Test func resetCancelsAQueuedWriteBeforeAccountChange() async throws {
        var writes: [ProfileAvatar] = []
        let queue = ProfileAvatarSaveQueue(debounce: .milliseconds(5), persist: { writes.append($0) })
        queue.submit(.standard)
        queue.reset()
        let nextAccountAvatar = ProfileAvatar(animal: .rabbit)
        queue.submit(nextAccountAvatar)
        try await waitUntil { queue.pending == nil }
        #expect(writes == [nextAccountAvatar])
    }

    @Test func avatarPreviewUpdatesBeforeSaveCompletes() async throws {
        let account = AccountSyncController()
        let avatar = ProfileAvatar(animal: .dog, tint: .lilac, fur: .cobalt)
        account.selectAvatar(avatar)
        #expect(account.personalization.avatar == avatar)
        try await Task.sleep(for: .milliseconds(350))
        #expect(account.personalization.avatar == avatar)
        #expect(account.avatarSaveError == nil)
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(predicate())
    }
}
