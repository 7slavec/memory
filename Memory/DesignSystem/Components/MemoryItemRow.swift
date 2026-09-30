import SwiftUI

struct MemoryItemRow: View {
    let item: Item
    var onToggle: (() -> Void)? = nil
    let onEdit: () -> Void
    var onDelete: (() -> Void)? = nil
    var showsContextMenu = true
    var linkedCount = 0
    var onOpenLinks: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var hovered = false

    private var isOverdue: Bool {
        !item.isEvent && !item.isCompleted && item.dueDate.map { $0 < .now } == true
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            Button(action: onEdit) {
                    HStack(alignment: .top, spacing: 12) {
                        if let date = item.dueDate { timeColumn(date) }
                        copy
                    }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.title), \(item.entryKind.title)\(item.dueDate.map { ", " + MemoryDateFormatting.shortDateTime($0) } ?? "")")
            if linkedCount > 0 {
                Button(action: onOpenLinks ?? onEdit) {
                    MemoryLinkCircle(count: linkedCount, onColor: item.isEvent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("recordLinksBadge")
                .anchorPreference(key: MemoryLinkControlAnchor.self, value: .bounds) { $0 }
            }
        }
        .padding(MemoryDensity.recordPadding)
        .foregroundStyle(item.isEvent ? MemoryTheme.onEventCard : MemoryTheme.accent)
        .background(item.isEvent ? (hovered ? MemoryTheme.eventCardHover : MemoryTheme.eventCard)
                    : (hovered ? MemoryTheme.raised : MemoryTheme.card),
                    in: RoundedRectangle(cornerRadius: MemoryDensity.recordRadius))
        .overlay {
            if isOverdue {
                RoundedRectangle(cornerRadius: MemoryDensity.recordRadius)
                    .strokeBorder(MemoryTheme.danger.opacity(0.45), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .onHover { hovered = $0 }
        .contextMenu {
            if showsContextMenu {
                Button(action: onEdit) { Label("Изменить", systemImage: "pencil") }
                if !item.isEvent, let onToggle {
                    Button(action: onToggle) {
                        Label(item.isCompleted ? "Вернуть" : "Выполнено", systemImage: "checkmark")
                    }
                }
                if let onDelete {
                    Button(role: .destructive, action: onDelete) { Label("Удалить", systemImage: "trash") }
                }
            }
        }
    }

    private func timeColumn(_ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(MemoryDateFormatting.time(date))
                .font(.system(size: MemoryDensity.recordTime, weight: .regular)).tracking(-1.2).monospacedDigit()
            if item.isEvent, let end = item.endDate {
                HStack(spacing: 5) {
                    Capsule().fill(MemoryTheme.onEventCard.opacity(0.3)).frame(width: 2, height: 16)
                    Text("до \(MemoryDateFormatting.time(end))")
                        .font(.system(size: 13)).monospacedDigit()
                }
            }
        }
        .fixedSize()
        .opacity(item.isCompleted ? 0.55 : 1)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: MemoryDensity.recordCopyGap) {
            Text(item.title.isEmpty ? "Без названия" : item.title)
                .font(.system(size: MemoryDensity.recordTitle, weight: .semibold))
                .strikethrough(item.isCompleted)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let details = item.details, !details.isEmpty {
                Text(details).font(.system(size: MemoryDensity.recordBody))
                    .opacity(0.72).lineLimit(2).multilineTextAlignment(.leading)
            }
            if let date = item.dueDate {
                HStack(spacing: 6) {
                    if isOverdue {
                        Circle().fill(MemoryTheme.danger).frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                    }
                    Text(dateLabel(date))
                        .foregroundStyle(isOverdue ? MemoryTheme.danger
                            : item.isEvent ? MemoryTheme.onEventCard.opacity(0.75) : MemoryTheme.secondaryText)
                }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.top, 4).multilineTextAlignment(.leading)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private func dateLabel(_ date: Date) -> String {
        let day = Calendar.current.isDateInToday(date) ? "Сегодня"
            : Calendar.current.isDateInTomorrow(date) ? "Завтра" : MemoryDateFormatting.editorDate(date)
        if item.isCompleted { return "Выполнено · \(day)" }
        if item.isEvent, let end = item.endDate, !Calendar.current.isDate(date, inSameDayAs: end) {
            return "\(day) — \(MemoryDateFormatting.editorDate(end))"
        }
        if !item.isEvent, date < .now { return "Просрочено · \(day)" }
        return day
    }
}
