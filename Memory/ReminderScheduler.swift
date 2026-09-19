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

    static func schedule(id: UUID, title: String, at date: Date, offsets: [Int]) async throws {
        let center = UNUserNotificationCenter.current()
        let normalizedOffsets = ReminderLeadTime.normalized(offsets)
        center.removePendingNotificationRequests(withIdentifiers: notificationIdentifiers(for: id))
        guard applicationNotificationsEnabled else { return }
        guard !normalizedOffsets.isEmpty else { return }

        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { throw ReminderError.notificationsDisabled }
        case .denied:
            throw ReminderError.notificationsDisabled
        case .authorized, .provisional, .ephemeral:
            break
        @unknown default:
            break
        }

        for offset in normalizedOffsets {
            let notificationDate = date.addingTimeInterval(TimeInterval(-offset * 60))
            guard notificationDate.timeIntervalSinceNow > 1 else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Напоминание"
            content.body = title
            content.sound = .default

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: notificationDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: notificationIdentifier(for: id, offset: offset),
                content: content,
                trigger: trigger
            )
            try await center.add(request)
        }
    }

    static func cancel(id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: notificationIdentifiers(for: id))
    }

    private static func notificationIdentifier(for id: UUID, offset: Int) -> String {
        "\(id.uuidString)-reminder-\(offset)"
    }

    private static func notificationIdentifiers(for id: UUID) -> [String] {
        [id.uuidString] + ReminderLeadTime.allCases.map {
            notificationIdentifier(for: id, offset: $0.rawValue)
        }
    }
}
