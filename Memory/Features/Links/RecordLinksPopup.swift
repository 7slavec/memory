import SwiftUI

extension View {
    func recordLinksPopup(item: Item, isPresented: Binding<Bool>, onOpen: @escaping (Item) -> Void) -> some View {
        overlayPreferenceValue(MemoryLinkControlAnchor.self) { anchor in
            MemoryAnchoredPopover(isPresented: isPresented, source: anchor) {
            RecordLinksPopupContent(item: item, onOpen: onOpen)
#if os(macOS)
                .frame(width: 360)
#else
                .frame(width: 320)
                .presentationCompactAdaptation(.popover)
                .presentationBackground(MemoryTheme.card)
#endif
            }
        }
    }
}

private struct RecordLinksPopupContent: View {
    let item: Item
    let onOpen: (Item) -> Void
    @State private var pendingRecord: Item?

    var body: some View {
        RecordLinksView(item: item) { pendingRecord = $0 }
            .onDisappear {
                // Wait for dismissal before navigating or asking about an unsaved draft.
                guard let pendingRecord else { return }
                self.pendingRecord = nil
                onOpen(pendingRecord)
            }
    }
}
