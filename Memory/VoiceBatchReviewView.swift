import SwiftUI
import Combine

struct VoiceBatchReviewView<Header: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var session: VoiceBatchReviewSession
    let onCancel: () -> Void
    let onSave: () -> Bool
    @ViewBuilder let header: () -> Header

    var body: some View {
        Group {
            if let selectedEntryID = session.selectedEntryID,
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
                    },
                    onToggleCompleted: {},
                    onDelete: { session.remove(selectedEntryID) },
                    isEmbedded: true,
                    isNew: true,
                    saveActionTitle: "Применить",
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
                                    MemoryItemRow(
                                        item: session.item(for: entry),
                                        onEdit: { selectEntry(entry.id) },
                                        onDelete: session.entries.count > 1 ? { session.remove(entry.id) } : nil
                                    )
                                    .accessibilityIdentifier("voiceReviewEntry-\(entry.id)")
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
}
