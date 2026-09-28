import Foundation

/// Connected records form one group, regardless of which member opens it.
struct RecordLinkIndex {
    private var groups: [UUID: Set<UUID>] = [:]

    init(items: [Item], links: [RecordLink], ownerID: String?) {
        let visible = Set(items.filter { $0.ownerID == ownerID && $0.deletedAt == nil }.map(\.id))
        var neighbours: [UUID: Set<UUID>] = [:]
        for link in links where link.ownerID == ownerID && link.deletedAt == nil {
            guard link.firstID != link.secondID,
                  visible.contains(link.firstID), visible.contains(link.secondID) else { continue }
            neighbours[link.firstID, default: []].insert(link.secondID)
            neighbours[link.secondID, default: []].insert(link.firstID)
        }
        var visited: Set<UUID> = []
        for id in visible where !visited.contains(id) {
            var members: Set<UUID> = [id]
            var pending = [id]
            visited.insert(id)
            while let next = pending.popLast() {
                for neighbour in neighbours[next, default: []] where visited.insert(neighbour).inserted {
                    members.insert(neighbour)
                    pending.append(neighbour)
                }
            }
            for member in members { groups[member] = members }
        }
    }

    func memberIDs(for id: UUID) -> Set<UUID> { groups[id] ?? [] }
    func count(for id: UUID) -> Int { max(0, memberIDs(for: id).count - 1) }

    /// Matches the archive: events remain active through their last calendar day.
    static func canAdd(_ item: Item, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard item.deletedAt == nil, !item.isCompleted else { return false }
        guard item.isEvent, let finalDate = item.endDate ?? item.dueDate else { return true }
        let boundary = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: finalDate)) ?? finalDate
        return now < boundary
    }
}
