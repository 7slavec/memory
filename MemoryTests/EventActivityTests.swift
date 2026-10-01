import Foundation
import Testing
@testable import Memory

struct EventActivityTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func activeOnlyInsideExplicitUnfinishedEventRange() {
        let end = start.addingTimeInterval(3_600)
        #expect(!EventActivity.isActive(kind: .event, start: start, end: nil,
                                        isCompleted: false, at: start))
        #expect(!EventActivity.isActive(kind: .reminder, start: start, end: end,
                                        isCompleted: false, at: start))
        #expect(!EventActivity.isActive(kind: .event, start: start, end: end,
                                        isCompleted: false, at: start.addingTimeInterval(-1)))
        #expect(EventActivity.isActive(kind: .event, start: start, end: end,
                                       isCompleted: false, at: start))
        #expect(EventActivity.isActive(kind: .event, start: start, end: end,
                                       isCompleted: false, at: end.addingTimeInterval(-1)))
        #expect(!EventActivity.isActive(kind: .event, start: start, end: end,
                                        isCompleted: false, at: end))
        #expect(!EventActivity.isActive(kind: .event, start: start, end: end,
                                        isCompleted: true, at: start))
    }

    @Test func remainingUsesDaysHoursMinutesAndRoundsUp() {
        let now = start
        #expect(EventActivity.remaining(until: now.addingTimeInterval(1), at: now)?.display == "00:01")
        #expect(EventActivity.remaining(until: now.addingTimeInterval(2 * 86_400 + 4 * 3_600 + 3 * 60),
                                        at: now)?.display == "2:04:03")
        #expect(EventActivity.remaining(until: now, at: now) == nil)
        #expect(EventTimeRemaining(totalMinutes: 2 * 1_440 + 4 * 60 + 3).accessibilityText
                == "Осталось 2 дня 4 часа 3 минуты")
    }

    @Test func earlyFinishReplacesEndAndSurvivesRemoteApply() {
        let originalEnd = start.addingTimeInterval(7_200)
        let actualEnd = start.addingTimeInterval(1_800)
        let item = Item(title: "Встреча", dueDate: start, entryKind: .event, endDate: originalEnd)

        #expect(item.finishEvent(at: actualEnd))
        #expect(item.endDate == actualEnd)
        #expect(item.completedAt == actualEnd)
        #expect(item.isCompleted)
        #expect(!item.isActiveEvent(at: actualEnd.addingTimeInterval(-1)))
        #expect(!item.finishEvent(at: actualEnd))

        let remote = RemoteTask(item: item, userID: UUID())
        let another = Item(title: "Старая версия", dueDate: start,
                           entryKind: .event, endDate: originalEnd)
        remote.apply(to: another)
        #expect(another.isCompleted)
        #expect(another.endDate == actualEnd)
        #expect(another.completedAt == actualEnd)
    }

    @Test func changingKindResetsCompletionButSavingSameKindDoesNot() {
        let end = start.addingTimeInterval(3_600)
        let item = Item(title: "Событие", dueDate: start, entryKind: .event, endDate: end)
        #expect(item.finishEvent(at: start.addingTimeInterval(600)))
        item.entryKind = .event
        #expect(item.isCompleted)
        item.entryKind = .reminder
        #expect(!item.isCompleted)
        #expect(item.completedAt == nil)
        #expect(item.endDate == nil)
    }
}
