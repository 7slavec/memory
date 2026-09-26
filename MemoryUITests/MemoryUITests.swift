//
//  MemoryUITests.swift
//  MemoryUITests
//
//  Created by Вячеслав Храмышкин on 15.09.2026.
//

import XCTest

final class MemoryUITests: XCTestCase {

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
        XCTAssertFalse(app.staticTexts["Сегодня"].exists)
        let listScreenshot = XCTAttachment(screenshot: app.screenshot())
        listScreenshot.name = "Compact voice review"
        listScreenshot.lifetime = .keepAlways
        add(listScreenshot)

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
        title.typeText("Купить продукты для поездки")
#else
        title.typeText(" — Купить продукты для поездки")
#endif
        let editorScreenshot = XCTAttachment(screenshot: app.screenshot())
        editorScreenshot.name = "Single record editor"
        editorScreenshot.lifetime = .keepAlways
        add(editorScreenshot)
        app.buttons["Применить"].tap()
        XCTAssertTrue(app.staticTexts["2 записи"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Купить продукты для поездки")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Собрание")).firstMatch.exists)
        XCTAssertTrue(app.buttons["Сохранить"].exists)
        app.buttons["Сохранить"].tap()
        XCTAssertTrue(app.buttons["Начать голосовой ввод"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
