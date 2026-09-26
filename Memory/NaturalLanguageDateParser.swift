import Foundation

struct ParsedMemoryInput {
    let title: String
    let dueDate: Date
    let reminderOffsets: [Int]
}

struct NaturalLanguageTimeProfile: Equatable, Sendable {
    let morningHour: Int
    let workStartHour: Int
    let lunchStartHour: Int
    let lunchEndHour: Int
    let workEndHour: Int
    let eveningHour: Int
    let nightHour: Int

    static let current = NaturalLanguageTimeProfile(
        morningHour: 8,
        workStartHour: 9,
        lunchStartHour: 13,
        lunchEndHour: 14,
        workEndHour: 18,
        eveningHour: 19,
        nightHour: 0
    )
}

enum NaturalLanguageDateParser {
    static func parse(
        _ input: String,
        now: Date = .now,
        calendar sourceCalendar: Calendar = .current,
        profile: NaturalLanguageTimeProfile = .current
    ) -> ParsedMemoryInput? {
        let original = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return nil }

        let normalized = original
            .lowercased(with: Locale(identifier: "ru_RU"))
            .replacingOccurrences(of: "ё", with: "е")
        var calendar = sourceCalendar
        calendar.locale = Locale(identifier: "ru_RU")
        let reminderLead = parseReminderLeadTime(in: normalized)

        if let relative = parseRelativeDate(in: normalized, now: now, calendar: calendar) {
            let removalRanges = [relative.range, reminderLead?.range].compactMap { $0 }
            return ParsedMemoryInput(
                title: cleanedTitle(from: original, removing: removalRanges),
                dueDate: relative.date,
                reminderOffsets: reminderLead.map { [$0.minutes] } ?? []
            )
        }

        var rangesToRemove: [NSRange] = []
        let day = parseDay(in: normalized, now: now, calendar: calendar)
        if let range = day?.range { rangesToRemove.append(range) }

        let time = parseTime(in: normalized, profile: profile)
        if let range = time?.range { rangesToRemove.append(range) }

        if let range = reminderLead?.range { rangesToRemove.append(range) }

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
        } else if day?.isExplicitToday == true,
                  time?.belongsToUpcomingNight == true,
                  resolvedDate <= now {
            resolvedDate = calendar.date(byAdding: .day, value: 1, to: resolvedDate) ?? resolvedDate
        } else if day?.isWeekday == true, resolvedDate <= now {
            resolvedDate = calendar.date(byAdding: .day, value: 7, to: resolvedDate) ?? resolvedDate
        }

        return ParsedMemoryInput(
            title: cleanedTitle(from: original, removing: rangesToRemove),
            dueDate: resolvedDate,
            reminderOffsets: reminderLead.map { [$0.minutes] } ?? []
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
        let belongsToUpcomingNight: Bool
    }

    private struct ReminderLeadMatch {
        let minutes: Int
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

        let weekdayPattern = #"\b(?:в\s+|во\s+|до\s+)?(понедельник|понедельника|вторник|вторника|среду|среды|четверг|четверга|пятницу|пятницы|субботу|субботы|воскресенье|воскресенья)\b"#
        guard let match = firstMatch(pattern: weekdayPattern, in: text),
              let weekdayRange = Range(match.range(at: 1), in: text) else { return nil }

        let weekdayName = String(text[weekdayRange])
        let weekday: Int
        switch weekdayName {
        case "понедельник", "понедельника": weekday = 2
        case "вторник", "вторника": weekday = 3
        case "среду", "среды": weekday = 4
        case "четверг", "четверга": weekday = 5
        case "пятницу", "пятницы": weekday = 6
        case "субботу", "субботы": weekday = 7
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

    private static func parseTime(
        in text: String,
        profile: NaturalLanguageTimeProfile
    ) -> TimeMatch? {
        let halfHourPattern = #"\b(?:в\s+)?пол\s*(1\s+[0-2]|1[0-2]|[1-9]|первого|первом|второго|втором|третьего|третьем|четвертого|четвертом|пятого|пятом|шестого|шестом|седьмого|седьмом|восьмого|восьмом|девятого|девятом|десятого|десятом|одиннадцатого|одиннадцатом|двенадцатого|двенадцатом)(?:\s+(утра|утром|дня|днем|вечера|вечером|ночи|ночью))?\b"#
        if let match = firstMatch(pattern: halfHourPattern, in: text),
           let targetHourRange = Range(match.range(at: 1), in: text),
           let targetHour = halfHourTargetValue(for: String(text[targetHourRange])) {
            let precedingHour = targetHour == 1 ? 0 : targetHour - 1
            let resolvedHour: Int
            if match.range(at: 2).location != NSNotFound,
               let dayPartRange = Range(match.range(at: 2), in: text) {
                resolvedHour = hourAdjusted(precedingHour, for: String(text[dayPartRange]))
            } else {
                resolvedHour = precedingHour
            }
            let dayPart = Range(match.range(at: 2), in: text).map { String(text[$0]) }
            return TimeMatch(
                hour: resolvedHour,
                minute: 30,
                range: match.range,
                belongsToUpcomingNight: dayPart.map { isNightPart($0) } ?? false
            )
        }

        let hourWithDayPartPattern = #"\b(?:в\s+)?(1[0-2]|[1-9]|час|один|два|три|четыре|пять|шесть|семь|восемь|девять|десять|одиннадцать|двенадцать)(?::([0-5]\d))?(?:\s*час(?:а|ов)?)?\s+(утра|утром|дня|днем|вечера|вечером|ночи|ночью)\b"#
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
                range: match.range,
                belongsToUpcomingNight: isNightPart(dayPart)
            )
        }

        let conversationalHourPattern = #"\b(?:(утром|днем|вечером|ночью)\s+)?(?:примерно\s+)?час(?:а|ов)?\s+в\s+(1[0-2]|[1-9]|час|один|два|три|четыре|пять|шесть|семь|восемь|девять|десять|одиннадцать|двенадцать)\b"#
        if let match = firstMatch(pattern: conversationalHourPattern, in: text),
           let hourRange = Range(match.range(at: 2), in: text),
           let hour = hourValue(for: String(text[hourRange])) {
            let explicitPart = match.range(at: 1).location != NSNotFound
                ? Range(match.range(at: 1), in: text).map { String(text[$0]) }
                : nil
            let contextualPart = explicitPart ?? inferredDayPart(in: text)
            return TimeMatch(
                hour: contextualPart.map { hourAdjusted(hour, for: $0) } ?? hour,
                minute: 0,
                range: match.range,
                belongsToUpcomingNight: contextualPart.map { isNightPart($0) } ?? false
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
            let contextualPart = hour <= 12 ? inferredDayPart(in: text) : nil
            return TimeMatch(
                hour: contextualPart.map { hourAdjusted(hour, for: $0) } ?? hour,
                minute: minute,
                range: match.range,
                belongsToUpcomingNight: contextualPart.map { isNightPart($0) } ?? false
            )
        }

        let spokenHourPattern = #"\bв\s+(час|один|два|три|четыре|пять|шесть|семь|восемь|девять|десять|одиннадцать|двенадцать)(?:\s*час(?:а|ов)?)?\b"#
        if let match = firstMatch(pattern: spokenHourPattern, in: text),
           let hourRange = Range(match.range(at: 1), in: text),
           let hour = hourValue(for: String(text[hourRange])) {
            let contextualPart = inferredDayPart(in: text)
            return TimeMatch(
                hour: contextualPart.map { hourAdjusted(hour, for: $0) } ?? hour,
                minute: 0,
                range: match.range,
                belongsToUpcomingNight: contextualPart.map { isNightPart($0) } ?? false
            )
        }

        let dayParts: [(pattern: String, hour: Int, upcomingNight: Bool)] = [
            (#"\b(?:к|до)\s+начал(?:у|а)\s+работы\b"#, profile.workStartHour, false),
            (#"\b(?:к|до)\s+конц(?:у|а)\s+(?:рабочего\s+дня|работы)\b"#, profile.workEndHour, false),
            (#"\b(?:после|с)\s+работы\b"#, profile.workEndHour, false),
            (#"\bдо\s+обед(?:а|у)?\b"#, profile.lunchStartHour, false),
            (#"\b(?:в|к)\s+обед(?:у)?\b"#, profile.lunchStartHour, false),
            (#"\bпосле\s+обед(?:а|у)?\b"#, profile.lunchEndHour, false),
            (#"\b(?:до|к)\s+вечер(?:а|у)\b"#, profile.eveningHour, false),
            (#"\bутром\b"#, profile.morningHour, false),
            (#"\bднем\b"#, profile.lunchEndHour, false),
            (#"\bвечером\b"#, profile.eveningHour, false),
            (#"\bночью\b"#, profile.nightHour, true)
        ]
        for dayPart in dayParts {
            if let match = firstMatch(pattern: dayPart.pattern, in: text) {
                return TimeMatch(
                    hour: dayPart.hour,
                    minute: 0,
                    range: match.range,
                    belongsToUpcomingNight: dayPart.upcomingNight
                )
            }
        }
        return nil
    }

    private static func parseReminderLeadTime(in text: String) -> ReminderLeadMatch? {
        guard text.range(of: "напом", options: [.caseInsensitive, .diacriticInsensitive]) != nil else {
            return nil
        }

        let pattern = #"\b(?:напомни(?:ть)?(?:\s+мне)?\s+)?за\s+(полчаса|час|неделю|\d+|один|два|три|четыре|пять|шесть|семь|восемь|девять|десять)\s*(минут(?:у|ы)?|час(?:а|ов)?|д(?:ень|ня|ней)|недел(?:ю|и|ь))?(?:\s+(?:до|перед))?(?:\s+напомни(?:ть)?)?\b"#
        guard let match = firstMatch(pattern: pattern, in: text),
              let amountRange = Range(match.range(at: 1), in: text) else { return nil }

        let amountToken = String(text[amountRange])
        if amountToken == "полчаса" {
            return ReminderLeadMatch(minutes: 30, range: match.range)
        }
        if amountToken == "час" {
            return ReminderLeadMatch(minutes: 60, range: match.range)
        }
        if amountToken == "неделю" {
            return ReminderLeadMatch(minutes: 10_080, range: match.range)
        }

        guard let amount = durationAmount(for: amountToken) else { return nil }
        let unit = match.range(at: 2).location != NSNotFound
            ? Range(match.range(at: 2), in: text).map { String(text[$0]) }
            : nil
        let minutes: Int
        if unit?.hasPrefix("минут") == true {
            minutes = amount
        } else if unit?.hasPrefix("д") == true {
            minutes = amount * 1_440
        } else if unit?.hasPrefix("недел") == true {
            minutes = amount * 10_080
        } else {
            minutes = amount * 60
        }

        guard ReminderLeadTime(rawValue: minutes) != nil else { return nil }
        return ReminderLeadMatch(minutes: minutes, range: match.range)
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

    private static func halfHourTargetValue(for token: String) -> Int? {
        let normalizedToken = token.replacingOccurrences(of: " ", with: "")
        if let numericHour = Int(normalizedToken), (1...12).contains(numericHour) {
            return numericHour
        }

        switch normalizedToken {
        case "первого", "первом": return 1
        case "второго", "втором": return 2
        case "третьего", "третьем": return 3
        case "четвертого", "четвертом": return 4
        case "пятого", "пятом": return 5
        case "шестого", "шестом": return 6
        case "седьмого", "седьмом": return 7
        case "восьмого", "восьмом": return 8
        case "девятого", "девятом": return 9
        case "десятого", "десятом": return 10
        case "одиннадцатого", "одиннадцатом": return 11
        case "двенадцатого", "двенадцатом": return 12
        default: return nil
        }
    }

    private static func hourAdjusted(_ hour: Int, for dayPart: String) -> Int {
        switch canonicalDayPart(dayPart) {
        case "day", "evening":
            return hour == 12 ? 12 : hour + 12
        case "night":
            if hour == 12 { return 0 }
            return hour <= 5 ? hour : hour + 12
        default:
            return hour == 12 ? 0 : hour
        }
    }

    private static func canonicalDayPart(_ value: String) -> String {
        if value.contains("обед") { return "day" }
        if value.contains("работ") { return "evening" }
        if value.hasPrefix("дн") { return "day" }
        if value.hasPrefix("вечер") { return "evening" }
        if value.hasPrefix("ноч") { return "night" }
        return "morning"
    }

    private static func inferredDayPart(in text: String) -> String? {
        if text.range(of: #"\bноч(?:ью|и)\b"#, options: .regularExpression) != nil { return "ночью" }
        if text.range(of: #"\b(?:утром|утра)\b"#, options: .regularExpression) != nil { return "утром" }
        if text.range(of: #"\b(?:в|к)\s+обед(?:у)?\b"#, options: .regularExpression) != nil { return "обед" }
        if text.range(of: #"\b(?:вечером|вечера|после\s+работы)\b"#, options: .regularExpression) != nil { return "вечером" }
        return nil
    }

    private static func isNightPart(_ value: String) -> Bool {
        canonicalDayPart(value) == "night"
    }

    private static func durationAmount(for token: String) -> Int? {
        if let numeric = Int(token) { return numeric }
        switch token {
        case "один": return 1
        case "два": return 2
        case "три": return 3
        case "четыре": return 4
        case "пять": return 5
        case "шесть": return 6
        case "семь": return 7
        case "восемь": return 8
        case "девять": return 9
        case "десять": return 10
        default: return nil
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
