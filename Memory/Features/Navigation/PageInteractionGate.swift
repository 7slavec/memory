import Foundation

/// Tap arbitration is not visual state. In particular, releasing the gate must not
/// invalidate the entire records page halfway through a navigation animation.
@MainActor
final class PageInteractionGate {
    private var dragging = false
    private var lastActivity: TimeInterval = 0
    private var blockedUntil: TimeInterval = 0

    func begin(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        dragging = true
        lastActivity = now
    }

    func end(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard dragging else { return }
        dragging = false
        blockedUntil = now + MemoryMotion.postSwipeTapCooldown
    }

    func isSuppressed(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        // An interrupted/cancelled gesture may never deliver onEnded.
        (dragging && now - lastActivity < 1) || now < blockedUntil
    }
}
