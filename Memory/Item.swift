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
    var ownerID: String?
    var deletedAt: Date?

    init(
        title: String,
        timestamp: Date = .now,
        isCompleted: Bool = false,
        dueDate: Date? = nil,
        notificationsEnabled: Bool? = nil,
        ownerID: String? = nil,
        id: UUID = UUID(),
        completedAt: Date? = nil,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.timestamp = timestamp
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.notificationEnabled = notificationsEnabled ?? (dueDate != nil)
        self.completedAt = completedAt ?? (isCompleted ? .now : nil)
        self.updatedAt = updatedAt
        self.ownerID = ownerID
        self.deletedAt = deletedAt
    }

    func setCompleted(_ completed: Bool) {
        isCompleted = completed
        completedAt = completed ? .now : nil
        updatedAt = .now
    }

    func markDeleted() {
        deletedAt = .now
        updatedAt = deletedAt ?? .now
    }
}

extension Item {
    var notificationsEnabled: Bool {
        get { notificationEnabled ?? (dueDate != nil) }
        set { notificationEnabled = newValue }
    }
}
