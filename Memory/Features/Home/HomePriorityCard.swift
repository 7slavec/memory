import SwiftUI

struct HomePriorityCard: View {
    let item: Item
    let isOverdue: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    var linkedCount = 0
    var onOpenLinkedRecord: ((Item) -> Void)? = nil
    @State private var showsLinks = false

    var body: some View {
        HStack(spacing: 14) {
            if !item.isEvent {
                Button(action: onToggle) {
                    Image(systemName: "circle")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(isOverdue ? Color.red.opacity(0.8) : Color.secondary.opacity(0.65))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Отметить выполненным")
            }

            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title.isEmpty ? "Без названия" : item.title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    if let details = item.details {
                        Text(details)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)
                    }

                    if item.isEvent {
                        Text(dateLabel)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(MemoryTheme.warm)
                    } else {
                        Label(dateLabel, systemImage: item.notificationsEnabled ? "bell" : "calendar")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(isOverdue ? Color.red : MemoryTheme.accent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if linkedCount > 0 {
                Button { showsLinks = true } label: {
                    MemoryLinkBadge(count: linkedCount)
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .recordLinksPopup(item: item, isPresented: $showsLinks) { linked in
                    showsLinks = false
                    onOpenLinkedRecord?(linked)
                }
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [
                    item.isEvent
                        ? MemoryTheme.warm.opacity(0.22)
                        : isOverdue ? Color.red.opacity(0.09) : MemoryTheme.accent.opacity(0.08),
                    MemoryTheme.card
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    item.isEvent
                        ? MemoryTheme.warm.opacity(0.28)
                        : isOverdue ? Color.red.opacity(0.14) : MemoryTheme.accent.opacity(0.1),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.05), radius: 14, y: 7)
    }

    private var dateLabel: String {
        guard let date = item.dueDate else { return "Без срока" }
        if item.isEvent {
            let start = MemoryDateFormatting.time(date)
            if let endDate = item.endDate {
                let end = MemoryDateFormatting.time(endDate)
                if date <= .now, endDate > .now { return "Сейчас · до \(end)" }
                if Calendar.current.isDateInToday(date) { return "Сегодня · \(start)–\(end)" }
                if Calendar.current.isDateInTomorrow(date) { return "Завтра · \(start)–\(end)" }
                return "\(MemoryDateFormatting.shortDate(date)) · \(start)–\(end)"
            }
            if Calendar.current.isDateInToday(date) { return "Сегодня · \(start)" }
            if Calendar.current.isDateInTomorrow(date) { return "Завтра · \(start)" }
            return "\(MemoryDateFormatting.shortDate(date)) · \(start)"
        }
        let time = MemoryDateFormatting.time(date)
        if isOverdue { return "Просрочено · \(time)" }
        if Calendar.current.isDateInToday(date) { return "Сегодня · \(time)" }
        if Calendar.current.isDateInTomorrow(date) { return "Завтра · \(time)" }
        return MemoryDateFormatting.shortDateTime(date)
    }
}
