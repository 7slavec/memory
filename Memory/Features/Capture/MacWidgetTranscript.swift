#if os(macOS)
import SwiftUI

/// Only whole-line growth changes the window height. Long speech scrolls instead
/// of growing beyond the display, and does not invalidate the animated orb.
struct MacWidgetTranscript: View {
    let text: String
    @State private var height: CGFloat = 20

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 14))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { MemoryWidgetMetrics.transcriptHeight($0.size.height) } action: {
                    height = $0
                }
        }
        .defaultScrollAnchor(.bottom)
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: height)
        .accessibilityLabel("Транскрипция")
    }
}
#endif
