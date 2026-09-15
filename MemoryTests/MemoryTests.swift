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

}
