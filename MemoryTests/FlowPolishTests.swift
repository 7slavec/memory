import Foundation
import CoreGraphics
import Testing
@testable import Memory

struct FlowPolishTests {
    @Test func panelPlacementUsesAboveBelowAndBottomWithoutClipping() {
        let panel = CGSize(width: 340, height: 416)
        let above = SchedulePanelPlacement(container: CGSize(width: 390, height: 760),
            source: CGRect(x: 240, y: 540, width: 90, height: 44), preferredSize: panel)
        #expect(!above.isBottomPanel)
        #expect(above.frame.maxY < 540)
        #expect(above.frame.minX >= 12 && above.frame.maxX <= 378)
        let below = SchedulePanelPlacement(container: CGSize(width: 390, height: 760),
            source: CGRect(x: 230, y: 80, width: 100, height: 44), preferredSize: panel)
        #expect(!below.isBottomPanel && below.frame.minY > 124)
        let bottom = SchedulePanelPlacement(container: CGSize(width: 320, height: 520),
            source: CGRect(x: 180, y: 260, width: 100, height: 44), preferredSize: panel)
        #expect(bottom.isBottomPanel)
        #expect(bottom.frame.maxY <= 508 && bottom.frame.minY >= 12)
        let landscape = SchedulePanelPlacement(container: CGSize(width: 700, height: 280),
            source: CGRect(x: 400, y: 120, width: 90, height: 44), preferredSize: panel)
        #expect(landscape.isBottomPanel && landscape.frame.height == 256)
    }

    @Test func editorMonthsAreExactlyThreeLetters() throws {
        for month in 1...12 {
            let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: month, day: 29)))
            let parts = MemoryDateFormatting.editorDate(date, relativeTo: date).split(separator: " ")
            #expect(parts.count == 2 && parts[1].count == 3)
        }
    }

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
