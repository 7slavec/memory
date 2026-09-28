import Foundation
import SwiftData

/// Group operations reuse the synced edge schema; no record or schema migration.
/// Each mutation is one local transaction. Survivors remain connected when any
/// member is removed, including a bridge in a legacy A–B–C chain.
@MainActor
enum RecordGroupService {
    static func add(_ candidate: Item, to anchor: Item, ownerID: String?, context: ModelContext) throws {
        try validate(anchor, ownerID: ownerID, context: context)
        try validate(candidate, ownerID: ownerID, context: context)
        guard candidate.id != anchor.id, RecordLinkIndex.canAdd(candidate) else { throw RecordLinkError.unavailable }
        try transaction(context) {
            let snapshot = try Snapshot(ownerID: ownerID, context: context)
            let members = snapshot.index.memberIDs(for: anchor.id).union(snapshot.index.memberIDs(for: candidate.id))
            try snapshot.connect(members, context: context)
        }
    }

    static func remove(_ member: Item, from anchor: Item, ownerID: String?, context: ModelContext) throws {
        try validate(anchor, ownerID: ownerID, context: context)
        try validate(member, ownerID: ownerID, context: context)
        try transaction(context) {
            let snapshot = try Snapshot(ownerID: ownerID, context: context)
            guard snapshot.index.memberIDs(for: anchor.id).contains(member.id) else { throw RecordLinkError.unavailable }
            try snapshot.detach(member.id, context: context)
        }
    }

    static func dissolve(containing anchor: Item, ownerID: String?, context: ModelContext) throws {
        try validate(anchor, ownerID: ownerID, context: context)
        try transaction(context) {
            let snapshot = try Snapshot(ownerID: ownerID, context: context)
            let members = snapshot.index.memberIDs(for: anchor.id)
            for link in snapshot.links.values where link.ownerID == ownerID && link.deletedAt == nil
                && members.contains(link.firstID) && members.contains(link.secondID) {
                snapshot.tombstone(link)
            }
        }
    }

    /// Part of the caller's record-deletion transaction; does not save on its own.
    static func detachBeforeDeletion(_ item: Item, context: ModelContext) throws {
        try validate(item, ownerID: item.ownerID, context: context)
        try Snapshot(ownerID: item.ownerID, context: context).detach(item.id, context: context)
    }

    private static func validate(_ item: Item, ownerID: String?, context: ModelContext) throws {
        guard item.ownerID == ownerID, item.deletedAt == nil, item.modelContext === context else {
            throw RecordLinkError.unavailable
        }
    }

    private static func transaction(_ context: ModelContext, changes: () throws -> Void) throws {
        do { try changes(); try context.save() }
        catch { context.rollback(); throw error }
    }

    private struct Snapshot {
        let ownerID: String?
        let links: [String: RecordLink]
        let index: RecordLinkIndex
        let timestamp: Date

        init(ownerID: String?, context: ModelContext) throws {
            let allLinks = try context.fetch(FetchDescriptor<RecordLink>())
            let items = try context.fetch(FetchDescriptor<Item>())
            self.ownerID = ownerID
            links = Dictionary(uniqueKeysWithValues: allLinks.map { ($0.id, $0) })
            index = RecordLinkIndex(items: items, links: allLinks, ownerID: ownerID)
            let previous = allLinks.filter { $0.ownerID == ownerID }.map(\.updatedAt).max() ?? .distantPast
            timestamp = max(.now, previous.addingTimeInterval(0.003))
        }

        func connect(_ members: Set<UUID>, context: ModelContext) throws {
            let ids = members.sorted { $0.uuidString < $1.uuidString }
            for (offset, first) in ids.enumerated() {
                for second in ids.dropFirst(offset + 1) {
                    let key = RecordLink.key(first, second)
                    if let existing = links[key] {
                        guard existing.ownerID == ownerID else { throw RecordLinkError.unavailable }
                        if existing.deletedAt != nil {
                            existing.updatedAt = timestamp
                            existing.deletedAt = nil
                        }
                    } else {
                        context.insert(RecordLink(first, second, ownerID: ownerID, updatedAt: timestamp))
                    }
                }
            }
        }

        func detach(_ id: UUID, context: ModelContext) throws {
            try connect(index.memberIDs(for: id).subtracting([id]), context: context)
            for link in links.values where link.ownerID == ownerID && link.deletedAt == nil
                && (link.firstID == id || link.secondID == id) {
                tombstone(link)
            }
        }

        func tombstone(_ link: RecordLink) {
            link.updatedAt = timestamp
            link.deletedAt = timestamp
        }
    }
}
