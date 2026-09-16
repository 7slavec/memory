import Foundation

struct RemoteTask: Codable, Identifiable, Sendable {
    let id: UUID
    let userID: UUID
    var title: String
    var dueAt: String?
    var notificationsEnabled: Bool
    var isCompleted: Bool
    var completedAt: String?
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case title
        case dueAt = "due_at"
        case notificationsEnabled = "notifications_enabled"
        case isCompleted = "is_completed"
        case completedAt = "completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(item: Item, userID: UUID) {
        id = item.id
        self.userID = userID
        title = item.title
        dueAt = item.dueDate.map(SupabaseDate.string)
        notificationsEnabled = item.notificationsEnabled
        isCompleted = item.isCompleted
        completedAt = item.completedAt.map(SupabaseDate.string)
        createdAt = SupabaseDate.string(item.timestamp)
        updatedAt = SupabaseDate.string(item.updatedAt)
        deletedAt = item.deletedAt.map(SupabaseDate.string)
    }

    var createdDate: Date { SupabaseDate.date(createdAt) ?? .distantPast }
    var updatedDate: Date { SupabaseDate.date(updatedAt) ?? .distantPast }

    func makeLocalItem() -> Item {
        Item(
            title: title,
            timestamp: createdDate,
            isCompleted: isCompleted,
            dueDate: dueAt.flatMap(SupabaseDate.date),
            notificationsEnabled: notificationsEnabled,
            ownerID: userID.uuidString.lowercased(),
            id: id,
            completedAt: completedAt.flatMap(SupabaseDate.date),
            updatedAt: updatedDate,
            deletedAt: deletedAt.flatMap(SupabaseDate.date)
        )
    }

    func apply(to item: Item) {
        item.title = title
        item.timestamp = createdDate
        item.isCompleted = isCompleted
        item.dueDate = dueAt.flatMap(SupabaseDate.date)
        item.notificationsEnabled = notificationsEnabled
        item.completedAt = completedAt.flatMap(SupabaseDate.date)
        item.updatedAt = updatedDate
        item.deletedAt = deletedAt.flatMap(SupabaseDate.date)
        item.ownerID = userID.uuidString.lowercased()
    }
}

enum SupabaseDate {
    // ISO8601DateFormatter and PostgreSQL can retain different fractions of a millisecond.
    // Treat that transport-only difference as the same revision to avoid upload loops.
    nonisolated private static let comparisonTolerance: TimeInterval = 0.002

    nonisolated private static func formatter(withFractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = withFractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }

    nonisolated static func string(_ date: Date) -> String {
        formatter(withFractionalSeconds: true).string(from: date)
    }

    nonisolated static func date(_ value: String) -> Date? {
        formatter(withFractionalSeconds: true).date(from: value)
            ?? formatter(withFractionalSeconds: false).date(from: value)
    }

    nonisolated static func isMeaningfullyNewer(_ candidate: Date, than reference: Date) -> Bool {
        candidate.timeIntervalSince(reference) > comparisonTolerance
    }
}
