import SwiftUI
import SwiftData

struct RecordLinksView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var account: AccountSyncController
    @Query(sort: \Item.timestamp, order: .reverse) private var items: [Item]
    @Query private var links: [RecordLink]
    let item: Item
    let onOpen: (Item) -> Void
    @State private var isChoosing = false
    @State private var search = ""
    @State private var errorMessage: String?
    @State private var anchorID: UUID

    init(item: Item, onOpen: @escaping (Item) -> Void) {
        self.item = item
        self.onOpen = onOpen
        _anchorID = State(initialValue: item.id)
    }

    private var groupIDs: Set<UUID> {
        RecordLinkIndex(items: items, links: links, ownerID: account.userID).memberIDs(for: anchorID)
    }
    private var visibleItems: [Item] {
        items.filter { $0.ownerID == account.userID && $0.deletedAt == nil }
    }
    private var displayedItems: [Item] {
        let ids = groupIDs
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return visibleItems.filter {
            (isChoosing ? !ids.contains($0.id) && RecordLinkIndex.canAdd($0) : ids.contains($0.id))
                && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                    || ($0.details?.localizedCaseInsensitiveContains(query) ?? false))
        }.sorted {
            let lhs = $0.dueDate ?? .distantFuture, rhs = $1.dueDate ?? .distantFuture
            if lhs != rhs { return lhs < rhs }
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return $0.id.uuidString < $1.id.uuidString
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
                    LazyVStack(spacing: 8) {
                        ForEach(displayedItems) { other in
                            HStack(spacing: 8) {
                                MemoryItemRow(item: other, onEdit: {
                                    if isChoosing { add(other) }
                                    else {
                                        if other.id != item.id { onOpen(other) }
                                        dismiss()
                                    }
                                }, showsContextMenu: false)
                                .overlay {
                                    if !isChoosing && other.id == item.id {
                                        RoundedRectangle(cornerRadius: 24)
                                            .stroke(MemoryTheme.accent.opacity(0.4), lineWidth: 1)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .accessibilityHint(other.id == item.id ? "Текущая запись" : "Открыть запись")
                                if !isChoosing && groupIDs.count > 1 {
                                    Button { remove(other) } label: {
                                        Image(systemName: "minus")
                                            .font(.system(size: 14, weight: .semibold))
                                            .frame(width: 32, height: 32)
                                            .background(.primary.opacity(0.06), in: Circle())
                                            .frame(width: 44, height: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain).foregroundStyle(.secondary)
                                    .accessibilityLabel("Исключить из связи: \(other.title)")
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
            if !isChoosing && groupIDs.count > 1 {
                Button("Разорвать связь", role: .destructive, action: dissolve)
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.red)
                    .frame(minHeight: 44)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MemoryTheme.background)
        .alert("Не удалось изменить связь", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("ОК", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        .onChange(of: account.userID) { _, _ in dismiss() }
#if os(macOS)
        // Compact for a small group, bounded and scrollable for long text/many records.
        .frame(height: min(480, CGFloat(isChoosing ? 180 : 152) + CGFloat(displayedItems.count) * 80))
#endif
    }

    private var header: some View {
        HStack(spacing: 8) {
            if isChoosing {
                Button {
                    isChoosing = false; search = ""
                } label: {
                    Image(systemName: "arrow.left").font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Назад")
            }
            headerTitle
            Spacer(minLength: 0)
            if !isChoosing {
                Button { isChoosing = true } label: {
                    Image(systemName: "plus").font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(MemoryTheme.accent)
                .accessibilityLabel("Связать запись")
                .accessibilityIdentifier("addRecordLink")
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .accessibilityLabel("Закрыть связи")
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 64)
    }

    private var headerTitle: some View {
        Text(isChoosing ? "Выбрать запись" : "Связанные записи")
            .font(.system(size: 17, weight: .medium, design: .rounded))
    }

    private func add(_ other: Item) {
        guard let anchor = visibleItems.first(where: { $0.id == anchorID }) else { return }
        do {
            try RecordGroupService.add(other, to: anchor, ownerID: account.userID, context: modelContext)
            isChoosing = false; search = ""
            account.markLocalChange(modelContext: modelContext)
        } catch { errorMessage = error.localizedDescription }
    }

    private func remove(_ other: Item) {
        guard let anchor = visibleItems.first(where: { $0.id == anchorID }) else { return }
        let nextAnchor = displayedItems.first { $0.id != other.id }?.id ?? item.id
        do {
            try RecordGroupService.remove(other, from: anchor, ownerID: account.userID, context: modelContext)
            if anchorID == other.id { anchorID = nextAnchor }
            account.markLocalChange(modelContext: modelContext)
        } catch { errorMessage = error.localizedDescription }
    }

    private func dissolve() {
        guard let anchor = visibleItems.first(where: { $0.id == anchorID }) else { return }
        do {
            try RecordGroupService.dissolve(containing: anchor, ownerID: account.userID, context: modelContext)
            account.markLocalChange(modelContext: modelContext)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
