import SwiftUI
import SwiftData

struct RecordLinksView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var account: AccountSyncController
    @Query(sort: \Item.timestamp, order: .reverse) private var items: [Item]
    @Query private var links: [RecordLink]
    let item: Item
    let onBack: () -> Void
    let onOpen: (Item) -> Void
    @State private var isChoosing = false
    @State private var search = ""
    @State private var errorMessage: String?

    private var linkedIDs: Set<UUID> {
        Set(links.filter { $0.ownerID == account.userID && $0.deletedAt == nil }
            .compactMap { $0.otherID(than: item.id) })
    }
    private var visibleItems: [Item] {
        items.filter { $0.ownerID == account.userID && $0.deletedAt == nil && $0.id != item.id }
    }
    private var displayedItems: [Item] {
        let ids = linkedIDs
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return visibleItems.filter {
            (isChoosing ? !ids.contains($0.id) : ids.contains($0.id))
                && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                    || ($0.details?.localizedCaseInsensitiveContains(query) ?? false))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isChoosing {
                        MemorySearchField(text: $search)
                            .accessibilityIdentifier("linkSearch")
                    }
                    if let syncError = account.linkSyncError {
                        Button {
                            account.markLocalChange(modelContext: modelContext)
                        } label: {
                            Label(syncError, systemImage: "arrow.clockwise")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    if displayedItems.isEmpty {
                        Text(isChoosing ? "Нет подходящих записей" : "Пока нет связанных записей")
                            .font(.body).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 100)
                    }
                    LazyVStack(spacing: 10) {
                        ForEach(displayedItems) { other in
                            HStack(spacing: 8) {
                                MemoryItemRow(item: other, onEdit: {
                                    if isChoosing { changeLink(true, other: other) }
                                    else { onOpen(other) }
                                }, showsContextMenu: !isChoosing)
                                if !isChoosing {
                                    Button { changeLink(false, other: other) } label: {
                                        Image(systemName: "link.badge.minus")
                                            .font(.system(size: 17, weight: .medium))
                                            .frame(width: 44, height: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain).foregroundStyle(.secondary)
                                    .accessibilityLabel("Убрать связь с \(other.title)")
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: 680)
                .padding(18)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MemoryTheme.background)
        .alert("Не удалось изменить связь", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("ОК", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        .accessibilityIdentifier("recordLinksPage")
    }

    private var header: some View {
        ZStack {
#if os(iOS)
            headerTitle
#endif
            HStack(spacing: 12) {
                Button {
                    if isChoosing { isChoosing = false; search = "" } else { onBack() }
                } label: {
                    Image(systemName: "arrow.left").font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Назад")
#if os(macOS)
                headerTitle
#endif
                Spacer(minLength: 0)
                if !isChoosing {
                    Button { isChoosing = true } label: {
                        Image(systemName: "plus").font(.system(size: 17, weight: .semibold))
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(MemoryTheme.accent)
                    .accessibilityLabel("Связать запись")
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 72)
    }

    private var headerTitle: some View {
        Text(isChoosing ? "Выбрать запись" : "Связанные записи")
            .font(.system(size: 17, weight: .medium, design: .rounded))
    }

    private func changeLink(_ enabled: Bool, other: Item) {
        do {
            try RecordLinkService.setLinked(enabled, first: item, second: other,
                                            ownerID: account.userID, context: modelContext)
            if enabled { isChoosing = false; search = "" }
            account.markLocalChange(modelContext: modelContext)
        } catch { errorMessage = error.localizedDescription }
    }
}
