import Foundation

/// Presentation-only index. Counts direct, visible neighbours, not a transitive group.
struct RecordLinkIndex {
    private var neighbours: [UUID: Set<UUID>] = [:]

    init(items: [Item], links: [RecordLink], ownerID: String?) {
        let visible = Set(items.filter { $0.ownerID == ownerID && $0.deletedAt == nil }.map(\.id))
        for link in links where link.ownerID == ownerID && link.deletedAt == nil {
            guard link.firstID != link.secondID,
                  visible.contains(link.firstID), visible.contains(link.secondID) else { continue }
            neighbours[link.firstID, default: []].insert(link.secondID)
            neighbours[link.secondID, default: []].insert(link.firstID)
        }
    }

    func count(for id: UUID) -> Int { neighbours[id]?.count ?? 0 }

    /// Matches the archive: events remain active through their last calendar day.
    static func canAdd(_ item: Item, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard item.deletedAt == nil, !item.isCompleted else { return false }
        guard item.isEvent, let finalDate = item.endDate ?? item.dueDate else { return true }
        let boundary = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: finalDate)) ?? finalDate
        return now < boundary
    }
}
