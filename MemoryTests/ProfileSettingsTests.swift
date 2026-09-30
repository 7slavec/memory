import Foundation
import SwiftData
import Testing
@testable import Memory

@MainActor
struct ProfileSettingsTests {
    @Test func avatarOptionsRoundTripAndUnknownMetadataUsesSafeDefaults() throws {
        #expect(ProfileAnimal.allCases.count == 3)
        #expect(ProfileTint.allCases.count == 6)
        for animal in ProfileAnimal.allCases {
            for tint in ProfileTint.allCases {
                let value = ProfilePersonalization(avatar: ProfileAvatar(animal: animal, tint: tint), eventReminderMinutes: 60)
                #expect(try JSONDecoder().decode(ProfilePersonalization.self, from: JSONEncoder().encode(value)) == value)
            }
        }
        #expect(ProfileAvatar(animal: "unknown", tint: nil) == .standard)
        #expect(ProfileAvatar(animal: "dog", tint: "unknown") == ProfileAvatar(animal: .dog))
    }

    @Test func eventAndReminderDefaultsAreIndependentAfterMigration() {
        let legacy = ProfilePersonalization()
        #expect(legacy.reminderMinutes(for: .event, fallback: 60) == 60)
        let split = ProfilePersonalization(eventReminderMinutes: 60)
        #expect(split.reminderMinutes(for: .event, fallback: 15) == 60)
        #expect(split.reminderMinutes(for: .reminder, fallback: 15) == 15)
        #expect(ProfilePersonalization(eventReminderMinutes: -999).reminderMinutes(for: .event, fallback: 15) == 15)
    }

    @Test func legacyAvatarKeepsItsSelectionAndRepeatedTapCyclesOnlyFur() throws {
        let legacy = Data(#"{"animal":"rabbit","tint":"mint"}"#.utf8)
        var avatar = try JSONDecoder().decode(ProfileAvatar.self, from: legacy)
        #expect(avatar == ProfileAvatar(animal: .rabbit, tint: .mint))
        for expected in [ProfileFur.cocoa, .cream, .ink] {
            avatar.select(.rabbit)
            #expect(avatar.fur == expected)
            #expect(avatar.tint == .mint)
            #expect(try JSONDecoder().decode(ProfileAvatar.self, from: JSONEncoder().encode(avatar)) == avatar)
        }
        avatar.select(.cat)
        #expect(avatar.animal == .cat && avatar.fur == .ink)
    }

    @Test func clearArchiveRevalidatesOwnerAndStateWithoutPhysicallyDeletingRecords() throws {
        let container = try ModelContainer(for: Item.self, RecordLink.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let now = Date.now
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let finished = Item(title: "Finished", isCompleted: true)
        let pastEvent = Item(title: "Past", dueDate: yesterday, entryKind: .event)
        let overdueReminder = Item(title: "Overdue", dueDate: yesterday)
        let todayEvent = Item(title: "Today", dueDate: now, entryKind: .event)
        let foreign = Item(title: "Foreign", isCompleted: true, ownerID: "another-account")
        let restored = Item(title: "Restored", isCompleted: true)
        let newArchive = Item(title: "Not in confirmation", isCompleted: true)
        let items = [finished, pastEvent, overdueReminder, todayEvent, foreign, restored, newArchive]
        for item in items { context.insert(item) }
        try context.save()
        let snapshot = Set(items.dropLast().map(\.id))
        restored.setCompleted(false)
        try context.save()
        let cleared = try ArchiveDeletion.clear(ids: snapshot, ownerID: nil, context: context, now: now)
        #expect(Set(cleared) == [finished.id, pastEvent.id])
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == items.count)
        #expect(items.dropFirst(2).allSatisfy { $0.deletedAt == nil })
    }

    @Test func archiveClearKeepsActiveMembersConnected() throws {
        let container = try ModelContainer(for: Item.self, RecordLink.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let items = (0..<3).map { Item(title: "Linked \($0)") }
        for item in items { context.insert(item) }
        try context.save()
        try RecordLinkService.setLinked(true, first: items[0], second: items[1], ownerID: nil, context: context)
        try RecordLinkService.setLinked(true, first: items[1], second: items[2], ownerID: nil, context: context)
        items[1].setCompleted(true)
        try context.save()
        _ = try ArchiveDeletion.clear(ids: [items[1].id], ownerID: nil, context: context)
        let index = RecordLinkIndex(items: items, links: try context.fetch(FetchDescriptor<RecordLink>()), ownerID: nil)
        #expect(index.memberIDs(for: items[0].id) == [items[0].id, items[2].id])
        #expect(items[0].deletedAt == nil && items[2].deletedAt == nil)
    }
}
