import Foundation
import SwiftData

@MainActor
enum ArchiveDeletion {
    /// One save/sync per batch. Revalidate the confirmation snapshot against current state.
    static func clear(ids: Set<UUID>, ownerID: String?, context: ModelContext, now: Date = .now) throws -> [UUID] {
        let items = try context.fetch(FetchDescriptor<Item>()).filter {
            ids.contains($0.id) && $0.ownerID == ownerID && $0.deletedAt == nil
                && !RecordLinkIndex.canAdd($0, now: now)
        }
        do {
            for item in items {
                try RecordLinkService.markDeleted(for: item, context: context)
                item.markDeleted()
            }
            try context.save()
            return items.map(\.id)
        } catch {
            context.rollback()
            throw error
        }
    }
}
