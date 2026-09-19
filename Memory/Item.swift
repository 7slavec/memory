//
//  Item.swift
//  Memory
//
//  Created by Вячеслав Храмышкин on 15.09.2026.
//

import Foundation
import SwiftData

enum ReminderLeadTime: Int, CaseIterable, Identifiable, Codable, Sendable {
    case atTime = 0
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case oneDay = 1_440
    case twoDays = 2_880
    case oneWeek = 10_080

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .atTime: "В момент события"
        case .fiveMinutes: "За 5 минут"
        case .fifteenMinutes: "За 15 минут"
        case .thirtyMinutes: "За 30 минут"
        case .oneHour: "За 1 час"
        case .oneDay: "За 1 день"
        case .twoDays: "За 2 дня"
        case .oneWeek: "За неделю"
        }
    }

    var compactTitle: String {
        switch self {
        case .atTime: "В момент"
        case .fiveMinutes: "За 5 мин"
        case .fifteenMinutes: "За 15 мин"
        case .thirtyMinutes: "За 30 мин"
        case .oneHour: "За час"
        case .oneDay: "За день"
        case .twoDays: "За 2 дня"
        case .oneWeek: "За неделю"
        }
    }

    static func normalized(_ values: [Int]) -> [Int] {
        let supported = Set(allCases.map(\.rawValue))
        return Array(Set(values.filter(supported.contains))).sorted()
    }

    static func summary(_ values: [Int]) -> String {
        normalized(values)
            .compactMap(ReminderLeadTime.init(rawValue:))
            .map(\.compactTitle)
            .joined(separator: " · ")
    }
}

@Model
final class Item {
    var id: UUID = UUID()
    var title: String = ""
    var details: String?
    var timestamp: Date = Date.now
    var isCompleted: Bool = false
    var dueDate: Date?
    var notificationEnabled: Bool?
    var reminderOffsets: [Int] = []
    var completedAt: Date?
    var updatedAt: Date = Date.now
    var ownerID: String?
    var deletedAt: Date?

    init(
        title: String,
        details: String? = nil,
        timestamp: Date = .now,
        isCompleted: Bool = false,
        dueDate: Date? = nil,
        notificationsEnabled: Bool? = nil,
        reminderOffsets: [Int]? = nil,
        ownerID: String? = nil,
        id: UUID = UUID(),
        completedAt: Date? = nil,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.details = Self.normalizedDetails(details)
        self.timestamp = timestamp
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        let normalizedOffsets = ReminderLeadTime.normalized(reminderOffsets ?? [])
        let shouldNotify = notificationsEnabled
            ?? (reminderOffsets == nil ? dueDate != nil : !normalizedOffsets.isEmpty)
        self.notificationEnabled = shouldNotify
        self.reminderOffsets = shouldNotify
            ? (normalizedOffsets.isEmpty ? [ReminderLeadTime.atTime.rawValue] : normalizedOffsets)
            : []
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

    static func normalizedDetails(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Item {
    var notificationsEnabled: Bool {
        get { notificationEnabled ?? (dueDate != nil) }
        set { notificationEnabled = newValue }
    }

    var effectiveReminderOffsets: [Int] {
        let normalized = ReminderLeadTime.normalized(reminderOffsets)
        if normalized.isEmpty, notificationsEnabled, dueDate != nil {
            return [ReminderLeadTime.atTime.rawValue]
        }
        return normalized
    }

    func setReminderOffsets(_ values: [Int]) {
        let normalized = ReminderLeadTime.normalized(values)
        reminderOffsets = normalized
        notificationsEnabled = !normalized.isEmpty
    }
}
