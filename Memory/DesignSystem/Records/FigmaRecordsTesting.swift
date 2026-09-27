#if DEBUG
import Foundation

// Reuses the existing in-memory, offline test host. Never reads the user's store.
enum FigmaRecordsTesting {
    @MainActor static func items() -> [Item] {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let reminder = Item(title: "Отправить портфолио", dueDate: tomorrow)
        reminder.details = "Добавить последние проекты"
        reminder.setReminderOffsets([])
        let event = Item(title: "Собрание по маркетингу с Тимуром и Натальей в офисе", dueDate: tomorrow)
        event.details = "Подготовить недельный отчет к собранию"
        event.entryKind = .event
        event.endDate = tomorrow.addingTimeInterval(7200)
        event.setReminderOffsets([])
        let inbox = Item(title: "Подумать над идеей подарка")
        inbox.setReminderOffsets([])
        return [reminder, event, inbox]
    }
}
#endif
