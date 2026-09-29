//
//  MemoryUITests.swift
//  MemoryUITests
//
//  Created by Вячеслав Храмышкин on 15.09.2026.
//

import XCTest
#if os(macOS)
import AppKit
#endif

final class MemoryUITests: XCTestCase {

#if os(iOS)
    @MainActor func testMobilePickerSwitchAndOrbSwipe() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-links"]
        app.launch()
        let title = app.textFields["recordEditorTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        app.switches["scheduleEnabled"].tap()
        let date = app.buttons["Начало, дата"]
        let time = app.buttons["Начало, время"]
        for _ in 0..<3 {
            date.tap()
            // Tap the other source control while its sibling panel is open.
            // The first outside tap may dismiss the popover; neither may close the editor.
            time.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(title.exists)
            time.tap()
            date.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(title.exists)
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Mobile schedule switching"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Назад"].tap()
        let orb = app.buttons["homeVoiceOrb"]
        if !orb.waitForExistence(timeout: 2), app.buttons["Назад"].exists {
            app.buttons["Назад"].tap()
        }
        XCTAssertTrue(orb.waitForExistence(timeout: 5))
        orb.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: orb.coordinate(withNormalizedOffset: CGVector(dx: 1.1, dy: 0.5)))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Входящие")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0, "A swipe must not request microphone access")
    }
#endif

    @MainActor func testFlowContextPanelsKeepEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-links"]
        app.launch()
        ensureWindow(app)
        let title = app.textFields["recordEditorTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "Назад").count, 1)
        app.switches["scheduleEnabled"].tap()
        XCTAssertTrue(app.buttons["Начало, дата"].waitForExistence(timeout: 5))
        app.buttons["Начало, дата"].tap()
#if os(macOS)
        XCTAssertFalse(app.buttons["Готово"].exists)
        app.typeKey(.escape, modifierFlags: [])
#else
        title.tap()
#endif
        XCTAssertTrue(title.exists)
        app.buttons["openRecordLinks"].tap()
        XCTAssertTrue(app.textFields["linkSearch"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["addRecordLink"].exists)
        XCTAssertFalse(app.buttons["Закрыть связи"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Flow contextual links"; screenshot.lifetime = .keepAlways; add(screenshot)
#if os(macOS)
        app.typeKey(.escape, modifierFlags: [])
#else
        title.tap()
#endif
        XCTAssertTrue(title.exists)
        XCTAssertEqual(app.buttons.matching(identifier: "Назад").count, 1)
    }

#if os(macOS)
    @MainActor private func pasteTestTitle(_ text: String, into field: XCUIElement) {
        let board = NSPasteboard.general
        var saved: [NSPasteboardItem] = []
        for item in board.pasteboardItems ?? [] {
            let restored = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { restored.setData(data, forType: type) }
            }
            saved.append(restored)
        }
        defer {
            board.clearContents()
            _ = board.writeObjects(saved)
        }
        board.clearContents()
        board.setString(text, forType: .string)
        field.typeKey("v", modifierFlags: .command)
    }
#endif

    @MainActor func testVoiceReviewAppliesEditedTitle() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-voice-review"]
        app.launch()
        ensureWindow(app)
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Сходить за покупками")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let title = app.textFields["recordEditorTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
#if os(macOS)
        title.typeKey("a", modifierFlags: .command)
        pasteTestTitle("Updated capture", into: title)
#else
        title.typeText(" Updated capture")
#endif
        XCTAssertTrue((title.value as? String)?.contains("Updated capture") == true)
        app.buttons["Применить"].tap()
        XCTAssertTrue(app.staticTexts["2 записи"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Updated capture")).firstMatch.exists)
    }

    @MainActor func testManualLinksUseOneEditorAndUnlinkKeepsRecords() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-links"]
        app.launch()
        ensureWindow(app)
        XCTAssertTrue(app.buttons["openRecordLinks"].waitForExistence(timeout: 10))
        app.buttons["openRecordLinks"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "Назад").count, 1)
        XCTAssertTrue(app.textFields["linkSearch"].waitForExistence(timeout: 5))
        let webinar = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Вебинар по дизайну")).firstMatch
        XCTAssertTrue(webinar.waitForExistence(timeout: 5))
        webinar.tap()
        XCTAssertTrue(app.buttons["addRecordLink"].waitForExistence(timeout: 5))
        app.buttons["addRecordLink"].tap()
        let materials = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Прочитать материалы")).firstMatch
        XCTAssertTrue(materials.waitForExistence(timeout: 5))
        materials.tap()
        webinar.tap()
        XCTAssertTrue(app.buttons["openRecordLinks"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "Назад").count, 1)
        app.buttons["openRecordLinks"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Отправить заявку")).firstMatch.exists)
        XCTAssertTrue(materials.exists)
        XCTAssertTrue(webinar.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Shared group includes current record"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Исключить из связи: Вебинар по дизайну"].tap()
        XCTAssertTrue(materials.waitForExistence(timeout: 5))
        XCTAssertFalse(webinar.exists)
        app.buttons["Разорвать"].tap()
        XCTAssertFalse(app.buttons["addRecordLink"].waitForExistence(timeout: 1))
        app.buttons["openRecordLinks"].tap()
        XCTAssertTrue(materials.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Отправить заявку")).firstMatch.exists)
        dismissLinkPopup(app)
        let title = app.textFields["recordEditorTitle"]
        title.tap()
        title.typeText(" — черновик")
        app.buttons["openRecordLinks"].tap()
        dismissLinkPopup(app)
        XCTAssertTrue((title.value as? String)?.contains("черновик") == true)
    }

    @MainActor func testEditorStaysOpenWhenSaveFails() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-links", "--uitest-save-failure"]
        app.launch()
        ensureWindow(app)
        XCTAssertTrue(app.buttons["openRecordLinks"].waitForExistence(timeout: 10))
        let title = app.textFields["recordEditorTitle"]
        title.tap()
#if os(macOS)
        title.typeKey("a", modifierFlags: .command)
        title.typeText("Сохранить мой черновик")
#else
        title.typeText(" — Сохранить мой черновик")
#endif
        let save = app.buttons["Назад"]
        save.tap()
        XCTAssertTrue(app.staticTexts["Не удалось сохранить"].waitForExistence(timeout: 5))
#if os(macOS)
        app.sheets.buttons["ОК"].tap()
#else
        app.alerts.buttons["ОК"].tap()
#endif
        XCTAssertTrue(app.buttons["openRecordLinks"].exists)
        XCTAssertTrue((title.value as? String)?.contains("Сохранить мой черновик") == true)
        XCTAssertEqual(app.buttons.matching(identifier: "Назад").count, 1)
    }

    @MainActor private func dismissLinkPopup(_ app: XCUIApplication) {
#if os(macOS)
        app.typeKey(.escape, modifierFlags: [])
#else
        app.textFields["recordEditorTitle"].tap()
#endif
    }

    @MainActor private func ensureWindow(_ app: XCUIApplication) {
#if os(macOS)
        if !app.windows.firstMatch.waitForExistence(timeout: 2) {
            app.typeKey("n", modifierFlags: .command)
            XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        }
#endif
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testVoiceReviewUsesOnePageAndReturnsFromEachRecord() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-voice-review"]
        app.launch()
#if os(macOS)
        if !app.windows.firstMatch.waitForExistence(timeout: 2) {
            app.menuBars.menuBarItems["File"].click()
            app.menuBars.menuItems["New Window"].click()
        }
#endif

        XCTAssertTrue(app.staticTexts["2 записи"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Требует внимания"].exists)
        let listScreenshot = XCTAttachment(screenshot: app.screenshot())
        listScreenshot.name = "Compact voice review"
        listScreenshot.lifetime = .keepAlways
        add(listScreenshot)

        let links = app.buttons["Связанные записи: 2"].firstMatch
        XCTAssertTrue(links.exists)
        links.tap()
        XCTAssertTrue(app.buttons["addRecordLink"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Сходить за покупками")).firstMatch.tap()
        XCTAssertTrue(app.buttons["openRecordLinks"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "Назад").count, 1)
        app.buttons["openRecordLinks"].tap()
        app.buttons["Разорвать"].tap()
        XCTAssertFalse(app.buttons["addRecordLink"].waitForExistence(timeout: 1))
        app.buttons["Назад"].tap()
        XCTAssertTrue(app.staticTexts["2 записи"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Связанные записи: 2"].exists)

        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Собрание")).firstMatch
        XCTAssertTrue(first.exists)
        first.tap()
        XCTAssertTrue(app.buttons["Назад"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["2 записи"].exists)
#if os(iOS)
        XCTAssertFalse(app.images["NorkaLogo"].exists)
#endif
        app.buttons["Назад"].tap()
        XCTAssertTrue(app.staticTexts["2 записи"].waitForExistence(timeout: 5))

        let second = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Сходить за покупками")).firstMatch
        second.tap()
        let title = app.textFields.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
#if os(macOS)
        title.typeKey("a", modifierFlags: .command)
        pasteTestTitle("Updated capture", into: title)
#else
        title.typeText(" Updated capture")
#endif
        let editorScreenshot = XCTAttachment(screenshot: app.screenshot())
        editorScreenshot.name = "Single record editor"
        editorScreenshot.lifetime = .keepAlways
        add(editorScreenshot)
        app.buttons["Применить"].tap()
        XCTAssertTrue(app.staticTexts["2 записи"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Updated capture")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Собрание")).firstMatch.exists)
        XCTAssertTrue(app.buttons["Сохранить"].exists)
        app.buttons["Сохранить"].tap()
        XCTAssertTrue(app.buttons["Начать голосовой ввод"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDesignCatalogScheduleIsLocalAndExplicit() throws {
#if os(macOS)
        let app = XCUIApplication()
        app.launchArguments = ["--design-catalog"]
        app.launch()
        if !app.windows.firstMatch.waitForExistence(timeout: 2) {
            app.menuBars.menuBarItems["File"].click()
            app.menuBars.menuItems["New Window"].click()
        }
        XCTAssertTrue(app.staticTexts["catalog-title"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Начать голосовой ввод"].exists)
        let records = XCTAttachment(screenshot: app.screenshot())
        records.name = "Catalog records — two themes"
        records.lifetime = .keepAlways
        add(records)

        // Each theme owns an independent sample. Scope interaction to one board.
        app.radioButtons["Светлая"].click()
        app.popUpButtons["catalog-section"].click()
        app.menuItems["Дата и время"].click()
        let timeChip = app.buttons["catalog-open-time"].firstMatch
        XCTAssertTrue(timeChip.waitForExistence(timeout: 5))
        timeChip.click()
        var field = app.popovers.textFields["Время"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeKey(.rightArrow, modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: .command)
        XCTAssertEqual(field.value as? String, "")
        field.typeText("25:00")
        app.popovers.buttons["Готово"].click()
        XCTAssertTrue(app.popovers.staticTexts["Введите время от 00:00 до 23:59"].exists)
        field.click()
        field.typeKey(.rightArrow, modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: .command)
        XCTAssertEqual(field.value as? String, "")
        field.typeText("14:30")
        XCTAssertEqual(field.value as? String, "14:30")
        app.popovers.buttons["Готово"].click()
        let applied = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "14:30"), object: timeChip)
        XCTAssertEqual(XCTWaiter.wait(for: [applied], timeout: 3), .completed)

        timeChip.click()
        field = app.popovers.textFields["Время"].firstMatch
        field.click()
        field.typeKey(.rightArrow, modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: .command)
        XCTAssertEqual(field.value as? String, "")
        field.typeText("20:20")
        field.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(timeChip.label, "14:30")

        app.buttons["catalog-open-date"].firstMatch.click()
        let nextDay = app.popovers.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "28 сентября")).firstMatch
        XCTAssertTrue(nextDay.waitForExistence(timeout: 5))
        nextDay.click()
        XCTAssertTrue(app.buttons["catalog-open-date"].firstMatch.label.hasPrefix("28"))
        XCTAssertEqual(timeChip.label, "14:30")
        let schedule = XCTAttachment(screenshot: app.screenshot())
        schedule.name = "Catalog schedule — native controls"
        schedule.lifetime = .keepAlways
        add(schedule)
#else
        throw XCTSkip("Mac catalog interaction test; iPhone picker needs its own device scenario")
#endif
    }

    @MainActor
    func testCatalogFieldsKeepGeometryAndCustomChoiceWorks() throws {
#if os(macOS)
        let app = XCUIApplication()
        app.launchArguments = ["--design-catalog"]
        app.launch()
        if !app.windows.firstMatch.waitForExistence(timeout: 2) {
            app.menuBars.menuBarItems["File"].click()
            app.menuBars.menuItems["New Window"].click()
        }
        XCTAssertTrue(app.staticTexts["catalog-title"].waitForExistence(timeout: 10))
        app.radioButtons["Светлая"].click()
        app.popUpButtons["catalog-section"].click()
        app.menuItems["Ввод"].click()

        let search = app.textFields["catalog-search"].firstMatch
        let box = app.descendants(matching: .any).matching(identifier: "catalog-search-container").firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(box.exists)
        let initial = box.frame
        let send = app.buttons["catalog-send"].firstMatch
        let expand = app.buttons["catalog-expand"].firstMatch
        XCTAssertEqual(send.frame.width, expand.frame.width, accuracy: 0.5)
        XCTAssertEqual(send.frame.height, expand.frame.height, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(send.frame.width, 48)
        XCTAssertFalse(send.isEnabled)

        search.click()
        search.typeText("Очень длинный поисковый запрос для проверки стабильного размера поля")
        XCTAssertEqual(box.frame.height, initial.height, accuracy: 0.5)
        XCTAssertEqual(box.frame.width, initial.width, accuracy: 0.5)
        app.buttons["Очистить поиск"].click()
        XCTAssertEqual(search.value as? String, "")
        XCTAssertEqual(box.frame.height, initial.height, accuracy: 0.5)
        XCTAssertEqual(box.frame.width, initial.width, accuracy: 0.5)

        app.popUpButtons["catalog-section"].click()
        app.menuItems["Элементы"].click()
        let choice = app.buttons["catalog-reminder-choice"].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        if !choice.isHittable { app.scrollViews.firstMatch.swipeUp() }
        choice.click()
        XCTAssertTrue(app.popovers.buttons["За час"].waitForExistence(timeout: 5))
        app.popovers.buttons["За час"].click()
        XCTAssertEqual(choice.value as? String, "За час")
        choice.click()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(choice.value as? String, "За час")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Catalog controls revision 02"
        screenshot.lifetime = .keepAlways
        add(screenshot)
#else
        throw XCTSkip("Mac layout regression; physical iPhone keyboard testing is separate")
#endif
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
