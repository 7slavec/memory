import Foundation
import Combine

struct VoiceReviewEntry: Identifiable, Equatable {
    let id: UUID
    let sourceText: String
    let originalDraft: ReminderDraft
    var title: String
    var details: String
    var kind: EntryKind
    var dueDate: Date?
    var endDate: Date?
    var reminderOffsets: [Int]
    var persistedItemID: UUID?

    init(_ entry: VoiceCaptureEntry, defaultReminderMinutes: Int = 0) {
        id = UUID()
        sourceText = entry.sourceText
        originalDraft = entry.draft
        title = entry.draft.title
        details = entry.draft.details ?? ""
        kind = entry.kind
        dueDate = entry.draft.dueDate
        endDate = entry.endDate
        reminderOffsets = entry.draft.dueDate == nil
            ? []
            : (entry.draft.reminderOffsets.isEmpty
                ? [defaultReminderMinutes]
                : entry.draft.reminderOffsets)
        persistedItemID = nil
    }

    mutating func applyEditorChanges(
        title: String,
        details: String?,
        kind: EntryKind,
        date: Date?,
        endDate: Date?,
        reminderOffsets: [Int]
    ) {
        self.title = title
        self.details = details ?? ""
        self.kind = kind
        dueDate = date
        self.endDate = kind == .event ? endDate : nil
        self.reminderOffsets = date == nil ? [] : reminderOffsets
    }
}

struct VoiceBatchReview: Identifiable {
    let id = UUID()
    let referenceDate: Date
    let entries: [VoiceReviewEntry]

    var isPersisted: Bool {
        !entries.isEmpty && entries.allSatisfy { $0.persistedItemID != nil }
    }
}

enum VoiceEntryCountLabel {
    static func short(_ count: Int) -> String {
        let word: String
        if (11...14).contains(count % 100) {
            word = "записей"
        } else {
            switch count % 10 {
            case 1: word = "запись"
            case 2...4: word = "записи"
            default: word = "записей"
            }
        }
        return "\(count) \(word)"
    }
}

@MainActor
final class VoiceBatchReviewSession: ObservableObject, Identifiable {
    let batch: VoiceBatchReview
    @Published var entries: [VoiceReviewEntry]
    @Published var selectedEntryID: UUID?

    var id: UUID { batch.id }
    var hasChanges: Bool { entries != batch.entries }
    var canSave: Bool {
        !entries.isEmpty && entries.allSatisfy {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && ($0.kind != .event || $0.dueDate != nil)
                && ($0.endDate == nil || ($0.dueDate != nil && $0.endDate! > $0.dueDate!))
        }
    }

    init(batch: VoiceBatchReview) {
        self.batch = batch
        entries = batch.entries
    }

    func item(for entry: VoiceReviewEntry) -> Item {
        Item(
            title: entry.title,
            details: entry.details,
            dueDate: entry.dueDate,
            entryKind: entry.kind,
            endDate: entry.endDate,
            reminderOffsets: entry.reminderOffsets,
            id: entry.id
        )
    }

    func update(
        _ entryID: UUID,
        title: String,
        details: String?,
        kind: EntryKind,
        date: Date?,
        endDate: Date?,
        reminderOffsets: [Int]
    ) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].applyEditorChanges(
            title: title,
            details: details,
            kind: kind,
            date: date,
            endDate: endDate,
            reminderOffsets: reminderOffsets
        )
    }

    func remove(_ entryID: UUID) {
        entries.removeAll { $0.id == entryID }
        selectedEntryID = nil
    }
}
