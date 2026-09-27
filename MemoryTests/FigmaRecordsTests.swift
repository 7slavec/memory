import SwiftUI
import Testing
@testable import Memory
#if os(macOS)
import AppKit
#endif

struct FigmaRecordsTests {
    @Test func iconSlotsAndTokens() {
        #expect(FigmaRecordsTokens.cardInset == 16)
        #expect(FigmaRecordsTokens.cardRadius == 20)
        #expect(FigmaRecordSchedule(text: "Без срока", tone: .muted).asset == "FigmaNoDate")
        #expect(FigmaRecordSchedule(text: "Завтра", tone: .event).asset == "FigmaClock")
        #expect(FigmaRecordSchedule(text: "Завтра", tone: .reminder).asset == "FigmaBell")
    }

#if os(macOS)
    @MainActor @Test func renderFigmaRecordStates() throws {
        _ = FigmaRecordsTokens.font(16)
        _ = FigmaRecordsTokens.brandFont
        #expect(NSFont(name: "Inter-Regular", size: 16) != nil)
        #expect(NSFont(name: "InstrumentSans-Regular", size: 32) != nil)
        for name in ["FigmaList", "FigmaProfile", "FigmaInbox", "FigmaBell", "FigmaClock", "FigmaNoDate"] {
            #expect(NSImage(named: name) != nil, "Missing Figma asset: \(name)")
        }
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("NorkaFigmaRecords")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for dark in [false, true] {
            for width in [320, 393, 652] {
                for largeText in [false, true] {
                    let board = VStack(alignment: .leading, spacing: 8) {
                        FigmaRecordCard(title: "Отправить портфолио", details: "Добавить последние проекты", isEvent: false, isCompleted: false,
                                        schedule: .init(text: "Завтра в 16:00", tone: .reminder), onEdit: {}, onToggle: {})
                        FigmaRecordCard(title: "Собрание по маркетингу с Тимуром и Натальей в офисе", details: "Подготовить недельный отчет к собранию", isEvent: true, isCompleted: false,
                                        schedule: .init(text: "29 сен. с 16:00 по 18:00", tone: .event), onEdit: {})
                        FigmaRecordCard(title: "Подумать над идеей подарка", details: nil, isEvent: false, isCompleted: false,
                                        schedule: .init(text: "Без срока", tone: .muted), onEdit: {}, onToggle: {})
                    }
                    .padding(16)
                    .frame(width: CGFloat(width))
                    .background(FigmaRecordsTokens.background)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .environment(\.dynamicTypeSize, largeText ? .accessibility1 : .large)
                    let renderer = ImageRenderer(content: board)
                    renderer.scale = 2
                    let cg = try #require(renderer.cgImage)
                    #expect(cg.width == width * 2)
                    let png = try #require(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
                    try png.write(to: folder.appendingPathComponent("cards-\(dark ? "dark" : "light")-\(width)-\(largeText ? "large" : "normal").png"))
                }
            }
        }
        print("Figma records visual review: \(folder.path)")
    }
#endif
}
