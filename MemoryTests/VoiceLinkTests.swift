import Foundation
import SwiftData
import Testing
@testable import Memory

@MainActor
struct VoiceLinkTests {
    private let speech = "В пятницу вебинар, отправить заявку, чтобы попасть на этот вебинар"

    private func result(_ groups: String? = nil) throws -> VoiceCaptureResult {
        let metadata = groups.map { ",\"linkGroups\":\($0)" } ?? ""
        let json = """
        {"entries":[
        {"title":"Вебинар","kind":"event","dueDate":"2026-10-02T19:00:00+04:00","reminderOffsets":[],"confidence":"high","ambiguities":[]},
        {"title":"Отправить заявку","kind":"reminder","reminderOffsets":[],"confidence":"medium","ambiguities":["missingDate"]}
        ]\(metadata)}
        """
        return try JSONDecoder().decode(RemoteVoiceCaptureResponse.self, from: Data(json.utf8))
            .captureResult(transcript: speech, dateFormatter: ISO8601DateFormatter(), defaultKind: .reminder)
    }

    @Test func explicitRelationSurvivesDecodingAndReview() throws {
        let capture = try result(#"[{"members":[0,1],"confidence":"high","evidence":"отправить заявку, чтобы попасть на этот вебинар"}]"#)
        #expect(capture.entries.map(\.linkGroup) == [0, 0])
        #expect(capture.entries.map { VoiceReviewEntry($0).linkGroup } == [0, 0])
        #expect(capture.entries[1].draft.dueDate == nil)
    }

    @Test(arguments: [
        "null", "{}", "[7]", "[]",
        #"[{"members":[0,2],"confidence":"high","evidence":"на этот вебинар"}]"#,
        #"[{"members":[0,0],"confidence":"high","evidence":"на этот вебинар"}]"#,
        #"[{"members":[0,1],"confidence":"medium","evidence":"на этот вебинар"}]"#,
        #"[{"members":[0,1],"confidence":"high","evidence":"придуманная цитата"}]"#,
        #"[{"members":[0,1],"confidence":"high","evidence":"на этот вебинар"},{"members":[0,1],"confidence":"high","evidence":"на этот вебинар"}]"#
    ])
    func malformedOrUncertainMetadataDoesNotLoseEntries(_ groups: String) throws {
        let capture = try result(groups)
        #expect(capture.entries.count == 2)
        #expect(capture.entries.allSatisfy { $0.linkGroup == nil })
    }

    @Test func oldServerAndOfflineRemainUnlinked() throws {
        #expect(try result().entries.allSatisfy { $0.linkGroup == nil })
        #expect(VoiceCaptureResult.local("Купить молоко и ещё оплатить интернет",
            now: .now, calendar: .current, defaultKind: .reminder).entries.allSatisfy { $0.linkGroup == nil })
    }

    @Test func independentGroupsAreNotMerged() throws {
        let json = #"[{"members":[0,1],"confidence":"high","evidence":"на этот вебинар"},{"members":[2,3],"confidence":"high","evidence":"на этот вебинар"}]"#
        let groups = try JSONDecoder().decode(VoiceLinkGroups.self, from: Data(json.utf8))
        #expect(groups.membership(entryCount: 4, transcript: speech) == [0: 0, 1: 0, 2: 1, 3: 1])
    }

    @Test func savedBatchUsesSharedGroupAndCancellationLeavesExistingRecords() throws {
        let container = try ModelContainer(for: Item.self, RecordLink.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let untouched = Item(title: "Существующая запись")
        context.insert(untouched)
        try context.save()
        let capture = try result(#"[{"members":[0,1],"confidence":"high","evidence":"на этот вебинар"}]"#)
        let entries = capture.entries.map { VoiceReviewEntry($0) }
        let items = try VoiceBatchPersistence.create(entries, ownerID: nil, context: context)
        let links = try context.fetch(FetchDescriptor<RecordLink>())
        let index = RecordLinkIndex(items: items + [untouched], links: links, ownerID: nil)
        #expect(index.memberIDs(for: items[0].id) == Set(items.map(\.id)))
        #expect(index.memberIDs(for: items[1].id) == Set(items.map(\.id)))
        #expect(index.count(for: untouched.id) == 0)
        try VoiceBatchPersistence.stageDeletion(items, context: context)
        try context.save()
        #expect(items.allSatisfy { $0.deletedAt != nil })
        #expect(links.allSatisfy { $0.deletedAt != nil })
        #expect(untouched.deletedAt == nil)
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 3)
    }

    @Test func removingOneOfThreeKeepsSurvivorsAndRollbackRestoresGroup() throws {
        let container = try ModelContainer(for: Item.self, RecordLink.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let capture = try result(#"[{"members":[0,1],"confidence":"high","evidence":"на этот вебинар"}]"#)
        let entries = (capture.entries + [capture.entries[1]]).map { VoiceReviewEntry($0) }
        let items = try VoiceBatchPersistence.create(entries, ownerID: "owner", context: context)
        try VoiceBatchPersistence.stageDeletion([items[0]], context: context)
        VoiceBatchPersistence.rollback(context)
        #expect(items.allSatisfy { $0.deletedAt == nil })
        try VoiceBatchPersistence.stageDeletion([items[0]], context: context)
        try context.save()
        let links = try context.fetch(FetchDescriptor<RecordLink>())
        let index = RecordLinkIndex(items: items, links: links, ownerID: "owner")
        #expect(index.memberIDs(for: items[1].id) == Set(items.dropFirst().map(\.id)))
        #expect(links.filter { $0.deletedAt == nil }.count == 1)
        #expect(links.allSatisfy { $0.ownerID == "owner" })
    }

    @Test func statisticsHaveNoInventedEmptyPercentage() {
        let empty = VoiceLabStatistics(examples: [])
        #expect(empty.total == 0)
        #expect(empty.percentage(0) == nil)
        let stats = VoiceLabStatistics(examples: [VoiceLabExample(transcript: "Купить молоко", expectedTitle: "Купить молоко")])
        #expect(stats.total == 1)
        #expect(stats.percentage(stats.exact) == 100)
    }
}
