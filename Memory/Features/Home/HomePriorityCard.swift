import SwiftUI

struct HomePriorityCard: View {
    let item: Item
    let isOverdue: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    var linkedCount = 0
    var onOpenLinkedRecord: ((Item) -> Void)? = nil
    @State private var showsLinks = false

    var body: some View {
        MemoryItemRow(item: item, onToggle: onToggle, onEdit: onEdit,
                      linkedCount: linkedCount, onOpenLinks: { showsLinks = true })
            .recordLinksPopup(item: item, isPresented: $showsLinks) { linked in
                showsLinks = false
                onOpenLinkedRecord?(linked)
            }
    }
}
