import Foundation

/// One in-flight write, with latest-selection-wins coalescing. Owned by the account,
/// not the popover, so dismissing the picker never cancels an accepted selection.
@MainActor
final class ProfileAvatarSaveQueue {
    private(set) var pending: ProfileAvatar?
    private var worker: Task<Void, Never>?
    private var revision = 0
    private var generation = 0
    private let debounce: Duration
    private let persist: (ProfileAvatar) async throws -> Void
    private let didFinish: () -> Void
    private let didFail: () -> Void

    init(debounce: Duration = .milliseconds(280),
         persist: @escaping (ProfileAvatar) async throws -> Void,
         didFinish: @escaping () -> Void = {}, didFail: @escaping () -> Void = {}) {
        self.debounce = debounce
        self.persist = persist
        self.didFinish = didFinish
        self.didFail = didFail
    }

    func submit(_ avatar: ProfileAvatar) {
        pending = avatar
        revision += 1
        retry()
    }

    func retry() {
        guard worker == nil, pending != nil else { return }
        let currentGeneration = generation
        worker = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, currentGeneration == generation, pending != nil {
                let version = revision
                do { try await Task.sleep(for: debounce) }
                catch { return }
                guard currentGeneration == generation else { return }
                guard version == revision, let value = pending else { continue }
                do {
                    try await persist(value)
                    try Task.checkCancellation()
                } catch {
                    guard currentGeneration == generation, !Task.isCancelled else { return }
                    worker = nil
                    // A newer selection deserves its own attempt, not an error from an old value.
                    if version != revision { retry() } else { didFail() }
                    return
                }
                guard currentGeneration == generation else { return }
                if version == revision {
                    pending = nil
                    worker = nil
                    didFinish()
                    return
                }
            }
        }
    }

    func reset() {
        generation += 1
        worker?.cancel()
        worker = nil
        pending = nil
    }
}
