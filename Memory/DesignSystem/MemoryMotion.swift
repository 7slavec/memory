import SwiftUI

/// One owner per transition. Navigation never animates header height, padding or scroll geometry.
enum MemoryMotion {
    static let pageDuration = 0.12
    static let panelDuration = 0.08
    static let postSwipeTapCooldown = pageDuration + 0.04
    static let pageDistance: CGFloat = 32
    static let mobileHeaderHeight: CGFloat = 72
    static func page(reduceMotion: Bool) -> Animation {
        .easeOut(duration: reduceMotion ? panelDuration : pageDuration)
    }
    static let panel = Animation.easeOut(duration: panelDuration)
    static func forward(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .offset(x: pageDistance).combined(with: .opacity)
    }
}

private struct MemoryPageVisibility: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let visible: Bool
    let hiddenX: CGFloat
    func body(content: Content) -> some View {
        content
            // The page owns its transform, not the layout/controls inside it.
            // Keep the value-driven timing identical to profile push transitions.
            .transaction { $0.animation = nil }
            .visualEffect { [visible, hiddenX, reduceMotion] effect, _ in
                effect.opacity(visible ? 1 : 0)
                    .offset(x: visible || reduceMotion ? 0 : hiddenX)
            }
            .animation(MemoryMotion.page(reduceMotion: reduceMotion), value: visible)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
    }
}

extension View {
    func memoryPageVisibility(_ visible: Bool, hiddenX: CGFloat = 0) -> some View {
        modifier(MemoryPageVisibility(visible: visible, hiddenX: hiddenX))
    }
}
