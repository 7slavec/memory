import Foundation
import UserNotifications

enum ReminderError: LocalizedError {
    case notificationsDisabled

    var errorDescription: String? {
        switch self {
        case .notificationsDisabled:
            return "Уведомления для Memory выключены в настройках системы."
        }
    }
}

enum ReminderScheduler {
    static func schedule(id: UUID, title: String, at date: Date) async throws {
        let center = UNUserNotificationCenter.current()
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

        center.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        guard date.timeIntervalSinceNow > 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Напоминание"
        content.body = title
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: id.uuidString,
            content: content,
            trigger: trigger
        )
        try await center.add(request)
    }

    static func cancel(id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }
}
