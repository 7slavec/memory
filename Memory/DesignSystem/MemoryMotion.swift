import SwiftUI

/// One owner per transition. Navigation never animates header height, padding or scroll geometry.
enum MemoryMotion {
    static let pageDuration = 0.24
    static let panelDuration = 0.12
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
            .animation(MemoryMotion.page(reduceMotion: reduceMotion)) {
                $0.opacity(visible ? 1 : 0)
                    .offset(x: visible || reduceMotion ? 0 : hiddenX)
            }
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
    }
}

extension View {
    func memoryPageVisibility(_ visible: Bool, hiddenX: CGFloat = 0) -> some View {
        modifier(MemoryPageVisibility(visible: visible, hiddenX: hiddenX))
    }
}
