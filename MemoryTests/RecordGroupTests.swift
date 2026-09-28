import Foundation
import SwiftData
import Testing
@testable import Memory

@MainActor
struct RecordGroupTests {
    private func fixture() throws -> (ModelContext, [Item]) {
        let container = try ModelContainer(for: Item.self, RecordLink.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let items = (0..<5).map { Item(title: "Запись \($0)") }
        for item in items { context.insert(item) }
        try context.save()
        return (context, items)
    }

    private func index(_ context: ModelContext) throws -> RecordLinkIndex {
        RecordLinkIndex(items: try context.fetch(FetchDescriptor<Item>()),
                        links: try context.fetch(FetchDescriptor<RecordLink>()), ownerID: nil)
    }

    @Test func legacyChainHasOneGroupFromEveryMemberWithoutWriting() throws {
        let (context, items) = try fixture()
        try RecordLinkService.setLinked(true, first: items[0], second: items[1], ownerID: nil, context: context)
        try RecordLinkService.setLinked(true, first: items[1], second: items[2], ownerID: nil, context: context)
        let group = Set(items.prefix(3).map(\.id))
        let snapshot = try index(context)
        for item in items.prefix(3) {
            #expect(snapshot.memberIDs(for: item.id) == group)
            #expect(snapshot.count(for: item.id) == 2)
        }
        #expect(snapshot.memberIDs(for: items[3].id) == [items[3].id])
        #expect(try context.fetchCount(FetchDescriptor<RecordLink>()) == 2)
        #expect(!context.hasChanges)
    }

    @Test func removingBridgeOrCurrentMemberKeepsRemainingGroup() throws {
        let (context, items) = try fixture()
        for n in 0..<3 {
            try RecordLinkService.setLinked(true, first: items[n], second: items[n + 1], ownerID: nil, context: context)
        }
        try RecordGroupService.remove(items[1], from: items[1], ownerID: nil, context: context)
        let survivors = Set([items[0].id, items[2].id, items[3].id])
        let snapshot = try index(context)
        for id in survivors { #expect(snapshot.memberIDs(for: id) == survivors) }
        #expect(snapshot.count(for: items[1].id) == 0)
        #expect(items.allSatisfy { $0.deletedAt == nil && !$0.isCompleted })
        // Reopening the persisted edges and merging a tombstone must not restore membership.
        let owner = UUID()
        for item in items { item.ownerID = owner.uuidString.lowercased() }
        let records = try RecordLinkReconciler.merge([], userID: owner, context: context)
        _ = try RecordLinkReconciler.merge(records, userID: owner, context: context)
        let reopened = RecordLinkIndex(items: items, links: try context.fetch(FetchDescriptor<RecordLink>()), ownerID: owner.uuidString.lowercased())
        #expect(reopened.memberIDs(for: items[0].id) == survivors)
        #expect(reopened.count(for: items[1].id) == 0)
    }

    @Test func addingFromAnyMemberMergesBothGroupsAndDissolveLeavesOtherGroups() throws {
        let (context, items) = try fixture()
        try RecordGroupService.add(items[1], to: items[0], ownerID: nil, context: context)
        try RecordGroupService.add(items[3], to: items[2], ownerID: nil, context: context)
        try RecordGroupService.add(items[2], to: items[1], ownerID: nil, context: context)
        let ids = Set(items.prefix(4).map(\.id))
        for item in items.prefix(4) { #expect(try index(context).memberIDs(for: item.id) == ids) }
        try RecordGroupService.remove(items[0], from: items[2], ownerID: nil, context: context)
        try RecordGroupService.add(items[4], to: items[0], ownerID: nil, context: context)
        try RecordGroupService.dissolve(containing: items[3], ownerID: nil, context: context)
        let snapshot = try index(context)
        #expect(snapshot.memberIDs(for: items[0].id) == [items[0].id, items[4].id])
        for item in items[1...3] { #expect(snapshot.count(for: item.id) == 0) }
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 5)
        #expect(items.allSatisfy { $0.deletedAt == nil })
    }

    @Test func deletingLegacyBridgePreservesOtherMembers() throws {
        let (context, items) = try fixture()
        try RecordLinkService.setLinked(true, first: items[0], second: items[1], ownerID: nil, context: context)
        try RecordLinkService.setLinked(true, first: items[1], second: items[2], ownerID: nil, context: context)
        try RecordLinkService.markDeleted(for: items[1], context: context)
        items[1].markDeleted(); try context.save()
        #expect(try index(context).memberIDs(for: items[0].id) == [items[0].id, items[2].id])
        #expect(items[0].deletedAt == nil && items[2].deletedAt == nil)
    }

    @Test func archiveForeignOwnerAndNonMemberAreRejected() throws {
        let (context, items) = try fixture()
        items[1].setCompleted(true)
        #expect(throws: RecordLinkError.self) {
            try RecordGroupService.add(items[1], to: items[0], ownerID: nil, context: context)
        }
        items[2].ownerID = UUID().uuidString
        #expect(throws: RecordLinkError.self) {
            try RecordGroupService.add(items[2], to: items[0], ownerID: nil, context: context)
        }
        try context.save()
        #expect(throws: RecordLinkError.self) {
            try RecordGroupService.remove(items[3], from: items[0], ownerID: nil, context: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<RecordLink>()) == 0)
    }
}
