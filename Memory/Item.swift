//
//  Item.swift
//  Memory
//
//  Created by Вячеслав Храмышкин on 15.09.2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var id: UUID = UUID()
    var title: String = ""
    var timestamp: Date = Date.now
    var isCompleted: Bool = false
    var dueDate: Date?
    var notificationEnabled: Bool?
    var completedAt: Date?
    var updatedAt: Date = Date.now

    init(
        title: String,
        timestamp: Date = .now,
        isCompleted: Bool = false,
        dueDate: Date? = nil,
        notificationsEnabled: Bool? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.timestamp = timestamp
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.notificationEnabled = notificationsEnabled ?? (dueDate != nil)
        self.completedAt = isCompleted ? .now : nil
        self.updatedAt = .now
    }

    func setCompleted(_ completed: Bool) {
        isCompleted = completed
        completedAt = completed ? .now : nil
        updatedAt = .now
    }
}

extension Item {
    var notificationsEnabled: Bool {
        get { notificationEnabled ?? (dueDate != nil) }
        set { notificationEnabled = newValue }
    }
}
