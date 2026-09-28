import SwiftUI
import SwiftData

/// Owns only record navigation. The editor keeps its draft while its links popup is open.
struct RecordEditorFlow: View {
    @EnvironmentObject private var account: AccountSyncController
    @Query private var links: [RecordLink]
    @Query private var items: [Item]
    let item: Item
    let onSave: (Item, String, String?, EntryKind, Date?, Date?, [Int]) -> Bool
    let onToggleCompleted: (Item) -> Bool
    let onDelete: (Item) -> Bool
    var isCompactDesktopPane = false
    var isNew = false
    var onOpenIntercept: ((Item) -> Bool)? = nil
    let onDismiss: () -> Void
    @State private var path: [Item] = []

    private var current: Item { path.last ?? item }
    private var linkedCount: Int {
        RecordLinkIndex(items: items, links: links, ownerID: account.userID).count(for: current.id)
    }

    var body: some View {
        ItemEditorView(
            item: current,
            onSave: { title, details, kind, date, end, offsets in
                onSave(current, title, details, kind, date, end, offsets)
            },
            onToggleCompleted: { onToggleCompleted(current) },
            onDelete: { onDelete(current) },
            isEmbedded: true,
            isCompactDesktopPane: isCompactDesktopPane,
            isNew: isNew,
            linkedCount: linkedCount,
            onOpenLinkedRecord: { linked in openLinkedRecord(linked) },
            onDismiss: backFromEditor
        )
        .id(current.id)
        .onChange(of: account.userID) { _, _ in onDismiss() }
        .onChange(of: current.deletedAt) { _, date in
            if date != nil { backFromEditor() }
        }
    }

    private func backFromEditor() {
        if path.isEmpty { onDismiss() }
        else {
            path.removeLast()
            if current.deletedAt != nil { onDismiss() }
        }
    }

    private func openLinkedRecord(_ linked: Item) {
        if onOpenIntercept?(linked) == true { return }
        // Keep navigation bounded when following a cycle A → B → A.
        if linked.id == item.id { path.removeAll() }
        else if let index = path.firstIndex(where: { $0.id == linked.id }) {
            path = Array(path.prefix(index + 1))
        } else { path.append(linked) }
    }
}
