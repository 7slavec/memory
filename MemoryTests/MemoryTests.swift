//
//  MemoryTests.swift
//  MemoryTests
//
//  Created by Вячеслав Храмышкин on 15.09.2026.
//

import Foundation
import SwiftData
import Testing
@testable import Memory

struct MemoryTests {

    @Test func newItemKeepsItsContentAndState() {
        let item = Item(title: "Купить молоко")

        #expect(item.title == "Купить молоко")
        #expect(item.isCompleted == false)

        item.isCompleted.toggle()

        #expect(item.isCompleted == true)
    }

    @Test func itemCanBeSavedAndFetched() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Item.self, configurations: configuration)
        let context = ModelContext(container)

        context.insert(Item(title: "Записать идею"))
        try context.save()

        let savedItems = try context.fetch(FetchDescriptor<Item>())

        #expect(savedItems.count == 1)
        #expect(savedItems.first?.title == "Записать идею")
    }

    @Test func itemStoresReminderAndCompletionDate() {
        let reminderDate = Date.now.addingTimeInterval(3600)
        let item = Item(title: "Позвонить", dueDate: reminderDate)
        #expect(item.dueDate == reminderDate)
        #expect(item.notificationsEnabled)
        #expect(item.completedAt == nil)
        item.setCompleted(true)
        #expect(item.isCompleted)
        #expect(item.completedAt != nil)
        item.setCompleted(false)
        #expect(!item.isCompleted)
        #expect(item.completedAt == nil)
    }

    @Test func scheduledItemCanStaySilent() {
        let scheduledDate = Date.now.addingTimeInterval(7200)
        let item = Item(
            title: "Посмотреть запись",
            dueDate: scheduledDate,
            notificationsEnabled: false
        )

        #expect(item.dueDate == scheduledDate)
        #expect(!item.notificationsEnabled)
    }

    @Test func smartInputUnderstandsTomorrowAndTime() throws {
        let calendar = testCalendar
        let now = makeDate(2026, 9, 15, 12, 0, calendar: calendar)
        let result = try #require(
            NaturalLanguageDateParser.parse(
                "Позвонить маме завтра в 10:30",
                now: now,
                calendar: calendar
            )
        )

        #expect(result.title == "Позвонить маме")
        #expect(result.dueDate == makeDate(2026, 9, 16, 10, 30, calendar: calendar))
    }

    @Test func smartInputUnderstandsRelativeTime() throws {
        let calendar = testCalendar
        let now = makeDate(2026, 9, 15, 12, 0, calendar: calendar)
        let result = try #require(
            NaturalLanguageDateParser.parse(
                "Проверить духовку через 20 минут",
                now: now,
                calendar: calendar
            )
        )

        #expect(result.title == "Проверить духовку")
        #expect(result.dueDate == makeDate(2026, 9, 15, 12, 20, calendar: calendar))
    }

    @Test func smartInputUnderstandsWeekdayAndDayPart() throws {
        let calendar = testCalendar
        let now = makeDate(2026, 9, 15, 12, 0, calendar: calendar)
        let result = try #require(
            NaturalLanguageDateParser.parse(
                "Посмотреть фильм в пятницу вечером",
                now: now,
                calendar: calendar
            )
        )

        #expect(result.title == "Посмотреть фильм")
        #expect(result.dueDate == makeDate(2026, 9, 18, 19, 0, calendar: calendar))
    }

    @Test func smartInputMovesPastStandaloneTimeToTomorrow() throws {
        let calendar = testCalendar
        let now = makeDate(2026, 9, 15, 12, 0, calendar: calendar)
        let result = try #require(
            NaturalLanguageDateParser.parse(
                "Отправить отчёт в 10:00",
                now: now,
                calendar: calendar
            )
        )

        #expect(result.title == "Отправить отчёт")
        #expect(result.dueDate == makeDate(2026, 9, 16, 10, 0, calendar: calendar))
    }

    @Test func smartInputIgnoresTextWithoutDate() {
        let calendar = testCalendar
        let now = makeDate(2026, 9, 15, 12, 0, calendar: calendar)
        let result = NaturalLanguageDateParser.parse(
            "Записать хорошую идею",
            now: now,
            calendar: calendar
        )

        #expect(result == nil)
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Samara")!
        return calendar
    }

    private func makeDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

}
