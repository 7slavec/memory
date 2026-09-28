import Foundation
import SwiftData

struct RemoteRecordLink: Codable, Sendable {
    let id: String
    let userID: UUID
    let firstID: UUID
    let secondID: UUID
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id", firstID = "first_id", secondID = "second_id"
        case updatedAt = "updated_at", deletedAt = "deleted_at"
    }

    init(_ link: RecordLink, userID: UUID) {
        id = link.id; self.userID = userID
        firstID = link.firstID; secondID = link.secondID
        updatedAt = SupabaseDate.string(link.updatedAt)
        deletedAt = link.deletedAt.map(SupabaseDate.string)
    }

    var updatedDate: Date { SupabaseDate.date(updatedAt) ?? .distantPast }

    func apply(to link: RecordLink) {
        link.ownerID = userID.uuidString.lowercased()
        link.updatedAt = updatedDate
        link.deletedAt = deletedAt.flatMap(SupabaseDate.date)
    }

    func makeLocal() -> RecordLink {
        RecordLink(firstID, secondID, ownerID: userID.uuidString.lowercased(),
                   updatedAt: updatedDate, deletedAt: deletedAt.flatMap(SupabaseDate.date))
    }
}
