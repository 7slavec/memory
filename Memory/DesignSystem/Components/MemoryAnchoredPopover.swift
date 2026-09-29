import SwiftUI

/// A single presenter owned by the container, with its source rect at the actual control.
/// Resolving anchors here avoids copying per-frame geometry into application state.
struct MemoryAnchoredPopover<Panel: View>: View {
    @Binding var isPresented: Bool
    let source: Anchor<CGRect>?
    @ViewBuilder var panel: () -> Panel

    var body: some View {
        GeometryReader { geometry in
            let rect = source.map { geometry[$0] } ?? CGRect(origin: .zero, size: geometry.size)
            Color.clear
                .allowsHitTesting(false)
                .popover(isPresented: $isPresented, attachmentAnchor: .rect(.rect(rect)), arrowEdge: .bottom) {
                    panel()
                }
        }
    }
}

struct MemoryLinkControlAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}
