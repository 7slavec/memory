import SwiftUI

/// A single presenter owned by the container, with its source rect at the actual control.
/// Resolving anchors here avoids copying per-frame geometry into application state.
struct MemoryAnchoredPopover<Panel: View>: View {
    @Binding var isPresented: Bool
    let source: Anchor<CGRect>?
    var fastPresentation = false
    @ViewBuilder var panel: () -> Panel

    var body: some View {
        GeometryReader { geometry in
            let rect = source.map { geometry[$0] } ?? CGRect(origin: .zero, size: geometry.size)
            Color.clear
                .allowsHitTesting(false)
                .popover(isPresented: $isPresented, attachmentAnchor: .rect(.rect(rect)), arrowEdge: .bottom) {
                    if fastPresentation {
                        MemoryFastPanel { panel() }
                    } else { panel() }
                }
                .transaction {
                    // Native shell has no configurable duration. Avoid stacking its animation
                    // with our short content fade; leave all non-opted-in pickers unchanged.
                    if fastPresentation { $0.disablesAnimations = true }
                }
        }
    }
}

private struct MemoryFastPanel<Content: View>: View {
    @State private var visible = false
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .opacity(visible ? 1 : 0)
            .onAppear { withAnimation(MemoryMotion.panel) { visible = true } }
            .transaction { $0.disablesAnimations = false }
    }
}

struct MemoryLinkControlAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}
