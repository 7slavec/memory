import Foundation
import SwiftData

@MainActor
enum RecordLinkReconciler {
    /// Purely local merge; no suspension between mutating the models and saving.
    static func merge(_ remote: [RemoteRecordLink], userID: UUID, context: ModelContext) throws -> [RemoteRecordLink] {
        let owner = userID.uuidString.lowercased()
        let items = try context.fetch(FetchDescriptor<Item>()).filter { $0.ownerID == owner }
        let itemByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let allLinks = try context.fetch(FetchDescriptor<RecordLink>())
        for link in allLinks where link.ownerID == nil {
            if itemByID[link.firstID] != nil && itemByID[link.secondID] != nil {
                link.ownerID = owner
                link.updatedAt = max(.now, link.updatedAt.addingTimeInterval(0.003))
            }
        }
        var localByID = Dictionary(uniqueKeysWithValues: allLinks.filter { $0.ownerID == owner }.map { ($0.id, $0) })
        var remoteByID: [String: RemoteRecordLink] = [:]
        for value in remote where value.userID == userID && value.firstID != value.secondID
            && value.id == RecordLink.key(value.firstID, value.secondID) {
            guard itemByID[value.firstID] != nil, itemByID[value.secondID] != nil else { continue }
            remoteByID[value.id] = value
            if let local = localByID[value.id] {
                let newer = SupabaseDate.isMeaningfullyNewer(value.updatedDate, than: local.updatedAt)
                let tied = !SupabaseDate.isMeaningfullyNewer(local.updatedAt, than: value.updatedDate) && !newer
                if newer || (tied && value.deletedAt != nil && local.deletedAt == nil) { value.apply(to: local) }
            } else {
                // Never let remote data overwrite a local association owned by another account.
                guard !allLinks.contains(where: { $0.id == value.id }) else { continue }
                let local = value.makeLocal()
                context.insert(local)
                localByID[local.id] = local
            }
        }
        var uploads: [RemoteRecordLink] = []
        for link in localByID.values {
            guard let first = itemByID[link.firstID], let second = itemByID[link.secondID] else { continue }
            if (first.deletedAt != nil || second.deletedAt != nil), link.deletedAt == nil {
                link.updatedAt = max(.now, link.updatedAt.addingTimeInterval(0.003))
                link.deletedAt = link.updatedAt
            }
            if let remote = remoteByID[link.id] {
                if SupabaseDate.isMeaningfullyNewer(link.updatedAt, than: remote.updatedDate)
                    || (link.deletedAt != nil && remote.deletedAt == nil && !SupabaseDate.isMeaningfullyNewer(remote.updatedDate, than: link.updatedAt)) {
                    uploads.append(RemoteRecordLink(link, userID: userID))
                }
            } else { uploads.append(RemoteRecordLink(link, userID: userID)) }
        }
        do { try context.save() }
        catch { context.rollback(); throw error }
        return uploads
    }
}
