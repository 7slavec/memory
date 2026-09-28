import SwiftUI

extension View {
    func recordLinksPopup(item: Item, isPresented: Binding<Bool>, onOpen: @escaping (Item) -> Void) -> some View {
        popover(isPresented: isPresented) {
            RecordLinksPopupContent(item: item, onOpen: onOpen)
#if os(macOS)
                .frame(width: 420, height: 480)
#else
                .presentationCompactAdaptation(.sheet)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
#endif
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
