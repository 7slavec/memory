import Foundation

struct ParsedMemoryInput {
    let title: String
    let dueDate: Date
}

enum NaturalLanguageDateParser {
    static func parse(
        _ input: String,
        now: Date = .now,
        calendar sourceCalendar: Calendar = .current
    ) -> ParsedMemoryInput? {
        let original = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return nil }

        let normalized = original
            .lowercased(with: Locale(identifier: "ru_RU"))
            .replacingOccurrences(of: "ё", with: "е")
        var calendar = sourceCalendar
        calendar.locale = Locale(identifier: "ru_RU")

        if let relative = parseRelativeDate(in: normalized, now: now, calendar: calendar) {
            return ParsedMemoryInput(
                title: cleanedTitle(from: original, removing: [relative.range]),
                dueDate: relative.date
            )
        }

        var rangesToRemove: [NSRange] = []
        let day = parseDay(in: normalized, now: now, calendar: calendar)
        if let range = day?.range { rangesToRemove.append(range) }

        let time = parseTime(in: normalized)
        if let range = time?.range { rangesToRemove.append(range) }

        guard day != nil || time != nil else { return nil }

        let targetDay = day?.date ?? calendar.startOfDay(for: now)
        let targetDate: Date

        if let time {
            targetDate = calendar.date(
                bySettingHour: time.hour,
                minute: time.minute,
                second: 0,
                of: targetDay
            ) ?? targetDay
        } else if day?.isExplicitToday == true {
            targetDate = calendar.date(byAdding: .hour, value: 1, to: now) ?? now
        } else {
            targetDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: targetDay) ?? targetDay
        }

        var resolvedDate = targetDate
        if day == nil, resolvedDate <= now {
            resolvedDate = calendar.date(byAdding: .day, value: 1, to: resolvedDate) ?? resolvedDate
        } else if day?.isWeekday == true, resolvedDate <= now {
            resolvedDate = calendar.date(byAdding: .day, value: 7, to: resolvedDate) ?? resolvedDate
        }

        return ParsedMemoryInput(
            title: cleanedTitle(from: original, removing: rangesToRemove),
            dueDate: resolvedDate
        )
    }

    private struct RelativeMatch {
        let date: Date
        let range: NSRange
    }

    private struct DayMatch {
        let date: Date
        let range: NSRange
        let isWeekday: Bool
        let isExplicitToday: Bool
    }

    private struct TimeMatch {
        let hour: Int
        let minute: Int
        let range: NSRange
    }

    private static func parseRelativeDate(
        in text: String,
        now: Date,
        calendar: Calendar
    ) -> RelativeMatch? {
        if let match = firstMatch(pattern: #"\bчерез\s+полчаса\b"#, in: text),
           let date = calendar.date(byAdding: .minute, value: 30, to: now) {
            return RelativeMatch(date: date, range: match.range)
        }

        if let match = firstMatch(pattern: #"\bчерез\s+час\b"#, in: text),
           let date = calendar.date(byAdding: .hour, value: 1, to: now) {
            return RelativeMatch(date: date, range: match.range)
        }

        let pattern = #"\bчерез\s+(\d+)\s*(минут(?:у|ы)?|час(?:а|ов)?|д(?:ень|ня|ней)|недел(?:ю|и|ь))\b"#
        guard let match = firstMatch(pattern: pattern, in: text),
              let amountRange = Range(match.range(at: 1), in: text),
              let amount = Int(text[amountRange]),
              let unitRange = Range(match.range(at: 2), in: text) else { return nil }

        let unit = String(text[unitRange])
        let component: Calendar.Component
        if unit.hasPrefix("минут") {
            component = .minute
        } else if unit.hasPrefix("час") {
            component = .hour
        } else if unit.hasPrefix("недел") {
            component = .weekOfYear
        } else {
            component = .day
        }

        guard let date = calendar.date(byAdding: component, value: amount, to: now) else { return nil }
        return RelativeMatch(date: date, range: match.range)
    }

    private static func parseDay(in text: String, now: Date, calendar: Calendar) -> DayMatch? {
        let namedDays: [(pattern: String, offset: Int, today: Bool)] = [
            (#"\b(?:на\s+)?послезавтра\b"#, 2, false),
            (#"\b(?:на\s+)?завтра\b"#, 1, false),
            (#"\b(?:на\s+)?сегодня\b"#, 0, true)
        ]

        for namedDay in namedDays {
            if let match = firstMatch(pattern: namedDay.pattern, in: text),
               let date = calendar.date(
                   byAdding: .day,
                   value: namedDay.offset,
                   to: calendar.startOfDay(for: now)
               ) {
                return DayMatch(
                    date: date,
                    range: match.range,
                    isWeekday: false,
                    isExplicitToday: namedDay.today
                )
            }
        }

        let weekdayPattern = #"\b(?:в\s+|во\s+)?(понедельник|вторник|среду|четверг|пятницу|субботу|воскресенье)\b"#
        guard let match = firstMatch(pattern: weekdayPattern, in: text),
              let weekdayRange = Range(match.range(at: 1), in: text) else { return nil }

        let weekdayName = String(text[weekdayRange])
        let weekday: Int
        switch weekdayName {
        case "понедельник": weekday = 2
        case "вторник": weekday = 3
        case "среду": weekday = 4
        case "четверг": weekday = 5
        case "пятницу": weekday = 6
        case "субботу": weekday = 7
        default: weekday = 1
        }

        let currentWeekday = calendar.component(.weekday, from: now)
        let daysAhead = (weekday - currentWeekday + 7) % 7
        let date = calendar.date(
            byAdding: .day,
            value: daysAhead,
            to: calendar.startOfDay(for: now)
        ) ?? now
        return DayMatch(date: date, range: match.range, isWeekday: true, isExplicitToday: false)
    }

    private static func parseTime(in text: String) -> TimeMatch? {
        let hourWithDayPartPattern = #"\b(?:в\s+)?(1[0-2]|[1-9]|час|один|два|три|четыре|пять|шесть|семь|восемь|девять|десять|одиннадцать|двенадцать)(?::([0-5]\d))?(?:\s*час(?:а|ов)?)?\s+(утра|дня|вечера|ночи)\b"#
        if let match = firstMatch(pattern: hourWithDayPartPattern, in: text),
           let hourRange = Range(match.range(at: 1), in: text),
           let hour = hourValue(for: String(text[hourRange])),
           let dayPartRange = Range(match.range(at: 3), in: text) {
            let minute: Int
            if match.range(at: 2).location != NSNotFound,
               let minuteRange = Range(match.range(at: 2), in: text) {
                minute = Int(text[minuteRange]) ?? 0
            } else {
                minute = 0
            }

            let dayPart = String(text[dayPartRange])
            return TimeMatch(
                hour: hourAdjusted(hour, for: dayPart),
                minute: minute,
                range: match.range
            )
        }

        let numericPatterns = [
            #"\b(?:в\s+)?([01]?\d|2[0-3])[:.]([0-5]\d)\b"#,
            #"\bв\s+([01]?\d|2[0-3])(?:\s*час(?:а|ов)?)?\b"#
        ]

        for pattern in numericPatterns {
            guard let match = firstMatch(pattern: pattern, in: text),
                  let hourRange = Range(match.range(at: 1), in: text),
                  let hour = Int(text[hourRange]) else { continue }
            let minute: Int
            if match.numberOfRanges > 2,
               match.range(at: 2).location != NSNotFound,
               let minuteRange = Range(match.range(at: 2), in: text) {
                minute = Int(text[minuteRange]) ?? 0
            } else {
                minute = 0
            }
            return TimeMatch(hour: hour, minute: minute, range: match.range)
        }

        let spokenHourPattern = #"\bв\s+(час|один|два|три|четыре|пять|шесть|семь|восемь|девять|десять|одиннадцать|двенадцать)(?:\s*час(?:а|ов)?)?\b"#
        if let match = firstMatch(pattern: spokenHourPattern, in: text),
           let hourRange = Range(match.range(at: 1), in: text),
           let hour = hourValue(for: String(text[hourRange])) {
            return TimeMatch(hour: hour, minute: 0, range: match.range)
        }

        let dayParts: [(pattern: String, hour: Int)] = [
            (#"\bутром\b"#, 9),
            (#"\bднем\b"#, 14),
            (#"\bвечером\b"#, 19),
            (#"\bночью\b"#, 23)
        ]
        for dayPart in dayParts {
            if let match = firstMatch(pattern: dayPart.pattern, in: text) {
                return TimeMatch(hour: dayPart.hour, minute: 0, range: match.range)
            }
        }
        return nil
    }

    private static func hourValue(for token: String) -> Int? {
        if let numericHour = Int(token), (1...12).contains(numericHour) {
            return numericHour
        }

        switch token {
        case "час", "один": return 1
        case "два": return 2
        case "три": return 3
        case "четыре": return 4
        case "пять": return 5
        case "шесть": return 6
        case "семь": return 7
        case "восемь": return 8
        case "девять": return 9
        case "десять": return 10
        case "одиннадцать": return 11
        case "двенадцать": return 12
        default: return nil
        }
    }

    private static func hourAdjusted(_ hour: Int, for dayPart: String) -> Int {
        switch dayPart {
        case "дня", "вечера":
            return hour == 12 ? 12 : hour + 12
        case "ночи":
            if hour == 12 { return 0 }
            return hour <= 5 ? hour : hour + 12
        default:
            return hour == 12 ? 0 : hour
        }
    }

    private static func firstMatch(pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        return expression.firstMatch(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        )
    }

    private static func cleanedTitle(from input: String, removing ranges: [NSRange]) -> String {
        var result = input
        for range in ranges.sorted(by: { $0.location > $1.location }) {
            guard let swiftRange = Range(range, in: result) else { continue }
            result.removeSubrange(swiftRange)
        }

        result = result.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        result = result.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        return result.isEmpty ? input.trimmingCharacters(in: .whitespacesAndNewlines) : result
    }
}
