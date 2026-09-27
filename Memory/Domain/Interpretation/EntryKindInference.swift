import Foundation

enum EntryKindInference {
    static func infer(from text: String, hasDate: Bool) -> EntryKind? {
        let normalized = text
            .lowercased(with: Locale(identifier: "ru_RU"))
            .replacingOccurrences(of: "ё", with: "е")
        let hasExplicitRange = normalized.contains(" с ")
            && (normalized.contains(" до ")
                || normalized.contains(" по ")
                || normalized.contains("—")
                || normalized.contains("–"))
        let actionMarkers = [
            "надо ", "нужно ", "не забыть", "напомни", "напомнить"
        ]
        let actionStems = [
            "купит", "сдела", "отправ", "позвон", "напис", "забрат",
            "оплат", "провер", "подготов", "подат", "заказ", "записат",
            "зайти", "сходить", "получит", "вернут", "доработ", "закончит"
        ]
        let eventPhrases = [
            "встреча", "встречу", "встретиться", "созвон", "вебинар",
            "концерт", "прием", "трениров", "занят", "лекци", "урок",
            "сеанс", "бронь", "перелет", "рейс", "поездка", "отпуск",
            "конференц", "мероприят", "собеседован", "экзамен",
            "день рождения", "годовщина"
        ]
        let hasAction = actionMarkers.contains(where: normalized.contains)
            || actionStems.contains(where: normalized.contains)
        let hasEventNoun = eventPhrases.contains(where: normalized.contains)

        if hasAction && !normalized.contains("встретиться") {
            return .reminder
        }
        if hasEventNoun {
            return .event
        }
        if hasDate && hasExplicitRange {
            return .event
        }
        return nil
    }
}
