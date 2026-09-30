#if os(macOS)
import SwiftUI
import SwiftData

struct MacQuickCaptureView: View {
    @EnvironmentObject private var account: AccountSyncController
    @Environment(\.modelContext) private var context
    @ObservedObject var controller: MacQuickCaptureController
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    @State private var review: VoiceBatchReviewSession?
    @State private var detail: Item?
    @State private var commitSignal = 0
    @State private var feedback: String?
    @State private var error: String?
    private var expanded: Bool { review != nil || detail != nil }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("norka.").font(.system(size: 20, weight: .semibold))
                Spacer()
                if let feedback { Label(feedback, systemImage: "checkmark").font(.system(size: 12)) }
                Button(action: controller.hide) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 28).background(MemoryTheme.card, in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("Скрыть быстрый ввод, сохранив черновик")
            }
            ZStack(alignment: .top) {
                QuickCaptureCard(defaultPreset: .none, presentation: .floating,
                                 activation: expanded ? nil : controller.activation,
                                 detailCommitSignal: commitSignal,
                                 remoteVoiceInterpreter: { text, now, calendar in
                                     try await account.interpretVoiceRemotely(text, now: now, calendar: calendar)
                                 },
                                 onOpenDetails: { title, details, kind, date, end in
                                     detail = Item(title: title, details: details, dueDate: date,
                                                   entryKind: kind, endDate: end,
                                                   reminderOffsets: date == nil ? [] : [account.defaultReminderMinutes(for: kind)])
                                 },
                                 onReviewBatch: { review = VoiceBatchReviewSession(batch: $0) },
                                 onAdd: save)
                    .opacity(expanded ? 0 : 1)
                    .frame(height: expanded ? 0 : nil).clipped()
                    .allowsHitTesting(!expanded).accessibilityHidden(expanded)
                if let detail {
                    ItemEditorView(item: detail, onSave: { title, details, kind, date, end, offsets in
                        guard save(title, details, kind, date, end, offsets) != nil else { return false }
                        commitSignal += 1
                        self.detail = nil
                        return true
                    }, onToggleCompleted: { false }, onDelete: { false },
                                   isEmbedded: true, isCompactDesktopPane: true, isNew: true,
                                   onDismiss: { self.detail = nil })
                        .id(detail.id).frame(height: controller.editorHeight)
                } else if let review {
                    // Entries are drafts here, so external persisted-record callbacks are unreachable.
                    VoiceBatchReviewView(session: review, onCancel: { self.review = nil },
                                         onSave: { saveBatch(review) },
                                         onSaveExisting: { _, _, _, _, _, _, _ in false },
                                         onToggleExisting: { _ in false }, onDeleteExisting: { _ in false },
                                         header: { EmptyView() })
                        .frame(height: controller.editorHeight)
                }
            }
            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(MemoryTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            if !expanded {
                HStack {
                    Text("↵ Сохранить").font(.system(size: 11))
                    Spacer()
                    Text("esc Скрыть").font(.system(size: 11))
                }.foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .foregroundStyle(MemoryTheme.accent)
        .background(MemoryTheme.background, in: RoundedRectangle(cornerRadius: MemoryTheme.cardRadius))
        .overlay { RoundedRectangle(cornerRadius: MemoryTheme.cardRadius).stroke(.primary.opacity(0.1), lineWidth: 1) }
        .preferredColorScheme(appearance.colorScheme)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controller.resize(height: $0) }
        .onExitCommand(perform: controller.hide)
        .onChange(of: controller.activation) { _, command in
            if command?.mode != .suspend { feedback = nil }
        }
    }

    private func save(_ title: String, _ details: String?, _ kind: EntryKind,
                      _ date: Date?, _ end: Date?, _ offsets: [Int]?) -> UUID? {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              kind != .event || date != nil else {
            error = "Для события укажите дату и время начала."
            return nil
        }
        let item = Item(title: title, details: details, dueDate: date, entryKind: kind,
                        endDate: end, reminderOffsets: date == nil ? [] : (offsets ?? [account.defaultReminderMinutes(for: kind)]),
                        ownerID: account.userID)
        context.insert(item)
        do { try context.save() }
        catch { context.rollback(); self.error = "Не удалось сохранить: \(error.localizedDescription)"; return nil }
        didSave([item])
        return item.id
    }

    private func saveBatch(_ review: VoiceBatchReviewSession) -> Bool {
        guard review.canSave, self.review?.id == review.id else { return false }
        do {
            let items = try VoiceBatchPersistence.create(review.entries, ownerID: account.userID, context: context)
            for (entry, item) in zip(review.entries, items) {
                VoicePersonalizationStore.beginCapture(itemID: item.id, transcript: entry.sourceText,
                    title: entry.originalDraft.title, details: entry.originalDraft.details,
                    dueDate: entry.originalDraft.dueDate, referenceDate: review.batch.referenceDate)
            }
            self.review = nil
            didSave(items)
            return true
        } catch { self.error = "Не удалось сохранить: \(error.localizedDescription)"; return false }
    }

    private func didSave(_ items: [Item]) {
        error = nil
        feedback = items.count == 1 ? "Сохранено" : "Сохранено: \(items.count)"
        account.markLocalChange(modelContext: context)
        for item in items where item.notificationsEnabled {
            guard let date = item.dueDate else { continue }
            let id = item.id, title = item.title, details = item.details, offsets = item.effectiveReminderOffsets
            Task { @MainActor in
                do { try await ReminderScheduler.schedule(id: id, title: title, details: details, at: date, offsets: offsets) }
                catch { self.error = "Запись сохранена. Уведомление: \(error.localizedDescription)" }
            }
        }
    }
}
#endif
