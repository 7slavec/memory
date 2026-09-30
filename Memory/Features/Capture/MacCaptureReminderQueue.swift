#if os(macOS)
import Foundation

/// Serialize changes to one freshly captured record. Undo must win even when
/// an earlier notification request is still waiting for system authorization.
@MainActor
final class MacCaptureReminderQueue {
    private var jobs: [UUID: (token: UUID, task: Task<Void, Never>)] = [:]

    func update(_ item: Item, onError: @escaping (String) -> Void) {
        let id = item.id
        let previous = jobs[id]?.task
        let token = UUID()
        if item.deletedAt != nil || item.isCompleted || !item.notificationsEnabled || item.dueDate == nil {
            ReminderScheduler.cancel(id: id)
        }
        let task = Task { @MainActor [weak self] in
            await previous?.value
            defer { if self?.jobs[id]?.token == token { self?.jobs[id] = nil } }
            guard let self, self.jobs[id]?.token == token else { return }
            guard item.deletedAt == nil, !item.isCompleted, item.notificationsEnabled, let date = item.dueDate else {
                ReminderScheduler.cancel(id: id)
                return
            }
            do {
                try await ReminderScheduler.schedule(id: id, title: item.title, details: item.details,
                                                     at: date, offsets: item.effectiveReminderOffsets)
            } catch {
                if self.jobs[id]?.token == token, item.deletedAt == nil {
                    onError("Запись сохранена. Уведомление: \(error.localizedDescription)")
                }
            }
            if item.deletedAt != nil || item.isCompleted { ReminderScheduler.cancel(id: id) }
        }
        jobs[id] = (token, task)
    }
}
#endif
