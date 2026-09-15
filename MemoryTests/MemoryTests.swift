//
//  MemoryTests.swift
//  MemoryTests
//
//  Created by Вячеслав Храмышкин on 15.09.2026.
//

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

}
