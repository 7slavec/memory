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
    let onSave: (String, String?, EntryKind, Date?, Date?, [Int]) -> Bool
    let onToggleCompleted: () -> Bool
    let onDelete: () -> Bool
    let onOpenLinkedRecord: ((Item) -> Void)?
    let linkedCount: Int
    let linksItem: Item?
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
    @State private var isEndDateExpanded = false
    @State private var reminderOffsets: Set<Int>
    @State private var isDeleteConfirmationPresented = false
    @State private var isDiscardConfirmationPresented = false
    @State private var isLinksConfirmationPresented = false
    @State private var showsLinks = false
    @State private var activeSchedulePicker: SchedulePickerTarget?
    @State private var editorWidth: CGFloat = 390
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pendingLinkedRecord: Item?
    @State private var isSaveErrorPresented = false
#if os(iOS)
    @State private var isMobileEditorAtTop = true
    @State private var dismissDragEligible: Bool?
    @FocusState private var mobileFocusedField: MobileEditorField?
#endif

    init(
        item: Item,
        onSave: @escaping (String, String?, EntryKind, Date?, Date?, [Int]) -> Bool,
        onToggleCompleted: @escaping () -> Bool,
        onDelete: @escaping () -> Bool,
        isEmbedded: Bool = false,
        isCompactDesktopPane: Bool = false,
        isNew: Bool = false,
        saveActionTitle: String? = nil,
        linkedCount: Int = 0,
        linksItem: Item? = nil,
        onOpenLinkedRecord: ((Item) -> Void)? = nil,
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
        self.linkedCount = linkedCount
        self.linksItem = linksItem
        self.onOpenLinkedRecord = onOpenLinkedRecord
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
        Group {
#if os(macOS)
            macEditor
#else
            mobileEditor
#endif
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _, width in
            if width > 0 { editorWidth = width }
        }
        .alert("Не удалось сохранить", isPresented: $isSaveErrorPresented) {
            Button("ОК", role: .cancel) {}
        } message: {
            Text("Изменения остались в редакторе. Попробуйте ещё раз.")
        }
        .confirmationDialog("Сохранить изменения перед переходом?", isPresented: $isLinksConfirmationPresented, titleVisibility: .visible) {
            Button("Сохранить и перейти") {
                if persistChanges() { openPendingLinkedRecord() } else { isSaveErrorPresented = true }
            }
            .disabled(!canSave)
            Button("Перейти без изменений", role: .destructive) { openPendingLinkedRecord() }
            Button("Отмена", role: .cancel) { pendingLinkedRecord = nil }
        }
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

                            mobileScheduleCard
                            mobileNotificationCard
                        }

                        if !isNew {
                            HStack(spacing: 10) {
                                mobileDeleteButton
                                Spacer(minLength: 0)
                                if entryKind == .reminder { mobileCompletionButton }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 24)
                    .padding(.bottom, 36)
                }
                .scrollDismissesKeyboard(.interactively)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y <= -geometry.contentInsets.top + 2
                } action: { _, atTop in isMobileEditorAtTop = atTop }
            }
            .background(MemoryTheme.background)
            .contentShape(Rectangle())
            .simultaneousGesture(strongDownDismissGesture)
            .toolbar(.hidden, for: .navigationBar)
            .modifier(MemoryMobileSchedulePanel(active: $activeSchedulePicker,
                                                selection: scheduleBinding(activeSchedulePicker ?? .startDate),
                                                minimumDate: activeSchedulePicker?.editsEnd == true ? scheduledDate : nil))
        }
        .interactiveDismissDisabled()
        .confirmationDialog(
            "Удалить запись?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                deleteAndDismiss()
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
                        .foregroundStyle(.primary)
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
                .font(.system(size: 31, weight: .medium, design: .rounded))
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
                .accessibilityIdentifier("recordEditorTitle")

            if isDescriptionPresented {
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
        entryChips
    }

    private var mobileScheduleCard: some View { scheduleCard }

    private var mobileNotificationCard: some View { notificationCard }

    private var mobileDeleteButton: some View {
        Button(role: .destructive) { isDeleteConfirmationPresented = true } label: {
            Image(systemName: "trash").frame(width: 44, height: 44)
                .background(MemoryTheme.card, in: Circle())
        }
        .buttonStyle(.plain).accessibilityLabel("Удалить запись")
    }

    private var mobileCompletionButton: some View {
        Button(action: saveToggleAndDismiss) {
            Label(item.isCompleted ? "Вернуть" : "Выполнено", systemImage: "checkmark")
        }
        .buttonStyle(MemoryActionStyle(prominent: true)).disabled(!canSave)
    }

    private var strongDownDismissGesture: some Gesture {
        DragGesture(minimumDistance: 32)
            .onChanged { _ in
                if dismissDragEligible == nil {
                    dismissDragEligible = isMobileEditorAtTop && activeSchedulePicker == nil
                        && !showsLinks && mobileFocusedField == nil
                }
            }
            .onEnded { value in
                defer { dismissDragEligible = nil }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                let predictedVertical = value.predictedEndTranslation.height

                guard dismissDragEligible == true, activeSchedulePicker == nil, !showsLinks,
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

            GeometryReader { geometry in
                let inset: CGFloat = isCompactDesktopPane ? 18 : 24
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        macPrimaryContent
                        macKindPicker
                        macScheduleCard
                        macNotificationCard
                    }
                    .frame(width: min(672, max(0, geometry.size.width - inset * 2)), alignment: .leading)
                    .padding(inset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

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
        .background(MemoryTheme.background)
        .confirmationDialog(
            "Удалить запись?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                deleteAndDismiss()
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

    private var macHeader: some View {
        HStack {
            Button(action: cancelEditing) {
                Image(systemName: "arrow.left").font(.system(size: 17))
                    .frame(width: 44, height: 44)
                    .background(MemoryTheme.card, in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("Назад")
            Spacer()
            Text(isNew ? "Новая запись" : entryKind.title).font(.system(size: 14)).foregroundStyle(.secondary)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
    }

    private var macPrimaryContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Что нужно запомнить?", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(
                    .system(
                        size: isCompactDesktopPane ? 28 : 34,
                        weight: .medium,
                        design: .rounded
                    )
                )
                .lineSpacing(2)
                .lineLimit(1...6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("recordEditorTitle")

            if isDescriptionPresented {
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
        entryChips
    }

    private var macScheduleCard: some View { scheduleCard }

    private var macNotificationCard: some View { notificationCard }

    private var macFooter: some View {
        HStack(spacing: 10) {
            if !isNew {
                Button(role: .destructive) { isDeleteConfirmationPresented = true } label: {
                    Image(systemName: "trash").frame(width: 44, height: 44)
                        .background(MemoryTheme.card, in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("Удалить запись")
            }
            Spacer(minLength: 0)
            if !isNew && entryKind == .reminder {
                Button(action: saveToggleAndDismiss) {
                    Label(item.isCompleted ? "Вернуть" : "Выполнено", systemImage: "checkmark")
                }
                .buttonStyle(MemoryActionStyle(prominent: true)).disabled(!canSave)
            }
            if isNew {
                Button("Отмена", action: cancelEditing).buttonStyle(MemoryActionStyle())
                Button(saveActionTitle ?? "Создать", action: saveAndDismiss)
                    .buttonStyle(MemoryActionStyle(prominent: true))
                    .keyboardShortcut(.defaultAction).disabled(!canSave)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 18)
    }

#endif


    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            settingToggle("Дата и время", isOn: scheduleEnabledBinding, identifier: "scheduleEnabled",
                          enabled: entryKind != .event)
                .accessibilityHint(entryKind == .event ? "Для события дата обязательна" : "Включает или снимает срок записи")
            if hasSchedule {
                scheduleRow(title: "Дата", start: .startDate, end: .endDate)
                scheduleRow(title: "Время", start: .startTime, end: .endTime)
            }
            if !eventRangeIsValid {
                Text("Окончание должно быть позже начала").font(.caption).foregroundStyle(MemoryTheme.danger)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .memoryCard()
#if os(macOS)
        .modifier(MemorySchedulePopover(active: $activeSchedulePicker,
                                        selection: scheduleBinding(activeSchedulePicker ?? .startDate),
                                        minimumDate: activeSchedulePicker?.editsEnd == true ? scheduledDate : nil,
                                        availableWidth: editorWidth))
#endif
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hasSchedule)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hasEventEnd)
        .onChange(of: scheduledDate) { old, new in
            guard entryKind == .event, hasEventEnd, eventEndDate <= new else { return }
            eventEndDate = new.addingTimeInterval(max(60, eventEndDate.timeIntervalSince(old)))
        }
        .onChange(of: activeSchedulePicker) { _, target in
            if target == nil { isEndDateExpanded = false }
        }
    }

    private var scheduleEnabledBinding: Binding<Bool> {
        Binding(get: { hasSchedule }, set: { enabled in
            activeSchedulePicker = nil
            hasSchedule = enabled
            // Keep the draft's chosen date and alerts for a reversible toggle.
            // persistChanges omits both while the schedule is off.
        })
    }

    private func scheduleRow(title: String, start: SchedulePickerTarget, end: SchedulePickerTarget) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.system(size: 13)).foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                scheduleValue(start)
                endControls(end)
            }
        }
        .padding(.vertical, 2)
    }

    private func scheduleValue(_ target: SchedulePickerTarget) -> some View {
        let date = target.editsEnd ? eventEndDate : scheduledDate
        return Button {
#if os(iOS)
            mobileFocusedField = nil
#endif
            activeSchedulePicker = target
        } label: {
            Text(target.editsDate ? MemoryDateFormatting.editorDate(date) : MemoryDateFormatting.time(date))
                .font(.system(size: target.editsDate ? 20 : 26, weight: .regular))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.75).frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(target.editsEnd ? "Окончание" : "Начало"), \(target.editsDate ? "дата" : "время")")
        .anchorPreference(key: ScheduleFieldAnchors.self, value: .bounds) { [target: $0] }
    }

    @ViewBuilder private func endControls(_ target: SchedulePickerTarget) -> some View {
        if entryKind == .event {
            if hasEventEnd && (!target.editsDate || isEndDateExpanded
                || !Calendar.current.isDate(scheduledDate, inSameDayAs: eventEndDate)) {
                Text("–").font(.caption).foregroundStyle(.secondary)
                scheduleValue(target)
                Button {
                    if target.editsDate {
                        let time = Calendar.current.dateComponents([.hour, .minute], from: eventEndDate)
                        let sameDay = Calendar.current.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                                                           second: 0, of: scheduledDate) ?? scheduledDate
                        if sameDay > scheduledDate { eventEndDate = sameDay }
                        else { hasEventEnd = false }
                        isEndDateExpanded = false
                    } else {
                        hasEventEnd = false; isEndDateExpanded = false
                    }
                } label: {
                    scheduleAccessory("xmark")
                }
                .buttonStyle(.plain).accessibilityLabel(target.editsDate ? "Убрать дату окончания" : "Убрать окончание")
            } else {
                Button {
#if os(iOS)
                    mobileFocusedField = nil
#endif
                    if !hasEventEnd { eventEndDate = scheduledDate.addingTimeInterval(3600) }
                    if target.editsDate { isEndDateExpanded = true }
                    hasEventEnd = true; activeSchedulePicker = target
                } label: {
                    scheduleAccessory("plus")
                }
                .buttonStyle(.plain).accessibilityLabel(target.editsDate ? "Добавить дату окончания" : "Добавить время окончания")
                .anchorPreference(key: ScheduleFieldAnchors.self, value: .bounds) { [target: $0] }
            }
        }
    }

    private func scheduleAccessory(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
            .frame(width: 28, height: 28)
            .background(MemoryTheme.raised, in: Circle())
            .frame(width: 44, height: 44).contentShape(Rectangle())
    }

    private func scheduleBinding(_ target: SchedulePickerTarget) -> Binding<Date> {
        Binding(get: { target.editsEnd ? eventEndDate : scheduledDate }, set: { value in
            if target.editsEnd { eventEndDate = max(value, scheduledDate.addingTimeInterval(60)) }
            else { scheduledDate = value }
        })
    }

    private var notificationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            settingToggle("Напомнить", isOn: notificationsEnabledBinding, identifier: "notificationsEnabled")
            if notificationsEnabled { reminderSelectionList }
        }
        .padding(.horizontal, 18).padding(.vertical, 10).memoryCard()
        .disabled(!hasSchedule || !applicationNotificationsEnabled)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: notificationsEnabled)
    }

    private func settingToggle(_ label: String, isOn: Binding<Bool>, identifier: String, enabled: Bool = true) -> some View {
        HStack {
            Text(label).font(.system(size: 15, weight: .medium))
            Spacer(minLength: 12)
            Toggle(label, isOn: isOn).labelsHidden()
                .toggleStyle(.switch).tint(MemoryTheme.switchTint)
                .disabled(!enabled).accessibilityIdentifier(identifier)
        }
        .frame(minHeight: 44)
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
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Удалить уведомление")
                    }
                }
                .padding(.horizontal, 11)
                .frame(minHeight: 44)
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
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
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

    private func saveAndDismiss() {
        guard persistChanges() else { isSaveErrorPresented = true; return }
        closeEditor()
    }

    private func saveToggleAndDismiss() {
        guard persistChanges(), onToggleCompleted() else { isSaveErrorPresented = true; return }
        closeEditor()
    }

    private func deleteAndDismiss() {
        guard onDelete() else { isSaveErrorPresented = true; return }
        closeEditor()
    }

    private var entryChips: some View {
        HStack(spacing: 8) {
            entryKindToggle
            if onOpenLinkedRecord != nil, !isNew || linksItem != nil {
                Button { showsLinks = true } label: {
                    MemoryLinkBadge(count: linkedCount)
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("openRecordLinks")
                .recordLinksPopup(item: linksItem ?? item, isPresented: $showsLinks) { linked in
                    pendingLinkedRecord = linked
                    showsLinks = false
                    if !hasUnsavedChanges || persistChanges() { openPendingLinkedRecord() }
                    else { isSaveErrorPresented = true }
                }
            }
        }
    }

    private func openPendingLinkedRecord() {
        guard let linked = pendingLinkedRecord else { return }
        pendingLinkedRecord = nil
        onOpenLinkedRecord?(linked)
    }

    private func persistChanges() -> Bool {
        guard canSave else { return false }
        return onSave(
            trimmedTitle,
            Item.normalizedDetails(trimmedDetails),
            entryKind,
            hasSchedule ? scheduledDate : nil,
            entryKind == .event && hasSchedule && hasEventEnd ? eventEndDate : nil,
            hasSchedule ? ReminderLeadTime.normalized(Array(reminderOffsets)) : []
        )
    }

    private func cancelEditing() {
        if isNew && hasUnsavedChanges {
            isDiscardConfirmationPresented = true
        } else if hasUnsavedChanges {
            guard canSave, persistChanges() else { isSaveErrorPresented = true; return }
            closeEditor()
        } else {
            closeEditor()
        }
    }

    private func closeEditor() {
        // A stale dismissal action during a nested panel transition may only
        // close that panel, never the record and its unsaved draft.
        if activeSchedulePicker != nil { activeSchedulePicker = nil; return }
        if showsLinks { showsLinks = false; return }
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
