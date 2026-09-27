#if DEBUG
import SwiftUI

enum CatalogScheduleModel {
    struct Cell: Identifiable {
        let id: String
        let date: Date?
    }
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "ru_RU")
        value.firstWeekday = 2
        return value
    }
    static var exampleDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 9))!
    }
    static func monthStart(_ date: Date, calendar: Calendar = calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
    static func cells(for month: Date, calendar: Calendar = calendar) -> [Cell] {
        let start = monthStart(month, calendar: calendar)
        let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 0
        let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        return (0..<42).map { position in
            let day = position - offset
            if (0..<count).contains(day), let date = calendar.date(byAdding: .day, value: day, to: start) {
                return Cell(id: "day-\(date.timeIntervalSince1970)", date: date)
            }
            return Cell(id: "empty-\(position)", date: nil)
        }
    }
    static func replacingDay(_ day: Date, in selection: Date, calendar: Calendar = calendar) -> Date {
        let time = calendar.dateComponents([.hour, .minute], from: selection)
        return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) ?? selection
    }
    static func time(_ text: String, on day: Date, calendar: Calendar = calendar) -> Date? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return calendar.date(bySettingHour: h, minute: m, second: 0, of: day)
    }
}

struct CatalogCalendar: View {
    @Environment(\.colorScheme) private var scheme
    @State private var month: Date
    let selection: Date
    let onChoose: (Date) -> Void
    init(selection: Date, onChoose: @escaping (Date) -> Void) {
        self.selection = selection
        self.onChoose = onChoose
        // A fresh picker opens at the selected month; subsequent browsing is local.
        _month = State(initialValue: CatalogScheduleModel.monthStart(selection))
    }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                CatalogIconButton(symbol: "chevron.left", label: "Предыдущий месяц", size: .small) { move(-1) }
                Spacer(minLength: 0)
                Text(month.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "ru_RU"))))
                    .font(.headline).textCase(.none)
                Spacer(minLength: 0)
                CatalogIconButton(symbol: "chevron.right", label: "Следующий месяц", size: .small) { move(1) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"], id: \.self) { day in
                    Text(day).font(CatalogType.caption).foregroundStyle(palette.secondary.color).frame(height: 32)
                }
                ForEach(CatalogScheduleModel.cells(for: month)) { cell in
                    if let date = cell.date {
                        let selected = CatalogScheduleModel.calendar.isDate(date, inSameDayAs: selection)
                        Button { onChoose(CatalogScheduleModel.replacingDay(date, in: selection)) } label: {
                            Text("\(CatalogScheduleModel.calendar.component(.day, from: date))")
                                .font(.system(.title3, design: .rounded, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? palette.onPrimary.color : palette.text.color)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background {
                                    if selected { Circle().fill(palette.primaryFill.color).frame(width: 40, height: 40) }
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "ru_RU"))))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    } else {
                        Color.clear.frame(height: 44).accessibilityHidden(true)
                    }
                }
            }
        }
        .foregroundStyle(palette.text.color)
        .padding(.vertical, 16)
        .padding(.horizontal, 4)
        .background(palette.surface.color, in: RoundedRectangle(cornerRadius: 20))
    }
    private var palette: CatalogPalette { .init(dark: scheme == .dark) }
    private func move(_ offset: Int) {
        month = CatalogScheduleModel.calendar.date(byAdding: .month, value: offset, to: month) ?? month
    }
}

struct CatalogTime: View {
    @Environment(\.colorScheme) private var scheme
    @State private var selection: Date
    @State private var typed: String
    @State private var invalid = false
    let onChoose: (Date) -> Void
    init(selection: Date, onChoose: @escaping (Date) -> Void) {
        _selection = State(initialValue: selection)
        _typed = State(initialValue: selection.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "ru_RU"))))
        self.onChoose = onChoose
    }
    var body: some View {
        VStack(spacing: 16) {
#if os(iOS)
            DatePicker("Время", selection: $selection, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel).labelsHidden().frame(height: 180)
#else
            TextField("ЧЧ:ММ", text: $typed)
                .textFieldStyle(.plain).font(CatalogType.largeTitle.monospacedDigit())
                .multilineTextAlignment(.center).padding(16)
                .background(palette.inset.color, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("Время").onSubmit(apply)
#endif
            if invalid { Text("Введите время от 00:00 до 23:59").font(.caption).foregroundStyle(palette.danger.color) }
            Button("Готово", action: apply).buttonStyle(CatalogButtonStyle(tone: .primary))
        }
        .padding(24).foregroundStyle(palette.text.color)
        .background(palette.surface.color, in: RoundedRectangle(cornerRadius: 20))
        .environment(\.locale, Locale(identifier: "ru_RU"))
    }
    private var palette: CatalogPalette { .init(dark: scheme == .dark) }
    private func apply() {
#if os(macOS)
        guard let date = CatalogScheduleModel.time(typed, on: selection) else { invalid = true; return }
        selection = date
        invalid = false
#endif
        onChoose(selection)
    }
}

enum CatalogPicker: String, Identifiable { case date, time; var id: Self { self } }

struct CatalogScheduleDemo: View {
    @State private var selection = CatalogScheduleModel.exampleDate
    @State private var picker: CatalogPicker?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                CatalogChip(title: selection.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "ru_RU"))), action: { picker = .date })
                    .accessibilityIdentifier("catalog-open-date")
                CatalogChip(title: selection.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "ru_RU"))), action: { picker = .time })
                    .accessibilityIdentifier("catalog-open-time")
                Spacer(minLength: 0)
            }
            CatalogCalendar(selection: selection) { selection = $0 }
            CatalogTime(selection: selection) { selection = $0 }.id(selection)
        }
#if os(iOS)
        .sheet(item: $picker) { target in
            pickerContent(target)
                .presentationDetents([.height(target == .date ? 420 : 320)])
                .presentationDragIndicator(.visible)
        }
#else
        .popover(item: $picker) { target in pickerContent(target).frame(width: 360) }
#endif
    }
    @ViewBuilder private func pickerContent(_ target: CatalogPicker) -> some View {
        if target == .date {
            CatalogCalendar(selection: selection) { selection = $0; picker = nil }
        } else {
            CatalogTime(selection: selection) { selection = $0; picker = nil }
        }
    }
}
#endif
