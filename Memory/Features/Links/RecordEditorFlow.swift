import SwiftUI
import SwiftData

/// A single page owner: navigating to links replaces the editor, not its header.
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
    let onDismiss: () -> Void
    @State private var path: [Item] = []
    @State private var showsLinks = false

    private var current: Item { path.last ?? item }
    private var linkedCount: Int {
        let visibleIDs = Set(items.filter { $0.ownerID == account.userID && $0.deletedAt == nil }.map(\.id))
        return links.filter {
            $0.ownerID == account.userID && $0.deletedAt == nil
                && $0.otherID(than: current.id).map(visibleIDs.contains) == true
        }.count
    }

    var body: some View {
        Group {
            if showsLinks {
                RecordLinksView(item: current, onBack: { showsLinks = false }, onOpen: { linked in
                    // Keep navigation bounded when following a cycle A → B → A.
                    if linked.id == item.id { path.removeAll() }
                    else if let index = path.firstIndex(where: { $0.id == linked.id }) {
                        path = Array(path.prefix(index + 1))
                    } else { path.append(linked) }
                    showsLinks = false
                })
            } else {
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
                    onOpenLinks: isNew ? nil : { showsLinks = true },
                    onDismiss: backFromEditor
                )
                .id(current.id)
            }
        }
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
            else { showsLinks = true }
        }
    }
}
