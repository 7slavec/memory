#if os(macOS)
import SwiftUI
import SwiftData

struct MacCaptureAutoHidePolicy: Equatable {
    var count: Int
    var interacting: Bool
    var hasError: Bool
    var isVisible: Bool
    var usesVoiceOver: Bool
    var shouldHide: Bool { count == 1 && !interacting && !hasError && isVisible && !usesVoiceOver }
}

struct MacQuickCaptureView: View {
    @EnvironmentObject private var account: AccountSyncController
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @ObservedObject var controller: MacQuickCaptureController
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    @State private var review: VoiceBatchReviewSession?
    @State private var detail: Item?
    @State private var isNewDetail = false
    @State private var draftEntryID: UUID?
    @State private var results: [Item] = []
    @State private var isVoice = false
    @State private var hovered = false
    @State private var keyboardInteraction = false
    @State private var commitSignal = 0
    @State private var error: String?
    @State private var reminderQueue = MacCaptureReminderQueue()
    init(controller: MacQuickCaptureController) {
        self.controller = controller
        _isVoice = State(initialValue: controller.activation?.mode == .voice)
    }
    private var occupied: Bool { review != nil || detail != nil || !results.isEmpty }
    private var width: CGFloat { occupied ? MemoryWidgetMetrics.width : isVoice ? MemoryWidgetMetrics.voiceWidth : MemoryWidgetMetrics.width }
    private var route: String { detail != nil ? "editor" : review != nil ? "review" : !results.isEmpty ? "receipt" : isVoice ? "voice" : "text" }
    private var autoHide: MacCaptureAutoHidePolicy {
        .init(count: results.count, interacting: hovered || keyboardInteraction || detail != nil || review != nil,
              hasError: error != nil, isVisible: controller.activation?.mode != .suspend, usesVoiceOver: voiceOver)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                composer
                    .opacity(occupied ? 0 : 1).frame(height: occupied ? 0 : nil).clipped()
                    .allowsHitTesting(!occupied).accessibilityHidden(occupied)
                if let detail {
                    editor(detail)
                } else if let review {
                    MacWidgetReview(session: review, onEdit: openDraft, onSave: { _ = saveBatch(review) },
                                    onDiscard: discardReview, maximumHeight: controller.editorHeight)
                } else if !results.isEmpty {
                    MacCaptureResultsView(items: results, onEdit: openResult,
                        onUndo: undoCreation, onClose: controller.hide)
                        .frame(maxHeight: controller.editorHeight)
                }
            }
            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(MemoryTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(12)
            }
        }
        .frame(width: width).fixedSize(horizontal: false, vertical: true)
        .modifier(MemoryWidgetRouteReveal(route: route))
        .foregroundStyle(MemoryTheme.accent)
        .background(occupied || isVoice ? MemoryTheme.background : MemoryTheme.card, in: RoundedRectangle(cornerRadius: MemoryWidgetMetrics.radius))
        .overlay { RoundedRectangle(cornerRadius: MemoryWidgetMetrics.radius).strokeBorder(.primary.opacity(0.1), lineWidth: 1).allowsHitTesting(false) }
        .compositingGroup().clipShape(RoundedRectangle(cornerRadius: MemoryWidgetMetrics.radius))
        .preferredColorScheme(appearance.colorScheme)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { controller.resize(size: $0) }
        .onExitCommand(perform: controller.hide)
        .onHover { hovered = $0 }
        .onKeyPress(.tab) { keyboardInteraction = true; return .ignored }
        .task(id: autoHide) {
            guard autoHide.shouldHide else { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard !Task.isCancelled, autoHide.shouldHide else { return }
            controller.hide()
        }
        .onChange(of: controller.activation) { _, command in
            guard let command, command.mode != .suspend else { return }
            // Reopening a receipt starts fresh; unfinished editors and batches remain available.
            if results.count == 1, detail == nil, review == nil { results = []; keyboardInteraction = false }
        }
#if DEBUG
        .task {
            guard VoiceReviewTesting.isQuickCaptureEnabled,
                  ProcessInfo.processInfo.arguments.contains("--uitest-capture-batch") else { return }
            var entries = VoiceReviewTesting.session().entries
            for index in entries.indices { entries[index].persistedItemID = nil }
            receiveBatch(VoiceBatchReview(referenceDate: .now, entries: entries))
        }
#endif
    }

    private var composer: some View {
        QuickCaptureCard(defaultPreset: .none, presentation: .floating,
            activation: occupied ? nil : controller.activation,
            onFloatingModeChange: { isVoice = $0 }, floatingContentVisible: !occupied,
            detailCommitSignal: commitSignal,
            remoteVoiceInterpreter: { text, now, calendar in
                try await account.interpretVoiceRemotely(text, now: now, calendar: calendar)
            }, onDismiss: controller.hide,
            onOpenDetails: { title, details, kind, date, end in
                isNewDetail = true
                draftEntryID = nil
                detail = Item(title: title, details: details, dueDate: date, entryKind: kind, endDate: end,
                              reminderOffsets: date == nil ? [] : [account.defaultReminderMinutes(for: kind)])
            }, onReviewBatch: receiveBatch, onAdd: save)
    }

    private func editor(_ item: Item) -> some View {
        ItemEditorView(item: item, onSave: { title, details, kind, date, end, offsets in
            if let entryID = draftEntryID, let review {
                review.update(entryID, title: title, details: details, kind: kind, date: date,
                              endDate: end, reminderOffsets: offsets)
                detail = nil; draftEntryID = nil
                return true
            }
            let succeeded = isNewDetail
                ? save(title, details, kind, date, end, offsets) != nil
                : update(item, title, details, kind, date, end, offsets)
            guard succeeded else { return false }
            if isNewDetail { commitSignal += 1 }
            detail = nil
            return true
        }, onToggleCompleted: { toggle(item) }, onDelete: { remove(item) },
            isEmbedded: true, isCompactDesktopPane: true, isNew: isNewDetail,
            saveActionTitle: draftEntryID != nil ? "Готово" : "Сохранить", presentation: .captureWidget,
            widgetMaximumHeight: controller.availableHeight,
            onDismiss: { detail = nil; draftEntryID = nil })
            .id(item.id)
    }

    private func openDraft(_ entry: VoiceReviewEntry) {
        guard let review else { return }
        draftEntryID = entry.id
        isNewDetail = false
        detail = review.item(for: entry)
    }

    private func openResult(_ item: Item) {
        keyboardInteraction = true
        isNewDetail = false
        draftEntryID = nil
        detail = item
    }

    private func discardReview() {
        review = nil; detail = nil; draftEntryID = nil; error = nil
        commitSignal += 1
        controller.hide()
    }

    private func receiveBatch(_ batch: VoiceBatchReview) {
        guard review?.id != batch.id else { return }
        let session = VoiceBatchReviewSession(batch: batch)
        review = session
        // Widget-specific explicit confirmation. No records, links or alerts
        // exist until the user accepts the entire group.
    }

    private func save(_ title: String, _ details: String?, _ kind: EntryKind,
                      _ date: Date?, _ end: Date?, _ offsets: [Int]?) -> UUID? {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, kind != .event || date != nil else {
            error = "Для события укажите дату и время начала."; return nil
        }
        let item = Item(title: title, details: details, dueDate: date, entryKind: kind, endDate: end,
                        reminderOffsets: date == nil ? [] : (offsets ?? [account.defaultReminderMinutes(for: kind)]),
                        ownerID: account.userID)
        context.insert(item)
        guard commit() else { return nil }
        results = [item]; keyboardInteraction = false
        changed([item])
        return item.id
    }

    private func saveBatch(_ session: VoiceBatchReviewSession) -> Bool {
        guard session.canSave, review?.id == session.id else { return false }
        do {
            let items = try VoiceBatchPersistence.create(session.entries, ownerID: account.userID, context: context)
            for (entry, item) in zip(session.entries, items) where !VoiceReviewTesting.isEnabled {
                VoicePersonalizationStore.beginCapture(itemID: item.id, transcript: entry.sourceText,
                    title: entry.originalDraft.title, details: entry.originalDraft.details,
                    dueDate: entry.originalDraft.dueDate, referenceDate: session.batch.referenceDate)
            }
            changed(items)
            review = nil; results = []; keyboardInteraction = false; commitSignal += 1
            controller.hide()
            return true
        } catch { self.error = "Не удалось сохранить: \(error.localizedDescription)"; return false }
    }

    private func update(_ item: Item, _ title: String, _ details: String?, _ kind: EntryKind,
                        _ date: Date?, _ end: Date?, _ offsets: [Int]) -> Bool {
        guard item.ownerID == account.userID, item.deletedAt == nil else { return false }
        item.title = title; item.details = Item.normalizedDetails(details); item.entryKind = kind
        item.dueDate = date; item.endDate = kind == .event ? end : nil
        item.setReminderOffsets(date == nil ? [] : offsets); item.updatedAt = .now
        guard commit() else { return false }
        if !VoiceReviewTesting.isEnabled {
            VoicePersonalizationStore.confirmCorrection(itemID: item.id, title: item.title,
                                                        details: item.details, dueDate: item.dueDate)
        }
        changed([item]); return true
    }

    private func toggle(_ item: Item) -> Bool {
        item.setCompleted(!item.isCompleted)
        guard commit() else { return false }
        changed([item]); return true
    }

    private func remove(_ item: Item) -> Bool {
        guard deleteCaptured([item]) else { return false }
        results.removeAll { $0.id == item.id }; detail = nil
        if results.isEmpty { controller.hide() }
        return true
    }

    private func undoCreation() {
        guard deleteCaptured(results) else { return }
        results = []; controller.hide()
    }

    private func deleteCaptured(_ items: [Item]) -> Bool {
        guard !items.isEmpty, items.allSatisfy({ $0.ownerID == account.userID }) else { return false }
        do { try VoiceBatchPersistence.stageDeletion(items, context: context) }
        catch { context.rollback(); self.error = error.localizedDescription; return false }
        guard commit() else { return false }
        changed(items); return true
    }

    private func commit() -> Bool {
        do { try context.save(); return true }
        catch { context.rollback(); self.error = "Не удалось сохранить: \(error.localizedDescription)"; return false }
    }

    private func changed(_ items: [Item]) {
        error = nil
        guard !VoiceReviewTesting.isEnabled else { return }
        account.markLocalChange(modelContext: context)
        for item in items {
            reminderQueue.update(item) { error = $0 }
        }
    }
}

private struct MacCaptureResultsView: View {
    @State private var contentHeight: CGFloat = 60
    let items: [Item]
    let onEdit: (Item) -> Void
    let onUndo: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label(items.count == 1 ? "Сохранено" : "Сохранено: \(items.count)", systemImage: "checkmark")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        MemoryItemRow(item: item, onEdit: { onEdit(item) }, showsContextMenu: false)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }.scrollBounceBehavior(.basedOnSize)
                .frame(height: min(300, max(60, contentHeight)))
            HStack(spacing: 8) {
                Button(action: onUndo) { Image(systemName: "trash") }
                    .buttonStyle(MemoryWidgetActionStyle(iconOnly: true, destructive: true)).help("Отменить создание")
                    .accessibilityLabel(items.count == 1 ? "Отменить создание записи" : "Отменить создание этих записей")
                Button(action: onClose) { Text("Готово").frame(maxWidth: .infinity) }
                    .buttonStyle(MemoryWidgetActionStyle(prominent: true))
            }
        }.padding(12)
    }
}
#endif
