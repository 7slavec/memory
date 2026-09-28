import Foundation
import SwiftData

/// A symmetric association, independent of dates and completion. Deletions are
/// retained as tombstones so an offline device cannot recreate a removed link.
@Model
final class RecordLink {
    @Attribute(.unique) var id: String
    var firstID: UUID
    var secondID: UUID
    var ownerID: String?
    var updatedAt: Date
    var deletedAt: Date?

    init(_ first: UUID, _ second: UUID, ownerID: String?, updatedAt: Date = .now, deletedAt: Date? = nil) {
        let ordered = [first, second].sorted { $0.uuidString < $1.uuidString }
        firstID = ordered[0]
        secondID = ordered[1]
        id = Self.key(first, second)
        self.ownerID = ownerID
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    static func key(_ first: UUID, _ second: UUID) -> String {
        [first.uuidString.lowercased(), second.uuidString.lowercased()].sorted().joined(separator: "_")
    }

    func otherID(than id: UUID) -> UUID? {
        if firstID == id { return secondID }
        if secondID == id { return firstID }
        return nil
    }
}

enum RecordLinkError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Запись недоступна. Возможно, она удалена или принадлежит другому аккаунту." }
}

@MainActor
enum RecordLinkService {
    static func unlinkAll(for item: Item, ownerID: String?, context: ModelContext) throws {
        try RecordGroupService.dissolve(containing: item, ownerID: ownerID, context: context)
    }

    static func setLinked(_ enabled: Bool, first: Item, second: Item, ownerID: String?, context: ModelContext) throws {
        guard first.id != second.id, first.ownerID == ownerID, second.ownerID == ownerID,
              first.deletedAt == nil, second.deletedAt == nil,
              first.modelContext === context, second.modelContext === context else {
            throw RecordLinkError.unavailable
        }
        let key = RecordLink.key(first.id, second.id)
        let existing = try context.fetch(FetchDescriptor<RecordLink>(predicate: #Predicate { $0.id == key })).first
        guard existing == nil || existing?.ownerID == ownerID else { throw RecordLinkError.unavailable }
        if !enabled && existing == nil { return }
        if let existing, (existing.deletedAt == nil) == enabled { return }
        let link = existing ?? RecordLink(first.id, second.id, ownerID: ownerID)
        if existing == nil { context.insert(link) }
        link.updatedAt = max(.now, link.updatedAt.addingTimeInterval(0.003))
        link.deletedAt = enabled ? nil : link.updatedAt
        do { try context.save() }
        catch { context.rollback(); throw error }
    }

    /// Called in the same save transaction as deleting a record.
    static func markDeleted(for item: Item, context: ModelContext) throws {
        try RecordGroupService.detachBeforeDeletion(item, context: context)
    }
}
