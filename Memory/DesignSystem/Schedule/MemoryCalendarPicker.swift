import SwiftUI

struct MemoryCalendarPicker: View {
    @Binding var selection: Date
    @Binding var isPresented: Bool
    @State private var visibleMonth: Date
    let minimumDate: Date?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdayTitles = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    init(selection: Binding<Date>, isPresented: Binding<Bool>, minimumDate: Date? = nil) {
        self.minimumDate = minimumDate
        _selection = selection
        _isPresented = isPresented
        _visibleMonth = State(initialValue: Self.startOfMonth(for: selection.wrappedValue))
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button { moveMonth(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                        .background(Color.primary.opacity(0.055))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                Text(monthTitle)
                    .font(.headline)

                Spacer()

                Button { moveMonth(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.055))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdayTitles, id: \.self) { title in
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(height: 24)
                }

                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        calendarDay(day)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }


        }
        .padding(14)
        .frame(width: 336)
        .background(MemoryTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

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

    private var monthDays: [Date?] {
        let start = Self.startOfMonth(for: visibleMonth)
        guard let dayRange = calendar.range(of: .day, in: .month, for: start) else { return [] }
        let weekday = calendar.component(.weekday, from: start)
        let leadingEmptyDays = (weekday - calendar.firstWeekday + 7) % 7
        var result = Array<Date?>(repeating: nil, count: leadingEmptyDays)

        result.append(contentsOf: dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: start)
        })
        return result
    }

    private var monthTitle: String {
        let value = Self.monthFormatter.string(from: visibleMonth)
        return value.prefix(1).uppercased() + value.dropFirst()
    }

    private func moveMonth(by value: Int) {
        guard let month = calendar.date(byAdding: .month, value: value, to: visibleMonth) else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            visibleMonth = Self.startOfMonth(for: month)
        }
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
