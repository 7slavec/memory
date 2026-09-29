import Foundation
import Testing
@testable import Memory

struct FlowPolishTests {
    @Test(arguments: [2024, 2026, 2027])
    func calendarKeepsSixWeeksAndAllDays(_ year: Int) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 14_400)!
        calendar.firstWeekday = 2
        for month in 1...12 {
            let start = try #require(calendar.date(from: DateComponents(year: year, month: month, day: 1)))
            let slots = MemoryCalendarGrid.slots(for: start, calendar: calendar)
            let dates = slots.compactMap(\.date)
            #expect(slots.count == 42)
            #expect(Set(slots.map(\.id)).count == 42)
            #expect(calendar.component(.weekday, from: slots[0].id) == 2)
            #expect(dates.count == calendar.range(of: .day, in: .month, for: start)?.count)
            #expect(dates.first == start)
            #expect(dates.allSatisfy { calendar.component(.month, from: $0) == month })
        }
    }

    @Test func cachedFormattingKeepsRussianOutputAndYearRule() throws {
        let calendar = Calendar.current
        let date = try #require(calendar.date(from: DateComponents(year: 2027, month: 2, day: 3, hour: 9, minute: 5)))
        let reference = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 29)))
        for _ in 0..<3 {
            #expect(MemoryDateFormatting.time(date) == "09:05")
            #expect(MemoryDateFormatting.editorDate(date, relativeTo: reference).contains("2027"))
            #expect(!MemoryDateFormatting.editorDate(date, relativeTo: date).contains("2027"))
            #expect(MemoryDateFormatting.fullDate(date).contains("февраля"))
        }
    }
}
