//
//  MemoryTests.swift
//  MemoryTests
//
//  Created by Вячеслав Храмышкин on 15.09.2026.
//

import Foundation
import SwiftData
import Testing
import UserNotifications
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

    @Test func notificationContentUsesReminderHierarchy() {
        let id = UUID()
        let dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        let content = ReminderScheduler.notificationContent(
            id: id,
            title: "  Отправить резюме  ",
            details: "Добавить   ссылку на портфолио",
            dueDate: dueDate,
            offset: ReminderLeadTime.fifteenMinutes.rawValue
        )

        #expect(content.title == "Отправить резюме")
        #expect(content.subtitle.hasPrefix("Через 15 минут"))
        #expect(content.body == "Добавить ссылку на портфолио")
        #expect(content.threadIdentifier == "norka.reminders")
        #expect(content.userInfo["itemID"] as? String == id.uuidString)
    }

    @Test func notificationWithoutDetailsStaysCompact() {
        let content = ReminderScheduler.notificationContent(
            id: UUID(),
            title: "Позвонить маме",
            details: nil,
            dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            offset: ReminderLeadTime.atTime.rawValue
        )

        #expect(content.title == "Позвонить маме")
        #expect(content.subtitle.hasPrefix("Сейчас"))
        #expect(content.body.isEmpty)
    }

    @Test func nearTermReminderFallsBackToDueTime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let dueDate = now.addingTimeInterval(2 * 60)

        let offsets = ReminderScheduler.deliverableOffsets(
            dueDate: dueDate,
            requestedOffsets: [ReminderLeadTime.oneHour.rawValue],
            now: now
        )

        #expect(offsets == [ReminderLeadTime.atTime.rawValue])
    }

    @Test func schedulerKeepsFutureLeadTimesAndDropsExpiredOnes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let dueDate = now.addingTimeInterval(30 * 60)

        let offsets = ReminderScheduler.deliverableOffsets(
            dueDate: dueDate,
            requestedOffsets: [
                ReminderLeadTime.oneHour.rawValue,
                ReminderLeadTime.fifteenMinutes.rawValue
            ],
            now: now
        )

        #expect(offsets == [ReminderLeadTime.fifteenMinutes.rawValue])
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

    @Test func eventCanKeepOnlyItsRequiredStart() {
        let start = Date.now.addingTimeInterval(7_200)
        let item = Item(
            title: "Вебинар",
            dueDate: start,
            entryKind: .event,
            endDate: nil
        )

        #expect(item.isEvent)
        #expect(item.dueDate == start)
        #expect(item.endDate == nil)

        item.setCompleted(true)

        #expect(!item.isCompleted)
        #expect(item.completedAt == nil)
    }

    @MainActor
    @Test func allItemsWeekEndsAtMondayForRemindersAndEvents() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = 1 // Verify the app uses Monday even with a Sunday-first device calendar.

        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) throws -> Date {
            try #require(calendar.date(from: DateComponents(
                year: year, month: month, day: day, hour: hour
            )))
        }

        let now = try date(2026, 9, 23)
        let thisSunday = try date(2026, 9, 27)
        let nextMonday = try date(2026, 9, 28)

        #expect(AllItemsGroup.group(
            for: Item(title: "Позвонить", dueDate: thisSunday), now: now, using: calendar
        ) == .week)
        #expect(AllItemsGroup.group(
            for: Item(title: "Вебинар", dueDate: thisSunday, entryKind: .event),
            now: now, using: calendar
        ) == .week)
        #expect(AllItemsGroup.group(
            for: Item(title: "Позвонить", dueDate: nextMonday), now: now, using: calendar
        ) == .later)
        #expect(AllItemsGroup.group(
            for: Item(title: "Вебинар", dueDate: nextMonday, entryKind: .event),
            now: now, using: calendar
        ) == .later)

        let newYearWeekday = try date(2026, 12, 30)
        #expect(AllItemsGroup.group(
            for: Item(title: "План", dueDate: try date(2027, 1, 3)),
            now: newYearWeekday, using: calendar
        ) == .week)
        #expect(AllItemsGroup.group(
            for: Item(title: "Встреча", dueDate: try date(2027, 1, 4), entryKind: .event),
            now: newYearWeekday, using: calendar
        ) == .later)

        // Tomorrow has priority even when Sunday is followed by a new week.
        #expect(AllItemsGroup.group(
            for: Item(title: "Встреча", dueDate: nextMonday, entryKind: .event),
            now: thisSunday, using: calendar
        ) == .tomorrow)
        #expect(AllItemsGroup.group(
            for: Item(title: "Позвонить", dueDate: nextMonday),
            now: thisSunday, using: calendar
        ) == .tomorrow)
    }

    @Test func eventWithoutEndSurvivesRemoteRoundTrip() {
        let ownerID = UUID()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let item = Item(
            title: "Встреча",
            dueDate: start,
            entryKind: .event,
            endDate: nil,
            ownerID: ownerID.uuidString.lowercased()
        )

        let restored = RemoteTask(item: item, userID: ownerID).makeLocalItem()

        #expect(restored.entryKind == .event)
        #expect(restored.dueDate == start)
        #expect(restored.endDate == nil)
        #expect(!restored.isCompleted)
    }

    @Test func entryKindInferenceRecognizesEventNouns() {
        #expect(
            EntryKindInference.infer(
                from: "Вебинар по дизайну завтра в 19:00",
                hasDate: true
            ) == .event
        )
        #expect(
            EntryKindInference.infer(
                from: "День рождения Кати",
                hasDate: false
            ) == .event
        )
        #expect(
            EntryKindInference.infer(
                from: "Встретиться с Машей в пятницу",
                hasDate: true
            ) == .event
        )
    }

    @Test func entryKindInferencePrioritizesActions() {
        #expect(
            EntryKindInference.infer(
                from: "Купить билет на концерт завтра",
                hasDate: true
            ) == .reminder
        )
        #expect(
            EntryKindInference.infer(
                from: "Не забыть подготовить материалы к вебинару",
                hasDate: false
            ) == .reminder
        )
    }

    @Test func editorDateOmitsCurrentYearAndKeepsFutureYear() {
        let calendar = testCalendar
        let reference = makeDate(2026, 9, 23, 12, 0, calendar: calendar)
        let sameYear = makeDate(2026, 10, 4, 9, 0, calendar: calendar)
        let nextYear = makeDate(2027, 1, 5, 9, 0, calendar: calendar)

        let sameYearLabel = MemoryDateFormatting.editorDate(sameYear, relativeTo: reference)
        let nextYearLabel = MemoryDateFormatting.editorDate(nextYear, relativeTo: reference)

        #expect(sameYearLabel.contains("окт"))
        #expect(!sameYearLabel.contains("2026"))
        #expect(nextYearLabel.contains("янв"))
        #expect(nextYearLabel.contains("2027"))
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

    @Test func smartInputUsesCurrentPersonalDayParts() throws {
        let calendar = testCalendar
        let now = makeDate(2026, 9, 15, 12, 0, calendar: calendar)

        let morning = try #require(NaturalLanguageDateParser.parse(
            "Завтра утром проверить почту",
            now: now,
            calendar: calendar
        ))
        let lunch = try #require(NaturalLanguageDateParser.parse(
            "Завтра в обед позвонить коллеге",
            now: now,
            calendar: calendar
        ))
        let afterWork = try #require(NaturalLanguageDateParser.parse(
            "Завтра после работы зайти в аптеку",
            now: now,
            calendar: calendar
        ))

        #expect(morning.dueDate == makeDate(2026, 9, 16, 8, 0, calendar: calendar))
        #expect(lunch.dueDate == makeDate(2026, 9, 16, 13, 0, calendar: calendar))
        #expect(afterWork.dueDate == makeDate(2026, 9, 16, 18, 0, calendar: calendar))
    }

    @Test func smartInputUnderstandsPersonalScheduleBoundaries() throws {
        let calendar = testCalendar
        let now = makeDate(2026, 9, 15, 10, 0, calendar: calendar)

        let beforeLunch = try #require(NaturalLanguageDateParser.parse(
            "Завтра до обеда отправить отчет",
            now: now,
            calendar: calendar
        ))
        let afterLunch = try #require(NaturalLanguageDateParser.parse(
            "Завтра после обеда забрать заказ",
            now: now,
            calendar: calendar
        ))
        let endOfWorkday = try #require(NaturalLanguageDateParser.parse(
            "Завтра до конца рабочего дня согласовать макет",
            now: now,
            calendar: calendar
        ))

        #expect(beforeLunch.title == "отправить отчет")
        #expect(beforeLunch.dueDate == makeDate(2026, 9, 16, 13, 0, calendar: calendar))
        #expect(afterLunch.title == "забрать заказ")
        #expect(afterLunch.dueDate == makeDate(2026, 9, 16, 14, 0, calendar: calendar))
        #expect(endOfWorkday.title == "согласовать макет")
        #expect(endOfWorkday.dueDate == makeDate(2026, 9, 16, 18, 0, calendar: calendar))
    }

    @Test func deterministicTimeWinsOverSemanticModel() throws {
        let calendar = testCalendar
        let now = makeDate(2026, 9, 15, 10, 0, calendar: calendar)
        let parsed = try #require(NaturalLanguageDateParser.parse(
            "Завтра до обеда отправить отчет клиенту",
            now: now,
            calendar: calendar
        ))
        let semantic = ReminderDraft(
            transcript: "Завтра до обеда отправить отчет клиенту",
            title: "Отправить отчет клиенту",
            details: nil,
            dueDate: nil,
            reminderOffsets: [],
            confidence: .medium,
            ambiguities: [.missingDate, .ambiguousTime]
        )

        let result = VoiceDraftReconciler.reconcile(
            semantic: semantic,
            deterministic: parsed
        )

        #expect(result.title == "Отправить отчет клиенту")
        #expect(result.dueDate == makeDate(2026, 9, 16, 13, 0, calendar: calendar))
        #expect(!result.ambiguities.contains(.missingDate))
        #expect(!result.ambiguities.contains(.ambiguousTime))
    }

    @MainActor
    @Test func voiceClarificationDoesNotInterruptPlainInboxCapture() {
        let draft = ReminderDraft(
            transcript: "Купить фильтр для воды",
            title: "Купить фильтр для воды",
            details: nil,
            dueDate: nil,
            reminderOffsets: [],
            confidence: .medium,
            ambiguities: [.missingDate]
        )

        #expect(VoiceClarificationPolicy.decision(for: draft) == nil)
    }

    @MainActor
    @Test func voiceClarificationAsksAboutVagueDeadline() {
        let draft = ReminderDraft(
            transcript: "На днях отправить заявку",
            title: "Отправить заявку",
            details: nil,
            dueDate: nil,
            reminderOffsets: [],
            confidence: .medium,
            ambiguities: [.missingDate]
        )

        #expect(VoiceClarificationPolicy.decision(for: draft) == .date)
    }

    @MainActor
    @Test func voiceClarificationPrioritizesAmbiguousTime() {
        let draft = ReminderDraft(
            transcript: "Завтра ближе к обеду позвонить Анне",
            title: "Позвонить Анне",
            details: nil,
            dueDate: Date.now.addingTimeInterval(86_400),
            reminderOffsets: [],
            confidence: .medium,
            ambiguities: [.ambiguousTime]
        )

        #expect(VoiceClarificationPolicy.decision(for: draft) == .time)
    }

    @MainActor
    @Test func voiceLabSelectsSimilarConfirmedExamples() throws {
        let suiteName = "MemoryTests.voice.similarity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = VoiceLabStore(defaults: defaults)
        store.save(VoiceLabExample(
            transcript: "Завтра до обеда отправить отчет",
            expectedTitle: "Отправить отчет"
        ))
        store.save(VoiceLabExample(
            transcript: "Вечером купить молоко",
            expectedTitle: "Купить молоко"
        ))

        let matches = VoiceLabStore.similarExamples(
            to: "До обеда нужно отправить отчет клиенту",
            defaults: defaults
        )

        #expect(matches.first?.expectedTitle == "Отправить отчет")
    }

    @MainActor
    @Test func editedVoiceReminderBecomesConfirmedExample() throws {
        let suiteName = "MemoryTests.voice.correction.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let itemID = UUID()
        VoicePersonalizationStore.beginCapture(
            itemID: itemID,
            transcript: "Слушай завтра до обеда отправить отчет",
            title: "Отправить",
            details: nil,
            dueDate: nil,
            referenceDate: .now,
            defaults: defaults
        )

        VoicePersonalizationStore.confirmCorrection(
            itemID: itemID,
            title: "Отправить отчет",
            details: "Клиенту",
            dueDate: nil,
            defaults: defaults
        )

        let examples = VoiceLabStore.persistedExamples(defaults: defaults)
        #expect(examples.count == 1)
        #expect(examples.first?.expectedTitle == "Отправить отчет")
        #expect(examples.first?.expectedDetails == "Клиенту")
    }

    @MainActor
    @Test func cancelledVoiceBatchDoesNotBecomeLearningExample() throws {
        let suiteName = "MemoryTests.voice.cancel.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let itemID = UUID()
        VoicePersonalizationStore.beginCapture(
            itemID: itemID,
            transcript: "Оплатить интернет",
            title: "Оплатить интернет",
            details: nil,
            dueDate: nil,
            referenceDate: .now,
            defaults: defaults
        )
        VoicePersonalizationStore.discardCaptures(for: [itemID], defaults: defaults)
        VoicePersonalizationStore.confirmCorrection(
            itemID: itemID,
            title: "Другое название",
            details: nil,
            dueDate: nil,
            defaults: defaults
        )
        #expect(VoiceLabStore.persistedExamples(defaults: defaults).isEmpty)
    }

    @Test func smartInputTreatsPastTodayNightAsUpcomingNight() throws {
        let calendar = testCalendar
        let now = makeDate(2026, 9, 15, 21, 0, calendar: calendar)
        let result = try #require(NaturalLanguageDateParser.parse(
            "Сегодня ночью часа в два проверить сервер",
            now: now,
            calendar: calendar
        ))

        #expect(result.dueDate == makeDate(2026, 9, 16, 2, 0, calendar: calendar))
    }

    @Test func smartInputAppliesExplicitReminderLeadTime() throws {
        let calendar = testCalendar
        let now = makeDate(2026, 9, 15, 10, 0, calendar: calendar)
        let result = try #require(NaturalLanguageDateParser.parse(
            "Сегодня в 15:00 тренировка напомнить за час",
            now: now,
            calendar: calendar
        ))

        #expect(result.dueDate == makeDate(2026, 9, 15, 15, 0, calendar: calendar))
        #expect(result.reminderOffsets == [60])
    }

    @Test func localVoiceInterpreterSeparatesActionAndContext() throws {
        let calendar = testCalendar
        let now = makeDate(2026, 9, 15, 12, 0, calendar: calendar)
        let draft = try #require(LocalVoiceIntentInterpreter().interpret(
            "Через час продолжить работу над проектом потому что обновятся лимиты",
            now: now,
            calendar: calendar
        ).draft)

        #expect(draft.title == "Продолжить работу над проектом")
        #expect(draft.details == "Обновятся лимиты")
        #expect(draft.dueDate == makeDate(2026, 9, 15, 13, 0, calendar: calendar))
    }

    @Test func localVoiceInterpreterUsesLastTaskMarker() throws {
        let calendar = testCalendar
        let now = makeDate(2026, 9, 15, 12, 0, calendar: calendar)
        let draft = try #require(LocalVoiceIntentInterpreter().interpret(
            "Дома закончилась паста завтра после работы нужно будет зайти в магазин и купить две пачки",
            now: now,
            calendar: calendar
        ).draft)

        #expect(draft.title == "Зайти в магазин и купить две пачки")
        #expect(draft.details == "Дома закончилась паста")
        #expect(draft.dueDate == makeDate(2026, 9, 16, 18, 0, calendar: calendar))
    }

    @Test func localVoiceInterpreterKeepsCurrentDatedBehavior() throws {
        let calendar = testCalendar
        let now = makeDate(2026, 9, 15, 12, 0, calendar: calendar)
        let result = LocalVoiceIntentInterpreter().interpret(
            "Позвонить маме завтра в 10:30",
            now: now,
            calendar: calendar
        )
        let draft = try #require(result.draft)

        #expect(draft.title == "Позвонить маме")
        #expect(draft.details == nil)
        #expect(draft.dueDate == makeDate(2026, 9, 16, 10, 30, calendar: calendar))
        #expect(draft.confidence == .high)
        #expect(draft.ambiguities.isEmpty)
    }

    @Test func localVoiceInterpreterKeepsUndatedSpeechUsable() throws {
        let result = LocalVoiceIntentInterpreter().interpret(
            "Записать хорошую идею",
            now: .now,
            calendar: testCalendar
        )
        let draft = try #require(result.draft)

        #expect(draft.title == "Записать хорошую идею")
        #expect(draft.dueDate == nil)
        #expect(draft.confidence == .medium)
        #expect(draft.ambiguities == [.missingDate])
    }

    @Test func explicitVoiceItemsSplitWithoutSplittingDependentActions() {
        #expect(VoiceUtteranceSplitter.split(
            "Завтра оплатить интернет, и ещё в пятницу вебинар"
        ) == ["Завтра оплатить интернет", "в пятницу вебинар"])
        #expect(VoiceUtteranceSplitter.split(
            "Зайти в магазин и купить молоко"
        ) == ["Зайти в магазин и купить молоко"])
    }

    @Test func voiceReviewCountUsesRussianPluralForms() {
        #expect(VoiceEntryCountLabel.short(1) == "1 запись")
        #expect(VoiceEntryCountLabel.short(2) == "2 записи")
        #expect(VoiceEntryCountLabel.short(5) == "5 записей")
        #expect(VoiceEntryCountLabel.short(11) == "11 записей")
        #expect(VoiceEntryCountLabel.short(21) == "21 запись")
    }

    @MainActor
    @Test func voicePreviewShowsCountOnlyForExplicitSplit() {
        #expect(VoiceCapturePreview.classify("Завтра оплатить интернет") == .single)
        #expect(VoiceCapturePreview.classify(
            "Завтра оплатить интернет, и ещё в пятницу вебинар"
        ) == .multiple(2))
        #expect(VoiceCapturePreview.classify(
            "Завтра оплатить интернет и купить билеты"
        ) == .uncertain)
        #expect(VoiceCapturePreview.classify(
            "Завтра оплатить интернет. В пятницу вебинар"
        ) == .uncertain)
    }

    @Test func voiceBatchReviewTracksPersistedEntries() {
        let draft = ReminderDraft(
            transcript: "Купить молоко",
            title: "Купить молоко",
            details: nil,
            dueDate: nil,
            reminderOffsets: [],
            confidence: .high,
            ambiguities: []
        )
        var entry = VoiceReviewEntry(VoiceCaptureEntry(
            sourceText: "Купить молоко",
            draft: draft,
            kind: .reminder,
            endDate: nil
        ))
        #expect(!VoiceBatchReview(referenceDate: .now, entries: [entry]).isPersisted)
        entry.persistedItemID = UUID()
        #expect(VoiceBatchReview(referenceDate: .now, entries: [entry]).isPersisted)
    }

    @MainActor
    @Test func voiceReviewEditsPreserveOriginalsForBatchUndo() {
        let session = VoiceReviewTesting.session()
        let first = session.entries[0]
        let second = session.entries[1]
        session.update(
            second.id, title: "Купить продукты для поездки", details: "Список в заметках",
            kind: second.kind, date: second.dueDate, endDate: second.endDate,
            reminderOffsets: second.reminderOffsets
        )
        #expect(session.hasChanges)
        #expect(session.canSave)
        #expect(session.entries[0] == first)
        #expect(session.batch.entries[1] == second)
        #expect(session.entries[1].persistedItemID == second.persistedItemID)
        session.remove(first.id)
        #expect(session.entries.count == 1)
        #expect(session.batch.entries.count == 2)
        #expect(session.batch.isPersisted)
    }

    @Test func voiceReviewEntryKeepsDefaultReminderOffset() {
        let draft = ReminderDraft(
            transcript: "Оплатить завтра",
            title: "Оплатить",
            details: nil,
            dueDate: .now.addingTimeInterval(86_400),
            reminderOffsets: [],
            confidence: .high,
            ambiguities: []
        )
        let entry = VoiceReviewEntry(
            VoiceCaptureEntry(sourceText: draft.transcript, draft: draft, kind: .reminder, endDate: nil),
            defaultReminderMinutes: 60
        )
        #expect(entry.reminderOffsets == [60])
    }

    @Test func voiceReviewEditorChangesStayInBatchDraft() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = ReminderDraft(
            transcript: "Вебинар завтра",
            title: "Вебинар",
            details: nil,
            dueDate: start,
            reminderOffsets: [30],
            confidence: .high,
            ambiguities: []
        )
        var entry = VoiceReviewEntry(
            VoiceCaptureEntry(sourceText: draft.transcript, draft: draft, kind: .event, endDate: nil)
        )
        entry.applyEditorChanges(
            title: "Вебинар по дизайну",
            details: "Ссылка в письме",
            kind: .event,
            date: start,
            endDate: start.addingTimeInterval(7_200),
            reminderOffsets: [60]
        )
        #expect(entry.title == "Вебинар по дизайну")
        #expect(entry.details == "Ссылка в письме")
        #expect(entry.endDate == start.addingTimeInterval(7_200))
        #expect(entry.reminderOffsets == [60])
    }

    @Test func localVoiceCaptureCreatesIndependentDatedEntries() {
        let calendar = testCalendar
        let now = makeDate(2026, 9, 15, 12, 0, calendar: calendar)
        let result = VoiceCaptureResult.local(
            "Позвонить маме завтра в 10:30, и ещё оплатить интернет в пятницу в 15:00",
            now: now,
            calendar: calendar,
            defaultKind: .reminder
        )
        #expect(result.entries.count == 2)
        #expect(result.entries[0].draft.title == "Позвонить маме")
        #expect(result.entries[0].draft.dueDate == makeDate(2026, 9, 16, 10, 30, calendar: calendar))
        #expect(result.entries[1].draft.title == "Оплатить интернет")
    }

    @MainActor
    @Test func remoteVoiceResponseDecodesMixedEntriesAndLegacySingle() throws {
        let formatter = ISO8601DateFormatter()
        let mixed = Data(#"{"entries":[{"sourceText":"завтра оплатить интернет","kind":"reminder","title":"Оплатить интернет","details":null,"dueDate":"2026-09-16T09:00:00+04:00","endDate":null,"reminderOffsets":[],"confidence":"high","ambiguities":[]},{"sourceText":"в пятницу вебинар","kind":"event","title":"Вебинар","details":null,"dueDate":"2026-09-18T19:00:00+04:00","endDate":null,"reminderOffsets":[],"confidence":"high","ambiguities":[]}]}"#.utf8)
        let response = try JSONDecoder().decode(RemoteVoiceCaptureResponse.self, from: mixed)
        let result = try response.captureResult(
            transcript: "завтра оплатить интернет и в пятницу вебинар",
            dateFormatter: formatter,
            defaultKind: .reminder
        )
        #expect(result.entries.map(\.kind) == [.reminder, .event])
        #expect(result.entries[0].draft.dueDate != result.entries[1].draft.dueDate)

        let old = Data(#"{"title":"Позвонить маме","details":null,"dueDate":null,"reminderOffsets":[],"confidence":"medium","ambiguities":["missingDate"]}"#.utf8)
        let legacy = try JSONDecoder().decode(RemoteVoiceCaptureResponse.self, from: old)
        #expect(try legacy.captureResult(
            transcript: "Позвонить маме",
            dateFormatter: formatter,
            defaultKind: .reminder
        ).entries.count == 1)
    }

    @MainActor
    @Test func localVoiceInterpreterRejectsEmptySpeech() {
        let result = LocalVoiceIntentInterpreter().interpret(
            "   \n",
            now: .now,
            calendar: testCalendar
        )

        #expect(result == .empty)
    }

    @Test func voiceLabDetectsExactAndIncorrectResults() {
        let calendar = testCalendar
        let now = makeDate(2026, 9, 15, 12, 0, calendar: calendar)
        let dueDate = makeDate(2026, 9, 16, 10, 30, calendar: calendar)
        let exactExample = VoiceLabExample(
            transcript: "Позвонить маме завтра в 10:30",
            expectedTitle: "Позвонить маме",
            expectedDueDate: dueDate,
            referenceDate: now,
            timeZoneIdentifier: calendar.timeZone.identifier
        )
        let incorrectExample = VoiceLabExample(
            transcript: exactExample.transcript,
            expectedTranscript: "Позвонить папе завтра в 10:30",
            expectedTitle: "Купить продукты",
            expectedDueDate: dueDate,
            referenceDate: now,
            timeZoneIdentifier: calendar.timeZone.identifier
        )

        #expect(exactExample.evaluation(using: LocalVoiceIntentInterpreter()).isExactMatch)
        #expect(!incorrectExample.evaluation(using: LocalVoiceIntentInterpreter()).isExactMatch)
        #expect(!incorrectExample.evaluation(using: LocalVoiceIntentInterpreter()).transcriptMatches)
        #expect(!incorrectExample.evaluation(using: LocalVoiceIntentInterpreter()).titleMatches)
    }

    @Test func voiceLabAllowsSmallRelativeTimeCaptureDelay() {
        let calendar = testCalendar
        let now = makeDate(2026, 9, 15, 12, 0, calendar: calendar)
        let example = VoiceLabExample(
            transcript: "Через час проверить отчёт",
            expectedTitle: "Проверить отчёт",
            expectedDueDate: now.addingTimeInterval(3_660),
            referenceDate: now,
            timeZoneIdentifier: calendar.timeZone.identifier
        )

        #expect(example.evaluation(using: LocalVoiceIntentInterpreter()).dateMatches)
    }

    @MainActor
    @Test func voiceLabPersistsCorrectionsLocally() throws {
        let suiteName = "MemoryTests.VoiceLab.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storageKey = "examples"
        let example = VoiceLabExample(
            transcript: "Завтра проверить отчёт",
            expectedTitle: "Проверить отчёт"
        )

        let firstStore = VoiceLabStore(defaults: defaults, storageKey: storageKey)
        firstStore.save(example)
        let restoredStore = VoiceLabStore(defaults: defaults, storageKey: storageKey)

        #expect(restoredStore.examples == [example])
    }

    @Test func notificationPermissionErrorBecomesReadableAppError() {
        let systemError = NSError(
            domain: UNErrorDomain,
            code: UNError.Code.notificationsNotAllowed.rawValue
        )

        let normalized = ReminderScheduler.normalizedNotificationError(systemError)

        #expect(normalized is ReminderError)
        #expect(normalized.localizedDescription == "Уведомления для Norka выключены в настройках системы.")
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
