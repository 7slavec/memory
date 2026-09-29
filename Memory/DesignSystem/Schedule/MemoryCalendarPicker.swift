import SwiftUI

struct MemoryCalendarPicker: View {
    @Binding var selection: Date
    @Binding var isPresented: Bool
    @State private var visibleMonth: Date
    let minimumDate: Date?
    let width: CGFloat

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdayTitles = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    init(selection: Binding<Date>, isPresented: Binding<Bool>, minimumDate: Date? = nil, width: CGFloat = 340) {
        self.minimumDate = minimumDate
        self.width = width
        _selection = selection
        _isPresented = isPresented
        _visibleMonth = State(initialValue: Self.startOfMonth(for: selection.wrappedValue))
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button { moveMonth(by: -1) } label: {
                    monthArrow("chevron.left")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Предыдущий месяц")

                Spacer()

                Text(monthTitle)
                    .font(.system(size: 16, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)

                Spacer()

                Button { moveMonth(by: 1) } label: {
                    monthArrow("chevron.right")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Следующий месяц")
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdayTitles, id: \.self) { title in
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(height: 24)
                }

                ForEach(monthSlots) { slot in
                    let day = slot.date
                    if let day {
                        calendarDay(day)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }


        }
        .padding(16)
        .frame(width: width)
        .background(MemoryTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

    }

    private func monthArrow(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .frame(width: 32, height: 32)
            .background(MemoryTheme.raised, in: Circle())
            .frame(width: 44, height: 44).contentShape(Rectangle())
    }

    private func calendarDay(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(day)

        let available = minimumDate.map { calendar.startOfDay(for: day) >= calendar.startOfDay(for: $0) } ?? true
        return Button {
            selectDay(day)
            isPresented = false
        } label: {
            ZStack {
                if isSelected {
                    Circle().fill(MemoryTheme.highlight)
                } else if isToday {
                    Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1)
                }

                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 21, weight: isSelected || isToday ? .semibold : .regular))
                    .foregroundStyle(isSelected ? MemoryTheme.onHighlight : Color.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.25)
        .accessibilityLabel(MemoryDateFormatting.editorDate(day))
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ru_RU")
        calendar.firstWeekday = 2
        return calendar
    }

    private var monthSlots: [MemoryCalendarGrid.Slot] {
        MemoryCalendarGrid.slots(for: visibleMonth, calendar: calendar)
    }

    private var monthTitle: String {
        let value = Self.monthFormatter.string(from: visibleMonth)
        return value.prefix(1).uppercased() + value.dropFirst()
    }

    private func moveMonth(by value: Int) {
        guard let month = calendar.date(byAdding: .month, value: value, to: visibleMonth) else { return }
        visibleMonth = Self.startOfMonth(for: month)
    }

    private func selectDay(_ day: Date) {
        let time = calendar.dateComponents([.hour, .minute, .second], from: selection)
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        if let updatedDate = calendar.date(from: components) {
            selection = updatedDate
        }
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

/// Fixed-size month layout, independent of presentation and safe to unit-test.
enum MemoryCalendarGrid {
    struct Slot: Identifiable {
        let id: Date
        let date: Date?
    }

    static func slots(for month: Date, calendar: Calendar) -> [Slot] {
        guard let start = calendar.dateInterval(of: .month, for: month)?.start,
              let dayRange = calendar.range(of: .day, in: .month, for: start) else { return [] }
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        return (0..<42).compactMap { slot in
            guard let date = calendar.date(byAdding: .day, value: slot - leading, to: start) else { return nil }
            let day = slot - leading + 1
            return Slot(id: date, date: dayRange.contains(day) ? date : nil)
        }
    }
}
