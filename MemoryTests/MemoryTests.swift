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
        let item = Item(title: "Купить молоко", details: "Безлактозное, 2 бутылки")

        #expect(item.title == "Купить молоко")
        #expect(item.details == "Безлактозное, 2 бутылки")
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
        #expect(item.effectiveReminderOffsets == [0])
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
        #expect(item.effectiveReminderOffsets.isEmpty)
    }

    @Test func itemKeepsMultipleReminderLeadTimes() {
        let item = Item(
            title: "Встреча",
            dueDate: Date.now.addingTimeInterval(7_200),
            reminderOffsets: [60, 15, 15]
        )

        #expect(item.notificationsEnabled)
        #expect(item.effectiveReminderOffsets == [15, 60])
    }

    @Test func remoteTaskRoundTripKeepsSyncFields() throws {
        let ownerID = UUID()
        let dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        let item = Item(
            title: "Общая проверка",
            details: "Материалы лежат в общей папке",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            dueDate: dueDate,
            notificationsEnabled: false,
            ownerID: ownerID.uuidString.lowercased(),
            updatedAt: Date(timeIntervalSince1970: 1_750_000_000)
        )

        let restored = RemoteTask(item: item, userID: ownerID).makeLocalItem()

        #expect(restored.id == item.id)
        #expect(restored.ownerID == ownerID.uuidString.lowercased())
        #expect(restored.title == item.title)
        #expect(restored.details == item.details)
        #expect(restored.dueDate == dueDate)
        #expect(!restored.notificationsEnabled)
        #expect(restored.effectiveReminderOffsets.isEmpty)
        #expect(restored.updatedAt == item.updatedAt)
    }

    @Test func remoteTaskRoundTripKeepsMultipleReminders() {
        let ownerID = UUID()
        let item = Item(
            title: "Встреча",
            dueDate: Date.now.addingTimeInterval(86_400),
            reminderOffsets: [0, 30, 1_440],
            ownerID: ownerID.uuidString.lowercased()
        )

        let restored = RemoteTask(item: item, userID: ownerID).makeLocalItem()

        #expect(restored.effectiveReminderOffsets == [0, 30, 1_440])
        #expect(restored.notificationsEnabled)
    }

    @Test func syncIgnoresSubMillisecondTimestampRoundTripDifferences() throws {
        let localDate = Date(timeIntervalSince1970: 1_750_000_000.123456)
        let remoteDate = try #require(
            SupabaseDate.date(SupabaseDate.string(localDate))
        )

        #expect(!SupabaseDate.isMeaningfullyNewer(localDate, than: remoteDate))
        #expect(!SupabaseDate.isMeaningfullyNewer(remoteDate, than: localDate))
        #expect(
            SupabaseDate.isMeaningfullyNewer(
                localDate.addingTimeInterval(1),
                than: remoteDate
            )
        )
    }

    @Test func deletedItemBecomesSyncableTombstone() {
        let item = Item(title: "Удалить после синхронизации")

        item.markDeleted()

        #expect(item.deletedAt != nil)
        #expect(item.updatedAt == item.deletedAt)
    }

    @Test func deletedRemoteItemKeepsItsTombstoneLocally() throws {
        let ownerID = UUID()
        let item = Item(
            title: "Удалено на другом устройстве",
            dueDate: Date.now.addingTimeInterval(3_600),
            ownerID: ownerID.uuidString.lowercased()
        )
        item.markDeleted()

        let remote = RemoteTask(item: item, userID: ownerID)
        let restored = remote.makeLocalItem()

        #expect(restored.deletedAt != nil)
        #expect(restored.id == item.id)
        #expect(!SupabaseDate.isMeaningfullyNewer(restored.updatedAt, than: item.updatedAt))
        #expect(!SupabaseDate.isMeaningfullyNewer(item.updatedAt, than: restored.updatedAt))
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

    @Test func smartInputUnderstandsNumericEveningTime() throws {
        let calendar = testCalendar
        let now = makeDate(2026, 9, 15, 12, 0, calendar: calendar)
        let result = try #require(
            NaturalLanguageDateParser.parse(
                "Позвонить завтра в 9 вечера",
                now: now,
                calendar: calendar
            )
        )

        #expect(result.title == "Позвонить")
        #expect(result.dueDate == makeDate(2026, 9, 16, 21, 0, calendar: calendar))
    }

    @Test func smartInputUnderstandsSpokenEveningTime() throws {
        let calendar = testCalendar
        let now = makeDate(2026, 9, 15, 12, 0, calendar: calendar)
        let result = try #require(
            NaturalLanguageDateParser.parse(
                "Лечь спать в одиннадцать вечера",
                now: now,
                calendar: calendar
            )
        )

        #expect(result.title == "Лечь спать")
        #expect(result.dueDate == makeDate(2026, 9, 15, 23, 0, calendar: calendar))
    }

    @Test func smartInputUnderstandsNightAndMorningHours() throws {
        let calendar = testCalendar
        let now = makeDate(2026, 9, 15, 12, 0, calendar: calendar)
        let night = try #require(
            NaturalLanguageDateParser.parse(
                "Проверить сервер завтра в два часа ночи",
                now: now,
                calendar: calendar
            )
        )
        let morning = try #require(
            NaturalLanguageDateParser.parse(
                "Тренировка завтра в четыре часа утра",
                now: now,
                calendar: calendar
            )
        )

        #expect(night.title == "Проверить сервер")
        #expect(night.dueDate == makeDate(2026, 9, 16, 2, 0, calendar: calendar))
        #expect(morning.title == "Тренировка")
        #expect(morning.dueDate == makeDate(2026, 9, 16, 4, 0, calendar: calendar))
    }

    @Test func smartInputKeepsMinutesWithDayPart() throws {
        let calendar = testCalendar
        let now = makeDate(2026, 9, 15, 12, 0, calendar: calendar)
        let result = try #require(
            NaturalLanguageDateParser.parse(
                "Фильм завтра в 9:30 вечера",
                now: now,
                calendar: calendar
            )
        )

        #expect(result.title == "Фильм")
        #expect(result.dueDate == makeDate(2026, 9, 16, 21, 30, calendar: calendar))
    }

    @Test func smartInputUnderstandsSpokenHourWithoutDayPart() throws {
        let calendar = testCalendar
        let now = makeDate(2026, 9, 15, 12, 0, calendar: calendar)
        let result = try #require(
            NaturalLanguageDateParser.parse(
                "Созвон в десять",
                now: now,
                calendar: calendar
            )
        )

        #expect(result.title == "Созвон")
        #expect(result.dueDate == makeDate(2026, 9, 16, 10, 0, calendar: calendar))
    }

    @Test func smartInputUnderstandsJoinedHalfHour() throws {
        let calendar = testCalendar
        let now = makeDate(2026, 9, 15, 8, 0, calendar: calendar)
        let result = try #require(
            NaturalLanguageDateParser.parse(
                "Проверить почту в полдесятого",
                now: now,
                calendar: calendar
            )
        )

        #expect(result.title == "Проверить почту")
        #expect(result.dueDate == makeDate(2026, 9, 15, 9, 30, calendar: calendar))
    }

    @Test func smartInputUnderstandsHalfHourAtNight() throws {
        let calendar = testCalendar
        let now = makeDate(2026, 9, 15, 12, 0, calendar: calendar)
        let result = try #require(
            NaturalLanguageDateParser.parse(
                "Позвонить завтра в пол одиннадцатого ночи",
                now: now,
                calendar: calendar
            )
        )

        #expect(result.title == "Позвонить")
        #expect(result.dueDate == makeDate(2026, 9, 16, 22, 30, calendar: calendar))
    }

    @Test func smartInputUnderstandsConversationalHalfHour() throws {
        let calendar = testCalendar
        let now = makeDate(2026, 9, 15, 12, 0, calendar: calendar)
        let result = try #require(
            NaturalLanguageDateParser.parse(
                "Фильм завтра пол восьмом вечером",
                now: now,
                calendar: calendar
            )
        )

        #expect(result.title == "Фильм")
        #expect(result.dueDate == makeDate(2026, 9, 16, 19, 30, calendar: calendar))
    }

    @Test func smartInputUnderstandsSpacedNumericHalfHour() throws {
        let calendar = testCalendar
        let now = makeDate(2026, 9, 15, 12, 0, calendar: calendar)
        let result = try #require(
            NaturalLanguageDateParser.parse(
                "Проверить сервер завтра в пол 1 1 ночи",
                now: now,
                calendar: calendar
            )
        )

        #expect(result.title == "Проверить сервер")
        #expect(result.dueDate == makeDate(2026, 9, 16, 22, 30, calendar: calendar))
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
