import SwiftUI

/// Figma RecordCard. Pure presentation: persistence and navigation remain with callers.
struct FigmaRecordCard: View {
    let title: String
    let details: String?
    let isEvent: Bool
    let isCompleted: Bool
    let schedule: FigmaRecordSchedule
    let onEdit: () -> Void
    var onToggle: (() -> Void)?
    var onDelete: (() -> Void)?
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .body) private var titleLeading = 4.6

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: FigmaRecordsTokens.cardInset) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.isEmpty ? "Без названия" : title)
                        .font(FigmaRecordsTokens.font(16))
                        .tracking(0.16)
                        .lineSpacing(titleLeading)
                        .padding(.vertical, titleLeading / 2)
                        .foregroundStyle(FigmaRecordsTokens.primary)
                        .strikethrough(isCompleted)
                    if let details, !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(details)
                            .font(FigmaRecordsTokens.font(14, relativeTo: .subheadline))
                            .foregroundStyle(contrast == .increased ? FigmaRecordsTokens.primary : FigmaRecordsTokens.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: hasCompletion ? 32 : 0, alignment: .topLeading)
                .padding(.trailing, hasCompletion ? 56 : 0)
                FigmaScheduleLabel(schedule: schedule)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(FigmaRecordsTokens.cardInset + (isEvent ? 1 : 0))
            .contentShape(RoundedRectangle(cornerRadius: FigmaRecordsTokens.cardRadius))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Открыть запись")
        .accessibilityIdentifier("figma-record-\(title)")
        .background(FigmaRecordsTokens.surface, in: RoundedRectangle(cornerRadius: FigmaRecordsTokens.cardRadius))
        .overlay {
            if isEvent {
                RoundedRectangle(cornerRadius: FigmaRecordsTokens.cardRadius)
                    .strokeBorder(
                        LinearGradient(stops: [
                            .init(color: Color("FigmaRecordsEventBorder"), location: 0),
                            .init(color: Color("FigmaRecordsEventBorder").opacity(0), location: 0.5912)
                        ], startPoint: UnitPoint(x: 0.020776, y: 0.047101),
                           endPoint: UnitPoint(x: 0.732687, y: 1.595588)), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if hasCompletion, let onToggle {
                Button(action: onToggle) {
                    ZStack {
                        Circle().fill(Color("FigmaRecordsCompletion"))
                        Circle().strokeBorder(FigmaRecordsTokens.muted, lineWidth: 1)
                        if isCompleted {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(FigmaRecordsTokens.primary)
                        }
                    }
                    .frame(width: 32, height: 32)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(10)
                .accessibilityLabel(isCompleted ? "Вернуть в активные" : "Отметить выполненным")
                .accessibilityIdentifier("figma-complete-\(title)")
            }
        }
        .contextMenu {
            Button(action: onEdit) { Label("Изменить", systemImage: "pencil") }
            if let onDelete {
                Button(role: .destructive, action: onDelete) { Label("Удалить", systemImage: "trash") }
            }
        }
    }

    private var hasCompletion: Bool { !isEvent && onToggle != nil }
}

struct FigmaScheduleLabel: View {
    let schedule: FigmaRecordSchedule
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(schedule.asset)
                .renderingMode(.template)
                .frame(width: 16, height: 16)
                // The original no-date SVG already contains its 20% opacity.
                .foregroundStyle(schedule.tone == .muted ? FigmaRecordsTokens.primary : schedule.color)
                .accessibilityHidden(true)
            Text(schedule.text)
                .font(FigmaRecordsTokens.font(14, relativeTo: .subheadline))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(contrast == .increased ? FigmaRecordsTokens.primary : schedule.color)
    }
}

struct FigmaRecordSchedule {
    enum Tone: Equatable { case reminder, event, muted, overdue }
    let text: String
    let tone: Tone

    var asset: String {
        switch tone {
        case .event: "FigmaClock"
        case .muted: "FigmaNoDate"
        case .reminder, .overdue: "FigmaBell"
        }
    }

    var color: Color {
        switch tone {
        case .reminder: FigmaRecordsTokens.reminder
        case .event: FigmaRecordsTokens.event
        case .muted: FigmaRecordsTokens.muted
        case .overdue: .red // Existing overdue meaning is retained; no new status design.
        }
    }
}
