import Foundation

/// An event is live only while its explicit start/end range contains `now`.
/// Events without an end never imply an ongoing timer.
enum EventActivity {
    static func isActive(
        kind: EntryKind,
        start: Date?,
        end: Date?,
        isCompleted: Bool,
        at now: Date
    ) -> Bool {
        guard kind == .event, !isCompleted, let start, let end else { return false }
        return start <= now && now < end
    }

    static func remaining(until end: Date, at now: Date) -> EventTimeRemaining? {
        guard end > now else { return nil }
        let minutes = max(1, Int(ceil(end.timeIntervalSince(now) / 60)))
        return EventTimeRemaining(totalMinutes: minutes)
    }
}

struct EventTimeRemaining: Equatable {
    let totalMinutes: Int

    var days: Int { totalMinutes / 1_440 }
    var hours: Int { (totalMinutes % 1_440) / 60 }
    var minutes: Int { totalMinutes % 60 }
    var hasDays: Bool { days > 0 }

    var display: String {
        if hasDays { return "\(days):\(twoDigits(hours)):\(twoDigits(minutes))" }
        return "\(twoDigits(hours)):\(twoDigits(minutes))"
    }

    var accessibilityText: String {
        let hourText = "\(hours) \(word(hours, one: "час", few: "часа", many: "часов"))"
        let minuteText = "\(minutes) \(word(minutes, one: "минута", few: "минуты", many: "минут"))"
        guard hasDays else { return "Осталось \(hourText) \(minuteText)" }
        let dayText = "\(days) \(word(days, one: "день", few: "дня", many: "дней"))"
        return "Осталось \(dayText) \(hourText) \(minuteText)"
    }

    private func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : String(value)
    }

    private func word(_ value: Int, one: String, few: String, many: String) -> String {
        let lastTwo = value % 100
        if (11...14).contains(lastTwo) { return many }
        switch value % 10 {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }
}
