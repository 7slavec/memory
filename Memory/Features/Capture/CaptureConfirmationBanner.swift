import SwiftUI

struct CaptureConfirmationBanner: View {
    let title: String
    let dueDate: Date?
    let onEdit: () -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.body.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Label(dueSummary, systemImage: dueDate == nil ? "tray" : "calendar")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(spacing: 10) {
                Button(action: onEdit) {
                    Label("Изменить", systemImage: "pencil")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Изменить")
                .accessibilityLabel("Изменить добавленную задачу")

                Button(action: onUndo) {
                    Label("Отменить", systemImage: "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Отменить добавление")
                .accessibilityLabel("Отменить добавление")
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 24, y: 10)
    }

    private var dueSummary: String {
        guard let dueDate else { return "Без срока" }
        return Self.compactDate(dueDate)
    }

    private static func compactDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "Сегодня · \(time)" }
        if calendar.isDateInTomorrow(date) { return "Завтра · \(time)" }
        return compactDateFormatter.string(from: date)
    }

    private static let compactDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter
    }()
}
