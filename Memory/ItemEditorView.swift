import SwiftUI

struct ItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let item: Item
    let onSave: (String, Date?) -> Void
    let onDelete: () -> Void
    @State private var title: String
    @State private var hasReminder: Bool
    @State private var reminderDate: Date

    init(item: Item, onSave: @escaping (String, Date?) -> Void, onDelete: @escaping () -> Void) {
        self.item = item
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: item.title)
        _hasReminder = State(initialValue: item.dueDate != nil)
        _reminderDate = State(initialValue: item.dueDate ?? Self.defaultReminderDate)
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
                Section("Напоминание") {
                    Toggle("Напомнить", isOn: $hasReminder)
                    if hasReminder {
                        DatePicker("Дата и время", selection: $reminderDate, displayedComponents: [.date, .hourAndMinute])
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
    }
#endif

#if os(macOS)
    private var macEditor: some View {
        VStack(spacing: 0) {
            macHeader

            Divider()

            VStack(spacing: 16) {
                macTitleCard
                macReminderCard
            }
            .padding(24)
            .frame(maxHeight: .infinity, alignment: .top)

            Divider()

            macFooter
        }
        .frame(width: 540, height: 500)
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

                Text("Обновите текст или время напоминания")
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

    private var macReminderCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(MemoryTheme.accent.opacity(0.13))
                        .frame(width: 34, height: 34)

                    Image(systemName: "bell.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MemoryTheme.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Напоминание")
                        .font(.body.weight(.medium))
                    Text(hasReminder ? "Уведомление включено" : "Без уведомления")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $hasReminder)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            if hasReminder {
                Divider()

                HStack {
                    Label("Дата и время", systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    DatePicker(
                        "Дата и время",
                        selection: $reminderDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .memoryCard()
        .animation(.easeInOut(duration: 0.18), value: hasReminder)
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

    private func saveAndDismiss() {
        onSave(trimmedTitle, hasReminder ? reminderDate : nil)
        dismiss()
    }

    private static var defaultReminderDate: Date {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) else { return .now.addingTimeInterval(3600) }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}
