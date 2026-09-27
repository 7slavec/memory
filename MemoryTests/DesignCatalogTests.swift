#if DEBUG
import Foundation
import SwiftUI
import Testing
@testable import Memory
#if os(macOS)
import AppKit
#endif

struct DesignCatalogTests {
    @Test(arguments: [false, true]) func proposedTextContrast(dark: Bool) {
        let p = CatalogPalette(dark: dark)
        let pairs: [(String, CatalogRGB, CatalogRGB)] = [
            ("Body/background", p.text, p.background), ("Body/surface", p.text, p.surface),
            ("Secondary/background", p.secondary, p.background), ("Secondary/surface", p.secondary, p.surface),
            ("Disabled/inset", p.secondary, p.inset), ("Accent/background", p.accent, p.background),
            ("Accent/chip", p.accent, p.accentSurface), ("Schedule/event", p.accent, p.eventSurface),
            ("Event/chip", p.event, p.eventSurface), ("Danger/chip", p.danger, p.dangerSurface),
            ("Primary/button", p.onPrimary, p.primaryFill)
        ]
        for (name, text, background) in pairs {
            #expect(text.contrast(on: background) >= 4.5, "\(name), dark=\(dark)")
        }
    }

    @Test func calendarMonthsAndIdentity() throws {
        let calendar = CatalogScheduleModel.calendar
        for year in [2024, 2025, 2026, 2027] {
            for month in 1...12 {
                let start = try #require(calendar.date(from: DateComponents(year: year, month: month, day: 1)))
                let cells = CatalogScheduleModel.cells(for: start)
                #expect(cells.count == 42)
                #expect(Set(cells.map(\.id)).count == 42)
                let dates = cells.compactMap(\.date)
                #expect(dates.count == calendar.range(of: .day, in: .month, for: start)?.count)
                #expect(dates.allSatisfy { calendar.component(.month, from: $0) == month })
                #expect(cells.firstIndex(where: { $0.date != nil }) == (calendar.component(.weekday, from: start) + 5) % 7)
            }
        }
    }

    @Test func changingDayPreservesTime() throws {
        let calendar = CatalogScheduleModel.calendar
        let selection = try #require(CatalogScheduleModel.time("23:45", on: CatalogScheduleModel.exampleDate))
        let day = try #require(calendar.date(from: DateComponents(year: 2027, month: 2, day: 15)))
        let result = CatalogScheduleModel.replacingDay(day, in: selection)
        #expect(calendar.isDate(result, inSameDayAs: day))
        #expect(calendar.component(.hour, from: result) == 23)
        #expect(calendar.component(.minute, from: result) == 45)
    }

    @Test func timeValidationAndDayPreservation() throws {
        let day = CatalogScheduleModel.exampleDate
        for valid in ["00:00", "23:59", "9:05", " 14:30 "] {
            let parsed = try #require(CatalogScheduleModel.time(valid, on: day))
            #expect(CatalogScheduleModel.calendar.isDate(day, inSameDayAs: parsed))
        }
        for invalid in ["", "24:00", "12:60", "-1:30", "12", "12:", ":30", "12:00:00", "утром"] {
            #expect(CatalogScheduleModel.time(invalid, on: day) == nil)
        }
        #expect(CatalogControlSize.allCases.allSatisfy { $0.hit >= 44 })
    }

#if os(macOS)
    // Review artifacts, not golden-image assertions or a substitute for iPhone testing.
    @MainActor @Test func renderCatalogBoards() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NorkaDesignCatalog", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // ImageRenderer cannot capture AppKit-backed TextField/Menu/Toggle.
        // Those sections are checked in the live catalog, not exported as misleading placeholders.
        for section in [CatalogSection.foundations, .records] {
            let name = section == .foundations ? "foundations" : "records"
            for dark in [false, true] {
                for width in [390, 620] {
                    let renderer = ImageRenderer(content: CatalogBoard(section: section)
                        .environment(\.colorScheme, dark ? .dark : .light)
                        .frame(width: CGFloat(width)).fixedSize(horizontal: false, vertical: true))
                    renderer.scale = 2
                    let cgImage = try #require(renderer.cgImage)
                    #expect(cgImage.width == width * 2)
                    let data = try #require(NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
                    try data.write(to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light")-\(width).png"))
                }
            }
        }
        print("Catalog review images: \(directory.path)")
    }
#endif
}
#endif
