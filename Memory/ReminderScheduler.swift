import Foundation
import UserNotifications

enum ReminderError: LocalizedError {
    case notificationsDisabled

    var errorDescription: String? {
        switch self {
        case .notificationsDisabled:
            return "Уведомления для Norka выключены в настройках системы."
        }
    }
}

enum ReminderScheduler {
    static let applicationNotificationsEnabledKey = "applicationNotificationsEnabled"

    static var applicationNotificationsEnabled: Bool {
        UserDefaults.standard.object(forKey: applicationNotificationsEnabledKey) as? Bool ?? true
    }

    static func setApplicationNotificationsEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: applicationNotificationsEnabledKey)
    }

    static func notificationsAreDisabled() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .denied
    }

    static func schedule(
        id: UUID,
        title: String,
        details: String? = nil,
        at date: Date,
        offsets: [Int]
    ) async throws {
        let center = UNUserNotificationCenter.current()
        let normalizedOffsets = ReminderLeadTime.normalized(offsets)
        center.removePendingNotificationRequests(withIdentifiers: notificationIdentifiers(for: id))
        guard applicationNotificationsEnabled else { return }
        guard !normalizedOffsets.isEmpty else { return }

        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            let granted: Bool
            do {
                granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                throw normalizedNotificationError(error)
            }
            guard granted else { throw ReminderError.notificationsDisabled }
        case .denied:
            throw ReminderError.notificationsDisabled
        case .authorized, .provisional, .ephemeral:
            break
        @unknown default:
            break
        }

        let deliveryOffsets = deliverableOffsets(
            dueDate: date,
            requestedOffsets: normalizedOffsets
        )

        for offset in deliveryOffsets {
            let notificationDate = date.addingTimeInterval(TimeInterval(-offset * 60))

            let content = notificationContent(
                id: id,
                title: title,
                details: details,
                dueDate: date,
                offset: offset
            )

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: notificationDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: notificationIdentifier(for: id, offset: offset),
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
            } catch {
                throw normalizedNotificationError(error)
            }
        }
    }

    static func deliverableOffsets(
        dueDate: Date,
        requestedOffsets: [Int],
        now: Date = .now
    ) -> [Int] {
        let normalizedOffsets = ReminderLeadTime.normalized(requestedOffsets)
        let futureOffsets = normalizedOffsets.filter { offset in
            dueDate.addingTimeInterval(TimeInterval(-offset * 60))
                .timeIntervalSince(now) > 1
        }

        if futureOffsets.isEmpty,
           !normalizedOffsets.isEmpty,
           dueDate.timeIntervalSince(now) > 1 {
            return [ReminderLeadTime.atTime.rawValue]
        }
        return futureOffsets
    }

    static func cancel(id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: notificationIdentifiers(for: id))
    }

    static func notificationContent(
        id: UUID,
        title: String,
        details: String?,
        dueDate: Date,
        offset: Int
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDetails = details?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        content.title = normalizedTitle.isEmpty ? "Напоминание" : normalizedTitle
        content.subtitle = notificationTimingText(dueDate: dueDate, offset: offset)
        if let normalizedDetails, !normalizedDetails.isEmpty {
            content.body = String(normalizedDetails.prefix(220))
        }
        content.sound = .default
        content.threadIdentifier = "norka.reminders"
        content.userInfo = [
            "itemID": id.uuidString,
            "dueDate": dueDate.timeIntervalSince1970
        ]
        return content
    }

    private static func notificationTimingText(dueDate: Date, offset: Int) -> String {
        let time = dueDate.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened).locale(.current)
        )

        guard let leadTime = ReminderLeadTime(rawValue: offset) else {
            return dueDate.formatted(
                Date.FormatStyle(date: .abbreviated, time: .shortened).locale(.current)
            )
        }

        switch leadTime {
        case .atTime:
            return "Сейчас · \(time)"
        case .fiveMinutes:
            return "Через 5 минут · \(time)"
        case .fifteenMinutes:
            return "Через 15 минут · \(time)"
        case .thirtyMinutes:
            return "Через 30 минут · \(time)"
        case .oneHour:
            return "Через час · \(time)"
        case .oneDay:
            return "Завтра · \(time)"
        case .twoDays:
            return "Через 2 дня · \(formattedDueDate(dueDate))"
        case .oneWeek:
            return "Через неделю · \(formattedDueDate(dueDate))"
        }
    }

    private static func formattedDueDate(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened).locale(.current)
        )
    }

    private static func notificationIdentifier(for id: UUID, offset: Int) -> String {
        "\(id.uuidString)-reminder-\(offset)"
    }

    private static func notificationIdentifiers(for id: UUID) -> [String] {
        [id.uuidString] + ReminderLeadTime.allCases.map {
            notificationIdentifier(for: id, offset: $0.rawValue)
        }
    }

    static func normalizedNotificationError(_ error: Error) -> Error {
        let notificationError = error as NSError
        guard notificationError.domain == UNErrorDomain,
              notificationError.code == UNError.Code.notificationsNotAllowed.rawValue else {
            return error
        }
        return ReminderError.notificationsDisabled
    }
}
