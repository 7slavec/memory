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
        if item.isEvent, item.endDate != nil {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                row(at: context.date)
            }
        } else {
            row(at: .now)
        }
    }

    private func row(at now: Date) -> some View {
        let active = item.isActiveEvent(at: now)
        return HStack(alignment: .bottom, spacing: 4) {
            Button(action: onEdit) {
                    HStack(alignment: .top, spacing: 12) {
                        if let date = item.dueDate { timeColumn(date, now: now) }
                        copy
                    }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rowAccessibilityLabel(at: now))
            .accessibilityIdentifier(active ? "activeEventCard" : "recordCard")
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
            if active {
                ActiveEventPulse(cornerRadius: MemoryDensity.recordRadius)
                    .allowsHitTesting(false)
            }
        }
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

    private func timeColumn(_ date: Date, now: Date) -> some View {
        let remaining = item.endDate.flatMap { item.isActiveEvent(at: now) ? EventActivity.remaining(until: $0, at: now) : nil }
        return VStack(alignment: .leading, spacing: 7) {
            if let remaining {
                Text(remaining.display)
                    .font(.system(size: remaining.hasDays ? MemoryDensity.recordTime - 7 : MemoryDensity.recordTime,
                                  weight: .medium, design: .rounded))
                    .tracking(remaining.hasDays ? -0.8 : -1.2)
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.85)
                    .accessibilityLabel(remaining.accessibilityText)
                    .modifier(ActiveEventCounterPulse())
            } else {
                Text(MemoryDateFormatting.time(date))
                    .font(.system(size: MemoryDensity.recordTime, weight: .regular)).tracking(-1.2).monospacedDigit()
            }
            if item.isEvent, let end = item.endDate {
                HStack(spacing: 5) {
                    Capsule().fill(MemoryTheme.onEventCard.opacity(0.3)).frame(width: 2, height: 16)
                    Text(remaining == nil ? "до \(MemoryDateFormatting.time(end))"
                         : "\(MemoryDateFormatting.time(date))–\(MemoryDateFormatting.time(end))")
                        .font(.system(size: remaining == nil ? 13 : 11)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
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

    private func rowAccessibilityLabel(at now: Date) -> String {
        var label = "\(item.title), \(item.entryKind.title)"
        if let date = item.dueDate { label += ", \(MemoryDateFormatting.shortDateTime(date))" }
        if item.isActiveEvent(at: now), let end = item.endDate,
           let remaining = EventActivity.remaining(until: end, at: now) {
            label += ", \(remaining.accessibilityText)"
        }
        return label
    }
}
