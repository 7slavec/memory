import Foundation
import SwiftData
import Testing
@testable import Memory

@MainActor
struct RecordLinkTests {
    @Test func unlinkAllPreservesRecordsAndUnrelatedLinks() throws {
        let context = try makeContext()
        let a = Item(title: "Заявка"), b = Item(title: "Вебинар"), c = Item(title: "Материалы")
        for item in [a, b, c] { context.insert(item) }
        try context.save()
        try RecordLinkService.setLinked(true, first: a, second: b, ownerID: nil, context: context)
        try RecordLinkService.setLinked(true, first: a, second: c, ownerID: nil, context: context)
        try RecordLinkService.setLinked(true, first: b, second: c, ownerID: nil, context: context)
        let links = try context.fetch(FetchDescriptor<RecordLink>())
        #expect(RecordLinkIndex(items: [a, b, c], links: links, ownerID: nil).count(for: a.id) == 2)
        try RecordLinkService.unlinkAll(for: a, ownerID: nil, context: context)
        let remaining = links.filter { $0.deletedAt == nil }
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == RecordLink.key(b.id, c.id))
        #expect([a, b, c].allSatisfy { $0.deletedAt == nil && !$0.isCompleted })
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 3)
        let index = RecordLinkIndex(items: [a, b, c], links: links, ownerID: nil)
        #expect(index.count(for: a.id) == 0)
        #expect(index.count(for: b.id) == 1)
    }

    @Test func linkCandidatesExcludeArchiveButIncludeInboxAndOverdue() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let today = calendar.startOfDay(for: now)
        let record = Item(title: "Входящие")
        #expect(RecordLinkIndex.canAdd(record, now: now, calendar: calendar))
        record.dueDate = today.addingTimeInterval(-86_400)
        #expect(RecordLinkIndex.canAdd(record, now: now, calendar: calendar))
        record.entryKind = .event
        #expect(!RecordLinkIndex.canAdd(record, now: now, calendar: calendar))
        record.endDate = today
        #expect(RecordLinkIndex.canAdd(record, now: now, calendar: calendar))
        record.entryKind = .reminder
        record.setCompleted(true)
        #expect(!RecordLinkIndex.canAdd(record, now: now, calendar: calendar))
        record.setCompleted(false); record.markDeleted()
        #expect(!RecordLinkIndex.canAdd(record, now: now, calendar: calendar))
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: Item.self, RecordLink.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    @Test func symmetricIdempotentLinksDoNotChangeRecords() throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = Item(title: "Заявка", dueDate: date)
        let second = Item(title: "Вебинар", dueDate: date.addingTimeInterval(3_600))
        second.entryKind = .event
        context.insert(first); context.insert(second); try context.save()
        try RecordLinkService.setLinked(true, first: first, second: second, ownerID: nil, context: context)
        try RecordLinkService.setLinked(true, first: second, second: first, ownerID: nil, context: context)
        let links = try context.fetch(FetchDescriptor<RecordLink>())
        #expect(links.count == 1)
        #expect(links.first?.otherID(than: first.id) == second.id)
        first.setCompleted(true); try context.save()
        #expect(!second.isCompleted)
        #expect(first.dueDate == date)
        #expect(second.dueDate == date.addingTimeInterval(3_600))
        try RecordLinkService.setLinked(false, first: second, second: first, ownerID: nil, context: context)
        #expect(links.first?.deletedAt != nil)
        #expect(first.deletedAt == nil && second.deletedAt == nil)
        try RecordLinkService.setLinked(true, first: first, second: second, ownerID: nil, context: context)
        #expect(links.first?.deletedAt == nil)
        #expect(try context.fetchCount(FetchDescriptor<RecordLink>()) == 1)
    }

    @Test func invalidEndpointsAreRejected() throws {
        let context = try makeContext()
        let first = Item(title: "Один")
        let second = Item(title: "Другой аккаунт")
        second.ownerID = UUID().uuidString.lowercased()
        context.insert(first); context.insert(second); try context.save()
        #expect(throws: RecordLinkError.self) {
            try RecordLinkService.setLinked(true, first: first, second: first, ownerID: nil, context: context)
        }
        #expect(throws: RecordLinkError.self) {
            try RecordLinkService.setLinked(true, first: first, second: second, ownerID: nil, context: context)
        }
        second.ownerID = nil; second.markDeleted(); try context.save()
        #expect(throws: RecordLinkError.self) {
            try RecordLinkService.setLinked(true, first: first, second: second, ownerID: nil, context: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<RecordLink>()) == 0)
    }

    @Test func deletionOnlyTombstonesLinksNotOtherRecords() throws {
        let context = try makeContext()
        let first = Item(title: "Один"), second = Item(title: "Два")
        context.insert(first); context.insert(second); try context.save()
        try RecordLinkService.setLinked(true, first: first, second: second, ownerID: nil, context: context)
        try RecordLinkService.markDeleted(for: first, context: context)
        first.markDeleted(); try context.save()
        #expect(try context.fetch(FetchDescriptor<RecordLink>()).first?.deletedAt != nil)
        #expect(second.deletedAt == nil)
    }

    @Test func mergeAdoptsLocalLinksAndRejectsStaleResurrection() throws {
        let context = try makeContext()
        let owner = UUID()
        let first = Item(title: "Один"), second = Item(title: "Два")
        context.insert(first); context.insert(second); try context.save()
        try RecordLinkService.setLinked(true, first: first, second: second, ownerID: nil, context: context)
        first.ownerID = owner.uuidString.lowercased(); second.ownerID = first.ownerID
        let uploads = try RecordLinkReconciler.merge([], userID: owner, context: context)
        #expect(uploads.count == 1)
        let link = try #require(context.fetch(FetchDescriptor<RecordLink>()).first)
        #expect(link.ownerID == first.ownerID)
        let stale = RemoteRecordLink(link, userID: owner)
        try RecordLinkService.setLinked(false, first: first, second: second, ownerID: first.ownerID, context: context)
        let removal = try RecordLinkReconciler.merge([stale], userID: owner, context: context)
        #expect(link.deletedAt != nil)
        #expect(removal.count == 1 && removal.first?.deletedAt != nil)
        let encoded = try JSONEncoder().encode(removal)
        let roundTrip = try JSONDecoder().decode([RemoteRecordLink].self, from: encoded)
        #expect(roundTrip.first?.id == link.id)
        #expect(try RecordLinkReconciler.merge(roundTrip, userID: owner, context: context).isEmpty)
    }

    @Test func remoteTombstoneWinsTieAndForeignAccountIsIgnored() throws {
        let context = try makeContext()
        let owner = UUID()
        let first = Item(title: "Один"), second = Item(title: "Два")
        first.ownerID = owner.uuidString.lowercased(); second.ownerID = first.ownerID
        context.insert(first); context.insert(second); try context.save()
        try RecordLinkService.setLinked(true, first: first, second: second, ownerID: first.ownerID, context: context)
        let local = try #require(context.fetch(FetchDescriptor<RecordLink>()).first)
        let tombstone = RecordLink(first.id, second.id, ownerID: first.ownerID, updatedAt: local.updatedAt, deletedAt: local.updatedAt)
        let foreign = RemoteRecordLink(tombstone, userID: UUID())
        _ = try RecordLinkReconciler.merge([foreign], userID: owner, context: context)
        #expect(local.deletedAt == nil)
        _ = try RecordLinkReconciler.merge([RemoteRecordLink(tombstone, userID: owner)], userID: owner, context: context)
        #expect(local.deletedAt != nil)
    }

    @Test func additiveSchemaPreservesOldStoreAndPersistsLinks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("norka-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.store")
        let originalID: UUID = try {
            let old = try ModelContainer(for: Item.self, configurations: ModelConfiguration(url: url))
            let context = ModelContext(old)
            let item = Item(title: "Существующая запись", details: "Не потерять описание", dueDate: Date(timeIntervalSince1970: 1_800_000_000))
            context.insert(item); try context.save()
            return item.id
        }()
        try {
            let upgraded = try ModelContainer(for: Item.self, RecordLink.self, configurations: ModelConfiguration(url: url))
            let context = ModelContext(upgraded)
            let item = try #require(context.fetch(FetchDescriptor<Item>()).first)
            #expect(item.id == originalID)
            #expect(item.details == "Не потерять описание")
            #expect(item.dueDate == Date(timeIntervalSince1970: 1_800_000_000))
            let other = Item(title: "Новая связанная запись")
            context.insert(other); try context.save()
            try RecordLinkService.setLinked(true, first: item, second: other, ownerID: nil, context: context)
        }()
        let reopened = try ModelContainer(for: Item.self, RecordLink.self, configurations: ModelConfiguration(url: url))
        let context = ModelContext(reopened)
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 2)
        #expect(try context.fetch(FetchDescriptor<RecordLink>()).first?.otherID(than: originalID) != nil)
    }
}
