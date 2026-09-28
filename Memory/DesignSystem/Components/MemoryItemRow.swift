import SwiftUI

struct MemoryItemRow: View {
    let item: Item
    var onToggle: (() -> Void)? = nil
    let onEdit: () -> Void
    var onDelete: (() -> Void)? = nil
    var showsContextMenu = true

    var body: some View {
        HStack(spacing: 14) {
            if !item.isEvent, let onToggle {
                Button(action: onToggle) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(item.isCompleted ? MemoryTheme.accent : Color.secondary.opacity(0.65))
                }
                .buttonStyle(.plain)
            }
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title.isEmpty ? "Без названия" : item.title)
                        .font(.body.weight(.medium)).foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                        .strikethrough(item.isCompleted).multilineTextAlignment(.leading)
                    if let details = item.details {
                        Text(details)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    if item.isEvent {
                        Text(dateLabel)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(dateColor)
                    } else {
                        Label(dateLabel, systemImage: dateIcon)
                            .font(.caption)
                            .foregroundStyle(dateColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 15)
        .memoryEntryCard(isEvent: item.isEvent)
        .contextMenu {
            if showsContextMenu {
                Button(action: onEdit) { Label("Изменить", systemImage: "pencil") }
                if let onDelete {
                    Button(role: .destructive, action: onDelete) { Label("Удалить", systemImage: "trash") }
                }
            }
        }
    }

    private var dateLabel: String {
        if item.isEvent, let startDate = item.dueDate {
            let start = MemoryDateFormatting.time(startDate)
            if let endDate = item.endDate {
                let end = MemoryDateFormatting.time(endDate)
                if startDate <= .now, endDate > .now { return "Сейчас · до \(end)" }
                if Calendar.current.isDateInToday(startDate) { return "Сегодня · \(start)–\(end)" }
                if Calendar.current.isDateInTomorrow(startDate) { return "Завтра · \(start)–\(end)" }
                return "\(MemoryDateFormatting.shortDate(startDate)) · \(start)–\(end)"
            }
            if Calendar.current.isDateInToday(startDate) { return "Сегодня · \(start)" }
            if Calendar.current.isDateInTomorrow(startDate) { return "Завтра · \(start)" }
            return "\(MemoryDateFormatting.shortDate(startDate)) · \(start)"
        }
        if item.isCompleted {
            guard let completedAt = item.completedAt else { return "Выполнено" }
            return "Выполнено · \(MemoryDateFormatting.shortDate(completedAt))"
        }
        guard let date = item.dueDate else { return "Без срока" }
        if date < .now { return "Просрочено · \(MemoryDateFormatting.time(date))" }
        if Calendar.current.isDateInToday(date) { return "Сегодня · \(MemoryDateFormatting.time(date))" }
        if Calendar.current.isDateInTomorrow(date) { return "Завтра · \(MemoryDateFormatting.time(date))" }
        return MemoryDateFormatting.shortDateTime(date)
    }
    private var dateIcon: String {
        if item.isEvent { return "calendar" }
        if item.isCompleted { return "checkmark" }
        guard item.dueDate != nil else { return "tray" }
        return item.notificationsEnabled ? "bell" : "calendar"
    }
    private var dateColor: Color {
        guard !item.isCompleted, let date = item.dueDate else { return .secondary }
        if item.isEvent, let endDate = item.endDate {
            return endDate < .now ? .secondary : MemoryTheme.warm
        }
        if item.isEvent { return date < .now ? .secondary : MemoryTheme.warm }
        return date < .now ? .red : MemoryTheme.accent
    }
}
