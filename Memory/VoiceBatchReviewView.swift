import SwiftUI
import Combine
import SwiftData

struct VoiceBatchReviewView<Header: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var account: AccountSyncController
    @Query private var storedItems: [Item]
    @Query private var links: [RecordLink]
    @ObservedObject var session: VoiceBatchReviewSession
    let onCancel: () -> Void
    let onSave: () -> Bool
    let onSaveExisting: (Item, String, String?, EntryKind, Date?, Date?, [Int]) -> Bool
    let onToggleExisting: (Item) -> Bool
    let onDeleteExisting: (Item) -> Bool
    @ViewBuilder let header: () -> Header

    var body: some View {
        let index = RecordLinkIndex(items: storedItems, links: links, ownerID: account.userID)
        Group {
            if let externalItem = session.externalItem {
                RecordEditorFlow(item: externalItem, onSave: onSaveExisting,
                                 onToggleCompleted: onToggleExisting, onDelete: onDeleteExisting,
                                 onOpenIntercept: { item in
                                     guard session.entries.contains(where: { $0.persistedItemID == item.id }) else { return false }
                                     session.externalItem = nil
                                     openLinkedRecord(item)
                                     return true
                                 },
                                 onDismiss: { session.externalItem = nil })
            } else if let selectedEntryID = session.selectedEntryID,
               let entry = session.entries.first(where: { $0.id == selectedEntryID }) {
                ItemEditorView(
                    item: session.item(for: entry),
                    onSave: { title, details, kind, date, endDate, reminderOffsets in
                        session.update(
                            selectedEntryID,
                            title: title,
                            details: details,
                            kind: kind,
                            date: date,
                            endDate: endDate,
                            reminderOffsets: reminderOffsets
                        )
                        return true
                    },
                    onToggleCompleted: { true },
                    onDelete: { session.remove(selectedEntryID); return true },
                    isEmbedded: true,
                    isNew: true,
                    saveActionTitle: "Применить",
                    linkedCount: entry.persistedItemID.map { index.count(for: $0) } ?? 0,
                    linksItem: storedItem(for: entry),
                    onOpenLinkedRecord: openLinkedRecord,
                    onDismiss: { selectEntry(nil) }
                )
                .id(selectedEntryID)
                .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    header()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Text(VoiceEntryCountLabel.short(session.entries.count))
                                .font(.system(size: 25, weight: .medium, design: .rounded))

                            LazyVStack(spacing: 10) {
                                ForEach(session.entries) { entry in
                                    VoiceReviewRow(
                                        draft: session.item(for: entry),
                                        stored: storedItem(for: entry),
                                        linkedCount: entry.persistedItemID.map { index.count(for: $0) } ?? 0,
                                        onEdit: { selectEntry(entry.id) },
                                        onDelete: session.entries.count > 1 ? { session.remove(entry.id) } : nil,
                                        onOpenLinked: openLinkedRecord
                                    )
                                }
                            }

                            actionBar
                        }
                        .frame(maxWidth: 680, alignment: .leading)
                        .padding(.horizontal, 22)
                        .padding(.top, 24)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity)
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MemoryTheme.background)
        .environment(\.locale, Locale(identifier: "ru_RU"))
        .accessibilityIdentifier("voiceBatchConfirmation")
    }

    private var actionBar: some View {
        HStack(spacing: 16) {
            Button(action: onCancel) {
                Text(session.batch.isPersisted ? "Отменить" : "Отмена")
                    .foregroundStyle(session.batch.isPersisted ? Color.red : Color.secondary)
                    .padding(.horizontal, 8)
                    .frame(minHeight: actionHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(session.batch.isPersisted ? "Удалит все записи, созданные из этой фразы" : "")

            Spacer(minLength: 8)

            Button {
                _ = onSave()
            } label: {
                Text(primaryActionTitle)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(minHeight: actionHeight)
                    .background(session.canSave ? MemoryTheme.accent : Color.secondary.opacity(0.3))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!session.canSave)
        }
        .font(.system(size: 14, weight: .medium, design: .rounded))
    }

    private var actionHeight: CGFloat {
#if os(macOS)
        36
#else
        44
#endif
    }

    private var primaryActionTitle: String {
        session.batch.isPersisted && !session.hasChanges ? "Готово" : "Сохранить"
    }

    private func selectEntry(_ entryID: UUID?) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            session.selectedEntryID = entryID
        }
    }

    private func storedItem(for entry: VoiceReviewEntry) -> Item? {
        storedItems.first { $0.id == entry.persistedItemID && $0.ownerID == account.userID && $0.deletedAt == nil }
    }

    private func openLinkedRecord(_ item: Item) {
        if let entry = session.entries.first(where: { $0.persistedItemID == item.id }) {
            selectEntry(entry.id)
        } else {
            session.externalItem = item
        }
    }
}

private struct VoiceReviewRow: View {
    let draft: Item
    let stored: Item?
    let linkedCount: Int
    let onEdit: () -> Void
    let onDelete: (() -> Void)?
    let onOpenLinked: (Item) -> Void
    @State private var showsLinks = false

    var body: some View {
        if let stored {
            MemoryItemRow(item: draft, onEdit: onEdit, onDelete: onDelete,
                          linkedCount: linkedCount, onOpenLinks: { showsLinks = true })
                .recordLinksPopup(item: stored, isPresented: $showsLinks, onOpen: onOpenLinked)
        } else {
            MemoryItemRow(item: draft, onEdit: onEdit, onDelete: onDelete)
        }
    }
}
