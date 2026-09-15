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
                        .popover(isPresented: $isCalendarPresented, arrowEdge: .bottom) {
                            DatePicker(
                                "Дата",
                                selection: $scheduledDate,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "ru_RU"))
                            .padding(16)
                            .frame(width: 300)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Время")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 9) {
                            Image(systemName: "clock")
                                .foregroundStyle(MemoryTheme.accent)

                            DatePicker(
                                "Время",
                                selection: $scheduledDate,
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
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
