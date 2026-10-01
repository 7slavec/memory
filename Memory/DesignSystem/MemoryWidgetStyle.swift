import SwiftUI

/// A compact density of Flow, not a second palette or a scaled-down application screen.
enum MemoryWidgetMetrics {
    static let width: CGFloat = 360
    static let voiceWidth: CGFloat = 264
    static let inset: CGFloat = 12
    static let gap: CGFloat = 8
    static let radius: CGFloat = 18
    static let control: CGFloat = 32
    static let editorHeight: CGFloat = 480
    static let transcriptLimit: CGFloat = 200

    static func transcriptHeight(_ measured: CGFloat) -> CGFloat {
        min(transcriptLimit, max(20, ceil(measured)))
    }
}

struct MemoryWidgetActionStyle: ButtonStyle {
    var prominent = false
    var iconOnly = false
    var destructive = false
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(destructive ? MemoryTheme.danger : prominent ? MemoryTheme.onAccent : MemoryTheme.accent)
            .padding(.horizontal, iconOnly ? 0 : 12)
            .frame(width: iconOnly ? MemoryWidgetMetrics.control : nil, height: MemoryWidgetMetrics.control)
            .background(prominent ? MemoryTheme.accent : hovered ? MemoryTheme.raised : MemoryTheme.card, in: Capsule())
            .contentShape(Capsule())
            .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.75 : 1)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : MemoryMotion.panel, value: configuration.isPressed)
    }
}

/// Fade only pixels when the route changes. Window geometry has its own single owner.
struct MemoryWidgetRouteReveal: ViewModifier {
    let route: String
    @State private var previous: String?
    @State private var revealed = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .visualEffect { [revealed] effect, _ in effect.opacity(revealed ? 1 : 0) }
            .task(id: route) {
                guard previous != nil else { previous = route; return }
                previous = route
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { revealed = false }
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(MemoryMotion.page(reduceMotion: reduceMotion)) { revealed = true }
            }
    }
}
