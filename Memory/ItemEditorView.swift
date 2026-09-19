import SwiftUI

#if os(iOS)
private enum MobileEditorField: Hashable {
    case title
    case details
}
#endif

struct ItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var account: AccountSyncController
    @AppStorage(ReminderScheduler.applicationNotificationsEnabledKey)
    private var applicationNotificationsEnabled = true
    let item: Item
    let onSave: (String, String?, Date?, [Int]) -> Void
    let onToggleCompleted: () -> Void
    let onDelete: () -> Void
    @State private var title: String
    @State private var details: String
    @State private var isDescriptionPresented: Bool
    @State private var hasSchedule: Bool
    @State private var scheduledDate: Date
    @State private var reminderOffsets: Set<Int>
    @State private var isDeleteConfirmationPresented = false
    @State private var isDiscardConfirmationPresented = false
#if os(macOS)
    @State private var isCalendarPresented = false
    @State private var isTimePickerPresented = false
#else
    @State private var isMobileEditorAtTop = true
    @FocusState private var mobileFocusedField: MobileEditorField?
#endif

    init(
        item: Item,
        onSave: @escaping (String, String?, Date?, [Int]) -> Void,
        onToggleCompleted: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.onSave = onSave
        self.onToggleCompleted = onToggleCompleted
        self.onDelete = onDelete
        _title = State(initialValue: item.title)
        _details = State(initialValue: item.details ?? "")
        _isDescriptionPresented = State(initialValue: item.details != nil)
        _hasSchedule = State(initialValue: item.dueDate != nil)
        _scheduledDate = State(initialValue: item.dueDate ?? Self.defaultScheduledDate)
        _reminderOffsets = State(initialValue: Set(item.effectiveReminderOffsets))
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
            VStack(spacing: 0) {
                mobileEditorHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        mobilePrimaryContent

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Настройки")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 2)

                            mobileScheduleCard
                            mobileNotificationCard
                        }

                        mobileCompletionButton
                        mobileDeleteButton
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 24)
                    .padding(.bottom, 36)
                }
                .scrollDismissesKeyboard(.interactively)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y <= geometry.contentInsets.top + 2
                } action: { _, isAtTop in
                    isMobileEditorAtTop = isAtTop
                }
            }
            .background(MemoryTheme.background)
            .contentShape(Rectangle())
            .simultaneousGesture(strongDownDismissGesture)
            .toolbar(.hidden, for: .navigationBar)
        }
        .confirmationDialog(
            "Удалить запись?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                onDelete()
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Это действие нельзя отменить.")
        }
        .confirmationDialog(
            "Не сохранять изменения?",
            isPresented: $isDiscardConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Не сохранять", role: .destructive) { dismiss() }
            Button("Продолжить редактирование", role: .cancel) {}
        }
        .onChange(of: hasSchedule) { _, isScheduled in
            if !isScheduled { reminderOffsets.removeAll() }
        }
    }

    private var mobileEditorHeader: some View {
        ZStack {
            Text("Напоминание")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)

            HStack(spacing: 16) {
                Button(action: cancelEditing) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Назад")

                Spacer(minLength: 0)

                Button(action: saveAndDismiss) {
                    Text("Готово")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(MemoryTheme.accent)
                        .frame(minWidth: 64, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(trimmedTitle.isEmpty)
                .opacity(trimmedTitle.isEmpty ? 0.42 : 1)
                .accessibilityLabel("Сохранить")
            }
        }
        .frame(height: 52)
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(MemoryTheme.background)
    }

    private var mobilePrimaryContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            TextField("Что нужно запомнить?", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 29, weight: .medium, design: .rounded))
                .lineSpacing(2)
                .lineLimit(1...6)
                .focused($mobileFocusedField, equals: .title)
                .submitLabel(.done)
                .onSubmit { mobileFocusedField = nil }
                .onChange(of: title) { oldValue, newValue in
                    guard Self.isSingleInsertedLineBreak(from: oldValue, to: newValue) else { return }
                    title = oldValue
                    mobileFocusedField = nil
                }
                .accessibilityLabel("Текст напоминания")

            if isDescriptionPresented {
                Divider()

                VStack(alignment: .leading, spacing: 9) {
                    Text("Описание")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    TextField("Контекст, детали или ссылка", text: $details, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17, weight: .regular, design: .rounded))
                        .lineSpacing(3)
                        .lineLimit(2...10)
                        .focused($mobileFocusedField, equals: .details)
                        .submitLabel(.done)
                        .onSubmit { mobileFocusedField = nil }
                        .onChange(of: details) { oldValue, newValue in
                            guard Self.isSingleInsertedLineBreak(from: oldValue, to: newValue) else { return }
                            details = oldValue
                            mobileFocusedField = nil
                        }
                        .accessibilityLabel("Описание напоминания")
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isDescriptionPresented = true
                    }
                    Task { @MainActor in
                        mobileFocusedField = .details
                    }
                } label: {
                    Label("Добавить описание", systemImage: "plus")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.18), value: isDescriptionPresented)
    }

    private var mobileScheduleCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                editorIcon("calendar")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Дата и время").font(.body.weight(.semibold))
                    Text(hasSchedule ? scheduleSummary : "Запись останется без срока")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Toggle("", isOn: $hasSchedule)
                    .labelsHidden()
            }

            if hasSchedule {
                Divider()
                DatePicker("Дата", selection: $scheduledDate, displayedComponents: .date)
                    .font(.body.weight(.medium))
                Divider()
                DatePicker("Время", selection: $scheduledDate, displayedComponents: .hourAndMinute)
                    .font(.body.weight(.medium))
            }
        }
        .padding(17)
        .memoryCard()
        .animation(.easeInOut(duration: 0.18), value: hasSchedule)
    }

    private var mobileNotificationCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                editorIcon(
                    notificationsEnabled ? "bell.fill" : "bell.slash",
                    color: applicationNotificationsEnabled ? MemoryTheme.accent : .secondary
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Уведомления").font(.body.weight(.semibold))
                    Text(notificationSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Toggle("", isOn: notificationsEnabledBinding)
                    .labelsHidden()
                    .disabled(!hasSchedule || !applicationNotificationsEnabled)
            }

            if hasSchedule && notificationsEnabled {
                Divider()
                reminderSelectionList
                    .disabled(!applicationNotificationsEnabled)
                    .opacity(applicationNotificationsEnabled ? 1 : 0.46)
            }
        }
        .padding(17)
        .memoryCard()
        .animation(.easeInOut(duration: 0.18), value: notificationsEnabled)
    }

    private var mobileDeleteButton: some View {
        Button(role: .destructive) {
            isDeleteConfirmationPresented = true
        } label: {
            Label("Удалить запись", systemImage: "trash")
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var mobileCompletionButton: some View {
        Button(action: saveToggleAndDismiss) {
            Label(
                item.isCompleted ? "Вернуть в активные" : "Отметить выполненным",
                systemImage: item.isCompleted ? "arrow.uturn.backward" : "checkmark.circle"
            )
            .font(.body.weight(.medium))
            .foregroundStyle(MemoryTheme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(MemoryTheme.accent.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(trimmedTitle.isEmpty)
    }

    private var strongDownDismissGesture: some Gesture {
        DragGesture(minimumDistance: 32)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                let predictedVertical = value.predictedEndTranslation.height

                guard isMobileEditorAtTop,
                      mobileFocusedField == nil,
                      vertical > 150,
                      predictedVertical > 340,
                      vertical > abs(horizontal) * 1.25 else { return }
                cancelEditing()
            }
    }

    private static func isSingleInsertedLineBreak(from oldValue: String, to newValue: String) -> Bool {
        guard newValue.count == oldValue.count + 1 else { return false }

        for index in newValue.indices where newValue[index] == "\n" || newValue[index] == "\r" {
            var candidate = newValue
            candidate.remove(at: index)
            if candidate == oldValue { return true }
        }

        return false
    }

    private func editorIcon(
        _ systemName: String,
        color: Color = MemoryTheme.accent
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 36, height: 36)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
#endif

#if os(macOS)
    private var macEditor: some View {
        VStack(spacing: 0) {
            macHeader

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    macPrimaryContent

                    Text("Настройки")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 2)

                    macScheduleCard
                    macNotificationCard
                }
                .padding(24)
            }

            Divider()

            macFooter
        }
        .frame(width: 560, height: 760)
        .background(MemoryTheme.background)
        .overlay { macPickerOverlay }
        .animation(.easeInOut(duration: 0.16), value: isCalendarPresented)
        .animation(.easeInOut(duration: 0.16), value: isTimePickerPresented)
        .confirmationDialog(
            "Удалить запись?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                onDelete()
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Это действие нельзя отменить.")
        }
        .confirmationDialog(
            "Не сохранять изменения?",
            isPresented: $isDiscardConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Не сохранять", role: .destructive) { dismiss() }
            Button("Продолжить редактирование", role: .cancel) {}
        }
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

                Text("Настройте запись, описание, дату и уведомление")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var macPrimaryContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Что нужно запомнить?", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .lineSpacing(2)
                .lineLimit(1...6)

            if isDescriptionPresented {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Описание")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    TextField("Контекст, детали или ссылка", text: $details, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, design: .rounded))
                        .lineSpacing(2)
                        .lineLimit(2...8)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isDescriptionPresented = true
                    }
                } label: {
                    Label("Добавить описание", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.18), value: isDescriptionPresented)
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
            if !isScheduled { reminderOffsets.removeAll() }
        }
    }

    private var macNotificationCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(MemoryTheme.accent.opacity(0.13))
                        .frame(width: 34, height: 34)

                    Image(systemName: notificationsEnabled ? "bell.fill" : "bell.slash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(applicationNotificationsEnabled ? MemoryTheme.accent : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Уведомления")
                        .font(.body.weight(.medium))
                    Text(notificationSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: notificationsEnabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!hasSchedule || !applicationNotificationsEnabled)
            }

            if hasSchedule && notificationsEnabled {
                Divider()
                reminderSelectionList
                    .disabled(!applicationNotificationsEnabled)
                    .opacity(applicationNotificationsEnabled ? 1 : 0.46)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .memoryCard()
        .animation(.easeInOut(duration: 0.18), value: notificationsEnabled)
    }

    private var macFooter: some View {
        HStack(spacing: 12) {
            Button(role: .destructive) {
                isDeleteConfirmationPresented = true
            } label: {
                Label("Удалить", systemImage: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)

            Button(action: saveToggleAndDismiss) {
                Label(
                    item.isCompleted ? "Вернуть" : "Выполнено",
                    systemImage: item.isCompleted ? "arrow.uturn.backward" : "checkmark.circle"
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(MemoryTheme.accent)
            .disabled(trimmedTitle.isEmpty)

            Spacer()

            Button("Отмена") {
                cancelEditing()
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
    private var trimmedDetails: String { details.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var notificationsEnabled: Bool { hasSchedule && !reminderOffsets.isEmpty }

    private var notificationsEnabledBinding: Binding<Bool> {
        Binding(
            get: { notificationsEnabled },
            set: { isEnabled in
                if isEnabled {
                    if reminderOffsets.isEmpty {
                        reminderOffsets.insert(account.defaultReminderMinutes)
                    }
                } else {
                    reminderOffsets.removeAll()
                }
            }
        )
    }

    private var reminderSelectionList: some View {
        VStack(spacing: 9) {
            ForEach(selectedReminderOffsets, id: \.self) { offset in
                HStack(spacing: 8) {
                    Menu {
                        ForEach(reminderOptions(for: offset)) { option in
                            Button {
                                replaceReminder(offset, with: option.rawValue)
                            } label: {
                                if option.rawValue == offset {
                                    Label(option.title, systemImage: "checkmark")
                                } else {
                                    Text(option.title)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "bell")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(MemoryTheme.accent)

                            Text(reminderTitle(for: offset))
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if selectedReminderOffsets.count > 1 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                _ = reminderOffsets.remove(offset)
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 30, height: 30)
                                .background(Color.primary.opacity(0.055))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Удалить уведомление")
                    }
                }
#if os(macOS)
                .padding(.horizontal, 11)
                .frame(height: 38)
#else
                .padding(.horizontal, 12)
                .frame(height: 44)
#endif
                .background {
                    Color.primary.opacity(0.05)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                }
            }

            if !availableReminderOptions.isEmpty {
                Menu {
                    ForEach(availableReminderOptions) { option in
                        Button(option.title) {
                            addReminder(option.rawValue)
                        }
                    }
                } label: {
                    Label("Добавить уведомление", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MemoryTheme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Добавляет ещё одно время уведомления")
            }
        }
    }

    private var selectedReminderOffsets: [Int] {
        ReminderLeadTime.normalized(Array(reminderOffsets))
    }

    private var availableReminderOptions: [ReminderLeadTime] {
        ReminderLeadTime.allCases.filter { !reminderOffsets.contains($0.rawValue) }
    }

    private func reminderOptions(for currentOffset: Int) -> [ReminderLeadTime] {
        ReminderLeadTime.allCases.filter {
            $0.rawValue == currentOffset || !reminderOffsets.contains($0.rawValue)
        }
    }

    private func reminderTitle(for offset: Int) -> String {
        ReminderLeadTime(rawValue: offset)?.title ?? "Выбрать время"
    }

    private func replaceReminder(_ currentOffset: Int, with newOffset: Int) {
        guard currentOffset != newOffset else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            reminderOffsets.remove(currentOffset)
            reminderOffsets.insert(newOffset)
        }
    }

    private func addReminder(_ offset: Int) {
        withAnimation(.easeInOut(duration: 0.18)) {
            _ = reminderOffsets.insert(offset)
        }
    }

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
        guard notificationsEnabled else { return "Задача останется в плане без сигнала" }
        return ReminderLeadTime.summary(Array(reminderOffsets))
    }

    private func saveAndDismiss() {
        persistChanges()
        dismiss()
    }

    private func saveToggleAndDismiss() {
        onToggleCompleted()
        persistChanges()
        dismiss()
    }

    private func persistChanges() {
        onSave(
            trimmedTitle,
            Item.normalizedDetails(trimmedDetails),
            hasSchedule ? scheduledDate : nil,
            hasSchedule ? ReminderLeadTime.normalized(Array(reminderOffsets)) : []
        )
    }

    private func cancelEditing() {
        if hasUnsavedChanges {
            isDiscardConfirmationPresented = true
        } else {
            dismiss()
        }
    }

    private var hasUnsavedChanges: Bool {
        let originalTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalDetails = Item.normalizedDetails(item.details)
        let nextDetails = Item.normalizedDetails(trimmedDetails)
        let nextDate: Date? = hasSchedule ? scheduledDate : nil
        let nextOffsets = hasSchedule ? ReminderLeadTime.normalized(Array(reminderOffsets)) : []

        return trimmedTitle != originalTitle
            || nextDetails != originalDetails
            || nextDate != item.dueDate
            || nextOffsets != item.effectiveReminderOffsets
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
