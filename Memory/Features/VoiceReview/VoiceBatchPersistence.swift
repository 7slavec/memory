import Foundation
import SwiftData

@MainActor
enum VoiceBatchPersistence {
    /// Only new records from this capture can be auto-linked. One save commits
    /// both records and edges; manual changes later are never regenerated.
    static func create(_ entries: [VoiceReviewEntry], ownerID: String?, context: ModelContext) throws -> [Item] {
        guard !entries.isEmpty, entries.allSatisfy({ $0.persistedItemID == nil }) else {
            throw RecordLinkError.unavailable
        }
        do {
            let items = entries.map { entry in
                Item(title: entry.title.trimmingCharacters(in: .whitespacesAndNewlines),
                     details: entry.details, dueDate: entry.dueDate, entryKind: entry.kind,
                     endDate: entry.kind == .event ? entry.endDate : nil,
                     reminderOffsets: entry.dueDate == nil ? [] : entry.reminderOffsets,
                     ownerID: ownerID)
            }
            items.forEach(context.insert)
            let groups = Dictionary(grouping: entries.indices.filter { entries[$0].linkGroup != nil }) {
                entries[$0].linkGroup!
            }
            for members in groups.values where members.count > 1 {
                for (offset, first) in members.enumerated() {
                    for second in members.dropFirst(offset + 1) {
                        context.insert(RecordLink(items[first].id, items[second].id, ownerID: ownerID))
                    }
                }
            }
            try context.save()
            return items
        } catch {
            rollback(context)
            throw error
        }
    }

    /// Caller owns the transaction, including edits to retained entries.
    static func stageDeletion(_ items: [Item], context: ModelContext) throws {
        for item in items {
            try RecordLinkService.markDeleted(for: item, context: context)
            item.markDeleted()
        }
    }

    static func rollback(_ context: ModelContext) {
        // Register synchronous property edits before asking SwiftData to revert.
        context.processPendingChanges()
        context.rollback()
    }
}
