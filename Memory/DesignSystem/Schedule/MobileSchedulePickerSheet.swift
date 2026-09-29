import SwiftUI

#if os(iOS)
struct MobileSchedulePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Date
    @State private var visibleMonth: Date
    @State private var didResolve = false

    let target: SchedulePickerTarget
    let minimumDate: Date?
    let onCommit: (Date) -> Void

    init(
        target: SchedulePickerTarget,
        selection: Date,
        minimumDate: Date?,
        onCommit: @escaping (Date) -> Void
    ) {
        self.target = target
        self.minimumDate = minimumDate
        self.onCommit = onCommit
        _selection = State(initialValue: selection)
        _visibleMonth = State(initialValue: Self.startOfMonth(for: selection))
    }

    var body: some View {
        VStack(spacing: 0) {
            if target.editsDate {
                pickerHeader
                Divider()
            }

            picker
                .transaction { transaction in
                    transaction.animation = nil
                }
        }
        .background(MemoryTheme.card)
        .environment(\.locale, Locale(identifier: "ru_RU"))
        .onDisappear {
            guard !didResolve else { return }
            didResolve = true
            onCommit(selection)
        }
    }

    private var pickerHeader: some View {
        HStack(spacing: 12) {
            monthButton(systemName: "chevron.left", offset: -1)

            Spacer()

            Text(monthTitle)
                .font(.headline)

            Spacer()

            monthButton(systemName: "chevron.right", offset: 1)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    @ViewBuilder
    private var picker: some View {
        if target.editsDate {
            LazyVGrid(columns: calendarColumns, spacing: 4) {
                ForEach(weekdayTitles, id: \.self) { title in
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(height: 22)
                }

                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        calendarDay(day)
                    } else {
                        Color.clear.frame(height: 42)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        } else if let minimumDate {
            DatePicker(
                "Время",
                selection: $selection,
                in: minimumDate...,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .frame(height: 206)
            .clipped()
            .padding(.horizontal, 12)
        } else {
            DatePicker(
                "Время",
                selection: $selection,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .frame(height: 206)
            .clipped()
            .padding(.horizontal, 12)
        }
    }

    private func monthButton(systemName: String, offset: Int) -> some View {
        Button {
            moveMonth(by: offset)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.055))
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(offset < 0 ? "Предыдущий месяц" : "Следующий месяц")
    }

    private func calendarDay(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(day)
        let isAvailable = minimumDate.map {
            calendar.startOfDay(for: day) >= calendar.startOfDay(for: $0)
        } ?? true

        return Button {
            guard isAvailable else { return }
            selectAndDismiss(day)
        } label: {
            ZStack {
                if isSelected {
                    Circle().fill(MemoryTheme.accent)
                } else if isToday {
                    Circle().stroke(MemoryTheme.accent.opacity(0.65), lineWidth: 1.5)
                }

                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 18, weight: isSelected || isToday ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(isSelected ? MemoryTheme.onAccent : Color.primary)
                    .opacity(isAvailable ? 1 : 0.24)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
    }

    private let calendarColumns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdayTitles = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "ru_RU")
        value.firstWeekday = 2
        return value
    }

    private var monthDays: [Date?] {
        let start = Self.startOfMonth(for: visibleMonth)
        guard let dayRange = calendar.range(of: .day, in: .month, for: start) else { return [] }
        let weekday = calendar.component(.weekday, from: start)
        let leadingEmptyDays = (weekday - calendar.firstWeekday + 7) % 7
        var result = Array<Date?>(repeating: nil, count: leadingEmptyDays)
        result.append(contentsOf: dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: start)
        })
        result.append(contentsOf: Array<Date?>(repeating: nil, count: max(0, 42 - result.count)))
        return result
    }

    private var monthTitle: String {
        let value = Self.monthFormatter.string(from: visibleMonth)
        return value.prefix(1).uppercased() + value.dropFirst()
    }

    private func moveMonth(by value: Int) {
        guard let month = calendar.date(byAdding: .month, value: value, to: visibleMonth) else { return }
        withAnimation(.easeInOut(duration: 0.14)) {
            visibleMonth = Self.startOfMonth(for: month)
        }
    }

    private func selectAndDismiss(_ day: Date) {
        let time = calendar.dateComponents([.hour, .minute, .second], from: selection)
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        let updatedSelection = calendar.date(from: components) ?? selection
        selection = updatedSelection
        didResolve = true
        onCommit(updatedSelection)
        dismiss()
    }

    private static func startOfMonth(for date: Date) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()
}
#endif
