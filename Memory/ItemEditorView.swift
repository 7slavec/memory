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
    let onSave: (String, String?, EntryKind, Date?, Date?, [Int]) -> Void
    let onToggleCompleted: () -> Void
    let onDelete: () -> Void
    let isEmbedded: Bool
    let isCompactDesktopPane: Bool
    let onDismiss: () -> Void
    let isNew: Bool
    let saveActionTitle: String?
    @State private var title: String
    @State private var details: String
    @State private var isDescriptionPresented: Bool
    @State private var hasSchedule: Bool
    @State private var scheduledDate: Date
    @State private var entryKind: EntryKind
    @State private var eventEndDate: Date
    @State private var hasEventEnd: Bool
    @State private var reminderOffsets: Set<Int>
    @State private var isDeleteConfirmationPresented = false
    @State private var isDiscardConfirmationPresented = false
#if os(macOS)
    @State private var isCalendarPresented = false
    @State private var isTimePickerPresented = false
    @State private var macPickerTarget: SchedulePickerTarget = .startDate
#else
    @State private var isMobileEditorAtTop = true
    @State private var mobileSchedulePicker: SchedulePickerTarget?
    @FocusState private var mobileFocusedField: MobileEditorField?
#endif

    init(
        item: Item,
        onSave: @escaping (String, String?, EntryKind, Date?, Date?, [Int]) -> Void,
        onToggleCompleted: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        isEmbedded: Bool = false,
        isCompactDesktopPane: Bool = false,
        isNew: Bool = false,
        saveActionTitle: String? = nil,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.item = item
        self.onSave = onSave
        self.onToggleCompleted = onToggleCompleted
        self.onDelete = onDelete
        self.isEmbedded = isEmbedded
        self.isCompactDesktopPane = isCompactDesktopPane
        self.isNew = isNew
        self.saveActionTitle = saveActionTitle
        self.onDismiss = onDismiss
        _title = State(initialValue: item.title)
        _details = State(initialValue: item.details ?? "")
        _isDescriptionPresented = State(initialValue: item.details != nil)
        _hasSchedule = State(initialValue: item.dueDate != nil)
        _scheduledDate = State(initialValue: item.dueDate ?? Self.defaultScheduledDate)
        _entryKind = State(initialValue: item.entryKind)
        let initialStart = item.dueDate ?? Self.defaultScheduledDate
        _eventEndDate = State(initialValue: item.endDate ?? initialStart.addingTimeInterval(3_600))
        _hasEventEnd = State(initialValue: item.endDate != nil)
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
                        mobileKindPicker

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Настройки")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 2)

                            mobileScheduleCard
                            mobileNotificationCard
                        }

                        if !isNew && entryKind == .reminder {
                            mobileCompletionButton
                        }
                        if !isNew {
                            mobileDeleteButton
                        }
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
                closeEditor()
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
            Button("Не сохранять", role: .destructive) { closeEditor() }
            Button("Продолжить редактирование", role: .cancel) {}
        }
        .sheet(item: $mobileSchedulePicker) { target in
            mobileSchedulePickerSheet(target)
                .presentationDetents([.height(target.editsDate ? 368 : 220)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
                .presentationBackground(MemoryTheme.card)
        }
        .onChange(of: hasSchedule) { _, isScheduled in
            if !isScheduled { reminderOffsets.removeAll() }
        }
        .onChange(of: scheduledDate) { oldValue, newValue in
            guard entryKind == .event, hasEventEnd, eventEndDate <= newValue else { return }
            let previousDuration = max(eventEndDate.timeIntervalSince(oldValue), 3_600)
            eventEndDate = newValue.addingTimeInterval(previousDuration)
        }
    }

    private var mobileEditorHeader: some View {
        ZStack {
            Text(entryKind.title)
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
                    Text(saveActionTitle ?? "Готово")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(MemoryTheme.accent)
                        .frame(minWidth: 64, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.42)
                .accessibilityLabel(saveActionTitle ?? "Сохранить")
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 6)
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

    private var mobileKindPicker: some View {
        entryKindToggle
    }

    private var mobileScheduleCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text(entryKind == .event ? "Период" : "Дата и время")
                    .font(.body.weight(.semibold))
                Spacer()
                if entryKind == .reminder || !hasSchedule {
                    schedulePresenceButton
                }
            }
            .padding(.bottom, hasSchedule ? 14 : 0)

            if hasSchedule {
                Divider()
                mobileScheduleValueRow(
                    title: "Дата",
                    startValue: MemoryDateFormatting.editorDate(scheduledDate),
                    startTarget: .startDate,
                    endValue: MemoryDateFormatting.editorDate(eventEndDate),
                    endTarget: .endDate
                )

                Divider()

                mobileScheduleValueRow(
                    title: "Время",
                    startValue: MemoryDateFormatting.time(scheduledDate),
                    startTarget: .startTime,
                    endValue: MemoryDateFormatting.time(eventEndDate),
                    endTarget: .endTime
                )

                if !eventRangeIsValid {
                    Text("Окончание должно быть позже начала")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
            }
        }
        .padding(17)
        .memoryCard()
        .animation(.easeInOut(duration: 0.18), value: hasSchedule)
        .animation(.easeInOut(duration: 0.18), value: hasEventEnd)
    }

    private func mobileScheduleValueRow(
        title: String,
        startValue: String,
        startTarget: SchedulePickerTarget,
        endValue: String,
        endTarget: SchedulePickerTarget
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                scheduleRowTitle(title)
                Spacer(minLength: 8)
                scheduleValueButton(startValue) { mobileSchedulePicker = startTarget }
                if entryKind == .event {
                    mobileScheduleEndControls(endValue: endValue, endTarget: endTarget)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    scheduleRowTitle(title)
                    Spacer(minLength: 8)
                    scheduleValueButton(startValue) { mobileSchedulePicker = startTarget }
                }
                if entryKind == .event {
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        mobileScheduleEndControls(endValue: endValue, endTarget: endTarget)
                    }
                }
            }
        }
        .frame(minHeight: 48)
    }

    @ViewBuilder
    private func mobileScheduleEndControls(
        endValue: String,
        endTarget: SchedulePickerTarget
    ) -> some View {
        if hasEventEnd {
            Text("—")
                .font(.caption)
                .foregroundStyle(.tertiary)
            scheduleValueButton(endValue) { mobileSchedulePicker = endTarget }
            removeEventEndButton
        } else {
            addEventEndButton(target: endTarget)
        }
    }

    private func scheduleValueButton(
        _ value: String,
        action: @escaping () -> Void
    ) -> some View {
        MemoryScheduleValueChip(value: value, action: action)
    }

    private func addEventEndButton(target: SchedulePickerTarget) -> some View {
        Button {
            addEventEnd(opening: target)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(MemoryTheme.accent)
                .frame(width: 32, height: 32)
                .background(MemoryTheme.accent.opacity(0.1))
                .clipShape(Circle())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Добавить окончание")
    }

    private var removeEventEndButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                hasEventEnd = false
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Color.secondary.opacity(0.08))
                .clipShape(Circle())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Убрать окончание")
    }

    private func addEventEnd(opening target: SchedulePickerTarget) {
        eventEndDate = max(eventEndDate, scheduledDate.addingTimeInterval(3_600))
        withAnimation(.easeInOut(duration: 0.18)) {
            hasEventEnd = true
        }
        mobileSchedulePicker = target
    }

    private func mobileSchedulePickerSheet(_ target: SchedulePickerTarget) -> some View {
        MobileSchedulePickerSheet(
            target: target,
            selection: target.editsEnd ? eventEndDate : scheduledDate,
            minimumDate: scheduleMinimumDate(for: target),
            onCommit: { value in
                let normalizedValue = normalizedScheduleSelection(value, for: target)
                if target.editsEnd {
                    eventEndDate = normalizedValue
                } else {
                    scheduledDate = normalizedValue
                }
                mobileSchedulePicker = nil
            }
        )
        .labelsHidden()
    }

    private func scheduleMinimumDate(for target: SchedulePickerTarget) -> Date? {
        guard target.editsEnd else { return nil }
        return target.editsDate
            ? Calendar.current.startOfDay(for: scheduledDate)
            : scheduledDate
    }

    private func normalizedScheduleSelection(
        _ value: Date,
        for target: SchedulePickerTarget
    ) -> Date {
        guard target.editsDate else { return value }

        let calendar = Calendar.current
        let currentValue = target.editsEnd ? eventEndDate : scheduledDate
        let date = calendar.dateComponents([.year, .month, .day], from: value)
        let time = calendar.dateComponents([.hour, .minute, .second], from: currentValue)
        var components = DateComponents()
        components.timeZone = calendar.timeZone
        components.year = date.year
        components.month = date.month
        components.day = date.day
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        return calendar.date(from: components) ?? value
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

                    macKindPicker

                    Text("Настройки")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 2)

                    macScheduleCard
                    macNotificationCard
                }
                .padding(isCompactDesktopPane ? 18 : 24)
            }

            Divider()

            macFooter
        }
        .frame(
            minWidth: isEmbedded ? 0 : 560,
            idealWidth: isEmbedded ? 720 : 560,
            maxWidth: isEmbedded ? .infinity : 560,
            minHeight: isEmbedded ? 0 : 760,
            idealHeight: 760,
            maxHeight: isEmbedded ? .infinity : 760
        )
        .background(isCompactDesktopPane ? MemoryTheme.card : MemoryTheme.background)
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
                closeEditor()
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
            Button("Не сохранять", role: .destructive) { closeEditor() }
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
                        selection: macPickerSelection,
                        isPresented: $isCalendarPresented
                    )
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                } else {
                    MemoryTimePicker(
                        selection: macPickerSelection,
                        isPresented: $isTimePickerPresented
                    )
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
        }
    }

    private var macHeader: some View {
        HStack(spacing: 14) {
            if isEmbedded {
                Button(action: cancelEditing) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(Color.primary.opacity(0.055))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Назад")
                .accessibilityLabel("Назад")
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MemoryTheme.accent.opacity(0.14))
                        .frame(width: 48, height: 48)

                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(MemoryTheme.accent)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(isEmbedded ? entryKind.title : (isNew ? "Новая запись" : "Редактировать запись"))
                    .font(.title3.weight(.semibold))

                if !isEmbedded {
                    Text("Настройте запись, описание, дату и уведомление")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, isCompactDesktopPane ? 18 : 24)
        .padding(.vertical, isCompactDesktopPane ? 15 : 20)
    }

    private var macPrimaryContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Что нужно запомнить?", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(
                    .system(
                        size: isCompactDesktopPane ? 23 : 26,
                        weight: .medium,
                        design: .rounded
                    )
                )
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

    private var macKindPicker: some View {
        entryKindToggle
    }

    private var macScheduleCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text(entryKind == .event ? "Период" : "Дата и время")
                    .font(.body.weight(.medium))
                Spacer()
                if entryKind == .reminder || !hasSchedule {
                    schedulePresenceButton
                }
            }
            .padding(.bottom, hasSchedule ? 14 : 0)

            if hasSchedule {
                Divider()
                macScheduleValueRow(
                    title: "Дата",
                    startValue: MemoryDateFormatting.editorDate(scheduledDate),
                    startTarget: .startDate,
                    endValue: MemoryDateFormatting.editorDate(eventEndDate),
                    endTarget: .endDate
                )

                Divider()

                macScheduleValueRow(
                    title: "Время",
                    startValue: MemoryDateFormatting.time(scheduledDate),
                    startTarget: .startTime,
                    endValue: MemoryDateFormatting.time(eventEndDate),
                    endTarget: .endTime
                )

                if !eventRangeIsValid {
                    Text("Окончание должно быть позже начала")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
            }
        }
        .padding(18)
        .memoryCard()
        .animation(.easeInOut(duration: 0.18), value: hasSchedule)
        .animation(.easeInOut(duration: 0.18), value: hasEventEnd)
        .onChange(of: hasSchedule) { _, isScheduled in
            if !isScheduled { reminderOffsets.removeAll() }
        }
        .onChange(of: scheduledDate) { oldValue, newValue in
            guard entryKind == .event, hasEventEnd, eventEndDate <= newValue else { return }
            let previousDuration = max(eventEndDate.timeIntervalSince(oldValue), 3_600)
            eventEndDate = newValue.addingTimeInterval(previousDuration)
        }
    }

    private func macScheduleValueRow(
        title: String,
        startValue: String,
        startTarget: SchedulePickerTarget,
        endValue: String,
        endTarget: SchedulePickerTarget
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                scheduleRowTitle(title)
                Spacer(minLength: 12)
                macScheduleValueButton(startValue, target: startTarget)
                if entryKind == .event {
                    macScheduleEndControls(endValue: endValue, endTarget: endTarget)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    scheduleRowTitle(title)
                    Spacer(minLength: 12)
                    macScheduleValueButton(startValue, target: startTarget)
                }
                if entryKind == .event {
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        macScheduleEndControls(endValue: endValue, endTarget: endTarget)
                    }
                }
            }
        }
        .frame(minHeight: 46)
    }

    @ViewBuilder
    private func macScheduleEndControls(
        endValue: String,
        endTarget: SchedulePickerTarget
    ) -> some View {
        if hasEventEnd {
            Text("—").foregroundStyle(.tertiary)
            macScheduleValueButton(endValue, target: endTarget)
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { hasEventEnd = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(Circle())
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Убрать окончание")
        } else {
            Button {
                addMacEventEnd(opening: endTarget)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MemoryTheme.accent)
                    .frame(width: 30, height: 30)
                    .background(MemoryTheme.accent.opacity(0.1))
                    .clipShape(Circle())
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Добавить окончание")
        }
    }

    private func macScheduleValueButton(
        _ value: String,
        target: SchedulePickerTarget
    ) -> some View {
        MemoryScheduleValueChip(value: value) {
            macPickerTarget = target
            isCalendarPresented = target.editsDate
            isTimePickerPresented = !target.editsDate
        }
    }

    private func addMacEventEnd(opening target: SchedulePickerTarget) {
        eventEndDate = max(eventEndDate, scheduledDate.addingTimeInterval(3_600))
        hasEventEnd = true
        macPickerTarget = target
        isCalendarPresented = target.editsDate
        isTimePickerPresented = !target.editsDate
    }

    private var macPickerSelection: Binding<Date> {
        Binding(
            get: { macPickerTarget.editsEnd ? eventEndDate : scheduledDate },
            set: { value in
                if macPickerTarget.editsEnd {
                    eventEndDate = max(value, scheduledDate.addingTimeInterval(60))
                } else {
                    scheduledDate = value
                }
            }
        )
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
            if !isNew {
                Button(role: .destructive) {
                    isDeleteConfirmationPresented = true
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }

            if !isNew && entryKind == .reminder {
                Button(action: saveToggleAndDismiss) {
                    Label(
                        item.isCompleted ? "Вернуть" : "Выполнено",
                        systemImage: item.isCompleted ? "arrow.uturn.backward" : "checkmark.circle"
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(MemoryTheme.accent)
                .disabled(trimmedTitle.isEmpty)
            }

            Spacer()

            Button("Отмена") {
                cancelEditing()
            }
            .keyboardShortcut(.cancelAction)

            Button(saveActionTitle ?? "Сохранить") {
                saveAndDismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(MemoryTheme.accent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
        .padding(.horizontal, isCompactDesktopPane ? 18 : 24)
        .padding(.vertical, isCompactDesktopPane ? 14 : 18)
    }
#endif

    private func scheduleRowTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private var entryKindToggle: some View {
        MemoryEntryKindChip(kind: entryKind) {
            let nextKind: EntryKind = entryKind == .reminder ? .event : .reminder
            withAnimation(.easeInOut(duration: 0.2)) {
                entryKind = nextKind
                normalizeSchedule(for: nextKind)
            }
        }
    }

    private var schedulePresenceButton: some View {
        Button {
            if hasSchedule {
                withAnimation(.easeInOut(duration: 0.18)) { hasSchedule = false }
            } else {
                withAnimation(.easeInOut(duration: 0.18)) { hasSchedule = true }
                if reminderOffsets.isEmpty {
                    reminderOffsets.insert(account.defaultReminderMinutes)
                }
#if os(iOS)
                mobileSchedulePicker = .startDate
#else
                macPickerTarget = .startDate
                isCalendarPresented = true
#endif
            }
        } label: {
            Image(systemName: hasSchedule ? "xmark" : "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(hasSchedule ? Color.secondary : MemoryTheme.accent)
                .frame(width: 30, height: 30)
                .background(
                    hasSchedule ? Color.secondary.opacity(0.08) : MemoryTheme.accent.opacity(0.1)
                )
                .clipShape(Circle())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasSchedule ? "Убрать дату и время" : "Добавить дату и время")
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedDetails: String { details.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var notificationsEnabled: Bool { hasSchedule && !reminderOffsets.isEmpty }
    private var eventRangeIsValid: Bool {
        entryKind != .event || (hasSchedule && (!hasEventEnd || eventEndDate > scheduledDate))
    }
    private var canSave: Bool { !trimmedTitle.isEmpty && eventRangeIsValid }

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
        if entryKind == .event {
#if os(macOS)
            let start = MemoryDateFormatting.time(scheduledDate)
            guard hasEventEnd else { return "\(macDateLabel) · \(start)" }
            return "\(macDateLabel) · \(start)–\(MemoryDateFormatting.time(eventEndDate))"
#else
            let start = MemoryDateFormatting.shortDateTime(scheduledDate)
            guard hasEventEnd else { return start }
            return "\(start)–\(MemoryDateFormatting.time(eventEndDate))"
#endif
        }
#if os(macOS)
        return "\(macDateLabel) · \(MemoryDateFormatting.time(scheduledDate))"
#else
        return MemoryDateFormatting.shortDateTime(scheduledDate)
#endif
    }

#if os(macOS)
    private var macDateLabel: String {
        MemoryDateFormatting.editorDate(scheduledDate)
    }
#endif

    private var notificationSummary: String {
        guard hasSchedule else { return "Сначала добавьте дату и время" }
        guard notificationsEnabled else { return "Задача останется в плане без сигнала" }
        return ReminderLeadTime.summary(Array(reminderOffsets))
    }

    private func saveAndDismiss() {
        persistChanges()
        closeEditor()
    }

    private func saveToggleAndDismiss() {
        onToggleCompleted()
        persistChanges()
        closeEditor()
    }

    private func persistChanges() {
        onSave(
            trimmedTitle,
            Item.normalizedDetails(trimmedDetails),
            entryKind,
            hasSchedule ? scheduledDate : nil,
            entryKind == .event && hasSchedule && hasEventEnd ? eventEndDate : nil,
            hasSchedule ? ReminderLeadTime.normalized(Array(reminderOffsets)) : []
        )
    }

    private func cancelEditing() {
        if hasUnsavedChanges {
            isDiscardConfirmationPresented = true
        } else {
            closeEditor()
        }
    }

    private func closeEditor() {
        if isEmbedded {
            onDismiss()
        } else {
            dismiss()
        }
    }

    private var hasUnsavedChanges: Bool {
        let originalTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalDetails = Item.normalizedDetails(item.details)
        let nextDetails = Item.normalizedDetails(trimmedDetails)
        let nextDate: Date? = hasSchedule ? scheduledDate : nil
        let nextEndDate: Date? = entryKind == .event && hasSchedule && hasEventEnd ? eventEndDate : nil
        let nextOffsets = hasSchedule ? ReminderLeadTime.normalized(Array(reminderOffsets)) : []

        return trimmedTitle != originalTitle
            || nextDetails != originalDetails
            || entryKind != item.entryKind
            || nextDate != item.dueDate
            || nextEndDate != item.endDate
            || nextOffsets != item.effectiveReminderOffsets
    }

    private func normalizeSchedule(for kind: EntryKind) {
        if kind == .event {
            hasSchedule = true
            if hasEventEnd && eventEndDate <= scheduledDate {
                eventEndDate = scheduledDate.addingTimeInterval(3_600)
            }
        } else {
            hasEventEnd = false
        }
    }

    private static var defaultScheduledDate: Date {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) else { return .now.addingTimeInterval(3600) }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}
