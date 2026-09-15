import SwiftUI

struct ItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let item: Item
    let onSave: (String, Date?, Bool) -> Void
    let onDelete: () -> Void
    @State private var title: String
    @State private var hasSchedule: Bool
    @State private var scheduledDate: Date
    @State private var notificationsEnabled: Bool
#if os(macOS)
    @State private var isCalendarPresented = false
    @State private var isTimePickerPresented = false
#endif

    init(
        item: Item,
        onSave: @escaping (String, Date?, Bool) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: item.title)
        _hasSchedule = State(initialValue: item.dueDate != nil)
        _scheduledDate = State(initialValue: item.dueDate ?? Self.defaultScheduledDate)
        _notificationsEnabled = State(initialValue: item.notificationsEnabled)
    }

    var body: some View {
#if os(macOS)
        macEditor
#else
        mobileEditor
#endif
    }

#if os(iOS)
    private var mobileEditor: some View {
        NavigationStack {
            Form {
                Section("Запись") {
                    TextField("Что нужно запомнить?", text: $title, axis: .vertical).lineLimit(2...6)
                }
                Section("Планирование") {
                    Toggle("Добавить дату", isOn: $hasSchedule)
                    if hasSchedule {
                        DatePicker("Дата", selection: $scheduledDate, displayedComponents: .date)
                        DatePicker("Время", selection: $scheduledDate, displayedComponents: .hourAndMinute)
                    }
                }
                Section("Уведомление") {
                    Toggle("Прислать уведомление", isOn: $notificationsEnabled)
                        .disabled(!hasSchedule)
                    if !hasSchedule {
                        Text("Сначала добавьте дату и время")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button("Удалить запись", role: .destructive) { onDelete(); dismiss() }
                }
            }
            .navigationTitle("Изменить")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Отмена")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveAndDismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Сохранить")
                    .disabled(trimmedTitle.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onChange(of: hasSchedule) { _, isScheduled in
            if !isScheduled { notificationsEnabled = false }
        }
    }
#endif

#if os(macOS)
    private var macEditor: some View {
        VStack(spacing: 0) {
            macHeader

            Divider()

            VStack(spacing: 16) {
                macTitleCard
                macScheduleCard
                macNotificationCard
            }
            .padding(24)
            .frame(maxHeight: .infinity, alignment: .top)

            Divider()

            macFooter
        }
        .frame(width: 560, height: 600)
        .background(MemoryTheme.background)
        .overlay { macPickerOverlay }
        .animation(.easeInOut(duration: 0.16), value: isCalendarPresented)
        .animation(.easeInOut(duration: 0.16), value: isTimePickerPresented)
    }

    @ViewBuilder
    private var macPickerOverlay: some View {
        if isCalendarPresented || isTimePickerPresented {
            ZStack {
                Color.black.opacity(0.34)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isCalendarPresented = false
                        isTimePickerPresented = false
                    }

                if isCalendarPresented {
                    MemoryCalendarPicker(
                        selection: $scheduledDate,
                        isPresented: $isCalendarPresented
                    )
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                } else {
                    MemoryTimePicker(
                        selection: $scheduledDate,
                        isPresented: $isTimePickerPresented
                    )
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
        }
    }

    private var macHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MemoryTheme.accent.opacity(0.14))
                    .frame(width: 48, height: 48)

                Image(systemName: "square.and.pencil")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(MemoryTheme.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Редактировать запись")
                    .font(.title3.weight(.semibold))

                Text("Настройте запись, дату и уведомление")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var macTitleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Запись", systemImage: "text.alignleft")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("Что нужно запомнить?", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .lineLimit(3...5)
                .padding(14)
                .background(Color.primary.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                }
        }
        .padding(18)
        .memoryCard()
    }

    private var macScheduleCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(MemoryTheme.accent.opacity(0.13))
                        .frame(width: 34, height: 34)

                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MemoryTheme.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Планирование")
                        .font(.body.weight(.medium))
                    Text(hasSchedule ? scheduleSummary : "Без даты и времени")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $hasSchedule)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            if hasSchedule {
                Divider()

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Дата")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        Button {
                            isTimePickerPresented = false
                            isCalendarPresented.toggle()
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "calendar")
                                    .foregroundStyle(MemoryTheme.accent)
                                Text(macDateLabel)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(Color.primary.opacity(0.045))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Время")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        Button {
                            isCalendarPresented = false
                            isTimePickerPresented.toggle()
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "clock")
                                    .foregroundStyle(MemoryTheme.accent)

                                Text(scheduledDate.formatted(date: .omitted, time: .shortened))
                                    .font(.body.monospacedDigit())

                                Spacer(minLength: 4)

                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(Color.primary.opacity(0.045))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: 150, alignment: .leading)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .memoryCard()
        .animation(.easeInOut(duration: 0.18), value: hasSchedule)
        .onChange(of: hasSchedule) { _, isScheduled in
            if !isScheduled { notificationsEnabled = false }
        }
    }

    private var macNotificationCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(MemoryTheme.accent.opacity(0.13))
                    .frame(width: 34, height: 34)

                Image(systemName: notificationsEnabled ? "bell.fill" : "bell.slash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MemoryTheme.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Уведомление")
                    .font(.body.weight(.medium))
                Text(notificationSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $notificationsEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!hasSchedule)
        }
        .padding(18)
        .memoryCard()
    }

    private var macFooter: some View {
        HStack(spacing: 12) {
            Button(role: .destructive) {
                onDelete()
                dismiss()
            } label: {
                Label("Удалить", systemImage: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)

            Spacer()

            Button("Отмена") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Сохранить") {
                saveAndDismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(MemoryTheme.accent)
            .keyboardShortcut(.defaultAction)
            .disabled(trimmedTitle.isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
#endif

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var scheduleSummary: String {
#if os(macOS)
        "\(macDateLabel) · \(scheduledDate.formatted(date: .omitted, time: .shortened))"
#else
        scheduledDate.formatted(date: .abbreviated, time: .shortened)
#endif
    }

#if os(macOS)
    private var macDateLabel: String {
        Self.macDateFormatter.string(from: scheduledDate)
    }

    private static let macDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter
    }()
#endif

    private var notificationSummary: String {
        guard hasSchedule else { return "Сначала добавьте дату и время" }
        return notificationsEnabled ? "Придёт в указанное время" : "Задача останется в плане без сигнала"
    }

    private func saveAndDismiss() {
        onSave(
            trimmedTitle,
            hasSchedule ? scheduledDate : nil,
            hasSchedule && notificationsEnabled
        )
        dismiss()
    }

    private static var defaultScheduledDate: Date {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) else { return .now.addingTimeInterval(3600) }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

#if os(macOS)
private struct MemoryCalendarPicker: View {
    @Binding var selection: Date
    @Binding var isPresented: Bool
    @State private var visibleMonth: Date

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdayTitles = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    init(selection: Binding<Date>, isPresented: Binding<Bool>) {
        _selection = selection
        _isPresented = isPresented
        _visibleMonth = State(initialValue: Self.startOfMonth(for: selection.wrappedValue))
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button { moveMonth(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 30, height: 30)
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
                        Color.clear.frame(height: 34)
                    }
                }
            }

            Divider()

            HStack {
                Button("Сегодня") {
                    selectDay(.now)
                    visibleMonth = Self.startOfMonth(for: .now)
                }
                .buttonStyle(.plain)
                .foregroundStyle(MemoryTheme.accent)

                Spacer()

                Button("Готово") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .tint(MemoryTheme.accent)
            }
        }
        .padding(18)
        .frame(width: 340)
        .background(MemoryTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.32), radius: 30, y: 16)
    }

    private func calendarDay(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(day)

        return Button {
            selectDay(day)
        } label: {
            ZStack {
                if isSelected {
                    Circle().fill(MemoryTheme.accent)
                } else if isToday {
                    Circle().stroke(MemoryTheme.accent.opacity(0.65), lineWidth: 1.5)
                }

                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 13, weight: isSelected || isToday ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
            }
            .frame(width: 34, height: 34)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
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

private struct MemoryTimePicker: View {
    @Binding var selection: Date
    @Binding var isPresented: Bool
    @State private var typedTime: String
    @State private var hasInvalidTime = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    private let timeOptions = [
        8 * 60, 9 * 60, 9 * 60 + 30, 10 * 60,
        12 * 60, 13 * 60, 14 * 60, 15 * 60,
        17 * 60, 18 * 60, 19 * 60, 20 * 60,
        21 * 60, 22 * 60, 23 * 60, 23 * 60 + 30
    ]

    init(selection: Binding<Date>, isPresented: Binding<Bool>) {
        _selection = selection
        _isPresented = isPresented
        _typedTime = State(initialValue: Self.timeString(from: selection.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Выберите время")
                        .font(.headline)
                    Text("Одним нажатием или введите точное")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.055))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Быстрый выбор")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(timeOptions, id: \.self) { minutes in
                        timeButton(minutes)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                Text("Точное время")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    TextField("ЧЧ:ММ", text: $typedTime)
                        .textFieldStyle(.plain)
                        .font(.body.monospacedDigit())
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(Color.primary.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(hasInvalidTime ? Color.red : Color.primary.opacity(0.07), lineWidth: 1)
                        }
                        .onSubmit(applyTypedTime)
                        .onChange(of: typedTime) { _, _ in hasInvalidTime = false }

                    Button("Применить") {
                        applyTypedTime()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MemoryTheme.accent)
                }

                if hasInvalidTime {
                    Text("Введите время в формате 09:30")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(18)
        .frame(width: 340)
        .background(MemoryTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.32), radius: 30, y: 16)
    }

    private func timeButton(_ minutes: Int) -> some View {
        let isSelected = selectedMinutes == minutes

        return Button {
            apply(minutes: minutes)
            isPresented = false
        } label: {
            Text(Self.timeString(minutes: minutes))
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(isSelected ? MemoryTheme.accent : Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var selectedMinutes: Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: selection)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func applyTypedTime() {
        let parts = typedTime
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            hasInvalidTime = true
            return
        }

        apply(minutes: hour * 60 + minute)
        isPresented = false
    }

    private func apply(minutes: Int) {
        let calendar = Calendar.current
        selection = calendar.date(
            bySettingHour: minutes / 60,
            minute: minutes % 60,
            second: 0,
            of: selection
        ) ?? selection
        typedTime = Self.timeString(minutes: minutes)
    }

    private static func timeString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return timeString(minutes: (components.hour ?? 0) * 60 + (components.minute ?? 0))
    }

    private static func timeString(minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
#endif
