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
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
#if os(iOS)
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Отмена")
#else
                    Button("Отмена") { dismiss() }
#endif
                }
                ToolbarItem(placement: .confirmationAction) {
#if os(iOS)
                    Button {
                        saveAndDismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Сохранить")
                    .disabled(trimmedTitle.isEmpty)
#else
                    Button("Сохранить") { saveAndDismiss() }
                        .disabled(trimmedTitle.isEmpty)
#endif
                }
            }
        }
#if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
#endif
#if os(macOS)
        .frame(minWidth: 470, minHeight: 360)
#endif
    }

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
