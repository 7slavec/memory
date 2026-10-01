//
//  Item.swift
//  Memory
//
//  Created by Вячеслав Храмышкин on 15.09.2026.
//

import Foundation
import SwiftData

enum MemoryDateFormatting {
    // Immutable after construction. NSCache is bounded and thread-safe; the time
    // zone is part of the key so travelling/settings changes cannot reuse old output.
    private static let formatters: NSCache<NSString, DateFormatter> = {
        let cache = NSCache<NSString, DateFormatter>()
        cache.countLimit = 24
        return cache
    }()
    static func shortDate(_ date: Date) -> String {
        formatter("d MMM").string(from: date)
    }

    static func shortDateTime(_ date: Date) -> String {
        formatter("d MMM, HH:mm").string(from: date)
    }

    static func fullDate(_ date: Date) -> String {
        formatter("d MMMM yyyy").string(from: date)
    }

    static func editorDate(_ date: Date, relativeTo referenceDate: Date = .now) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let includesYear = calendar.component(.year, from: date)
            != calendar.component(.year, from: referenceDate)
        let month = ["янв", "фев", "мар", "апр", "май", "июн",
                     "июл", "авг", "сен", "окт", "ноя", "дек"][calendar.component(.month, from: date) - 1]
        let day = calendar.component(.day, from: date)
        return "\(day) \(month)" + (includesYear ? " \(calendar.component(.year, from: date))" : "")
    }

    static func time(_ date: Date) -> String {
        formatter("HH:mm").string(from: date)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let timeZone = TimeZone.current
        let key = "\(format)|\(timeZone.identifier)" as NSString
        if let cached = formatters.object(forKey: key) { return cached }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format
        formatter.timeZone = timeZone
        formatters.setObject(formatter, forKey: key)
        return formatter
    }
}

enum EntryKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case reminder
    case event

    var id: Self { self }

    var title: String {
        switch self {
        case .reminder: "Напоминание"
        case .event: "Событие"
        }
    }

    var compactTitle: String {
        switch self {
        case .reminder: "Напомнить"
        case .event: "Событие"
        }
    }

    var icon: String {
        switch self {
        case .reminder: "checkmark.circle"
        case .event: "calendar"
        }
    }
}

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
    var entryKindRaw: String = EntryKind.reminder.rawValue
    var endDate: Date?
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
        entryKind: EntryKind = .reminder,
        endDate: Date? = nil,
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
        self.entryKindRaw = entryKind.rawValue
        self.endDate = entryKind == .event ? endDate : nil
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
        guard entryKind == .reminder else { return }
        isCompleted = completed
        completedAt = completed ? .now : nil
        updatedAt = .now
    }

    var isActiveEvent: Bool { isActiveEvent(at: .now) }

    func isActiveEvent(at date: Date) -> Bool {
        EventActivity.isActive(
            kind: entryKind, start: dueDate, end: endDate,
            isCompleted: isCompleted, at: date
        )
    }

    @discardableResult
    func finishEvent(at date: Date) -> Bool {
        guard isActiveEvent(at: date) else { return false }
        endDate = date
        isCompleted = true
        completedAt = date
        updatedAt = date
        return true
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
    var entryKind: EntryKind {
        get { EntryKind(rawValue: entryKindRaw) ?? .reminder }
        set {
            if entryKind != newValue {
                isCompleted = false
                completedAt = nil
            }
            entryKindRaw = newValue.rawValue
            if newValue == .reminder {
                endDate = nil
            }
        }
    }

    var isEvent: Bool { entryKind == .event }

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
