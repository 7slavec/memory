import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

enum MemorySection: String, CaseIterable, Identifiable {
    case now, inbox, completed, search
    var id: Self { self }

    var title: String {
        switch self {
        case .now: "Сейчас"
        case .inbox: "Входящие"
        case .completed: "Выполнено"
        case .search: "Поиск"
        }
    }

    var subtitle: String {
        switch self {
        case .now: "Всё, что важно не забыть"
        case .inbox: "Мысли и задачи без срока"
        case .completed: "То, что уже сделано"
        case .search: "Найти любую запись"
        }
    }

    var icon: String {
        switch self {
        case .now: "sparkles"
        case .inbox: "tray"
        case .completed: "checkmark.circle"
        case .search: "magnifyingglass"
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.timestamp, order: .reverse) private var items: [Item]
    @State private var selectedSection: MemorySection = .now
    @State private var searchText = ""
    @State private var editingItem: Item?
    @State private var errorMessage: String?
#if os(iOS)
    @State private var isKeyboardVisible = false
#endif

    var body: some View {
        Group {
#if os(macOS)
            desktopLayout
#else
            mobileLayout
#endif
        }
        .tint(MemoryTheme.accent)
        .task { repairDuplicateIdentifiers() }
        .sheet(item: $editingItem) { item in
            ItemEditorView(
                item: item,
                onSave: { title, date, notificationsEnabled in
                    update(
                        item,
                        title: title,
                        dueDate: date,
                        notificationsEnabled: notificationsEnabled
                    )
                },
                onDelete: { delete(item) }
            )
        }
        .alert("Нужно внимание", isPresented: isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Неизвестная ошибка")
        }
    }

#if os(macOS)
    private var desktopLayout: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(MemoryTheme.accent.gradient)
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Memory").font(.headline)
                        Text("Внешняя память")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)
                List(MemorySection.allCases, selection: $selectedSection) { section in
                    Label(section.title, systemImage: section.icon).tag(section)
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
        } detail: {
            sectionContent.frame(maxWidth: 920).frame(maxWidth: .infinity)
        }
    }
#endif

#if os(iOS)
    private var mobileLayout: some View {
        NavigationStack {
            sectionContent.toolbar(.hidden, for: .navigationBar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isKeyboardVisible {
                mobileTabBar.transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: isKeyboardVisible)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
    }

    private var mobileTabBar: some View {
        HStack(spacing: 4) {
            ForEach(MemorySection.allCases) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selectedSection = section }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: section.icon).font(.system(size: 18, weight: .semibold))
                        Text(section.title).font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(selectedSection == section ? MemoryTheme.accent : Color.secondary)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 5)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.45) }
    }
#endif

    private var sectionContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                pageHeader
                if selectedSection == .now || selectedSection == .inbox {
                    QuickCaptureCard(
                        defaultPreset: selectedSection == .now ? .today : .none,
                        onAdd: addItem
                    )
                    .id(selectedSection)
                }
                if selectedSection == .search { searchField }
                if selectedSection == .now, !activeItems.isEmpty { overview }
                taskList
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 36)
            .frame(maxWidth: .infinity)
        }
#if os(iOS)
        .scrollDismissesKeyboard(.interactively)
#endif
        .background(MemoryTheme.background)
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(selectedSection.title).font(.system(size: 34, weight: .bold, design: .rounded))
            Text(selectedSection.subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var overview: some View {
        HStack(spacing: 10) {
            StatPill(value: "\(dueTodayCount)", label: "на сегодня", icon: "sun.max.fill", color: MemoryTheme.warm)
            StatPill(value: "\(inboxItems.count)", label: "без срока", icon: "tray.fill", color: MemoryTheme.accent)
        }
    }

    private var searchField: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Что ищем?", text: $searchText).textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16).memoryCard()
    }

    @ViewBuilder private var taskList: some View {
        if visibleItems.isEmpty {
            EmptyMemoryView(section: selectedSection, hasSearchText: !searchText.isEmpty)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(visibleItems, id: \.persistentModelID) { item in
                    MemoryItemRow(
                        item: item,
                        onToggle: { toggleCompleted(item) },
                        onEdit: { editingItem = item },
                        onDelete: { delete(item) }
                    )
                }
            }
        }
    }

    private var activeItems: [Item] { sorted(items.filter { !$0.isCompleted && $0.dueDate != nil }) }
    private var inboxItems: [Item] { sorted(items.filter { !$0.isCompleted && $0.dueDate == nil }) }
    private var completedItems: [Item] {
        items.filter(\.isCompleted).sorted { ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt) }
    }

    private var visibleItems: [Item] {
        switch selectedSection {
        case .now: activeItems
        case .inbox: inboxItems
        case .completed: completedItems
        case .search:
            searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? items.sorted { $0.updatedAt > $1.updatedAt }
                : items.filter { $0.title.localizedCaseInsensitiveContains(searchText) }.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    private var dueTodayCount: Int {
        activeItems.filter { item in
            guard let date = item.dueDate else { return false }
            return Calendar.current.isDateInToday(date) || date < .now
        }.count
    }

    private func sorted(_ source: [Item]) -> [Item] {
        source.sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case let (left?, right?): left < right
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): lhs.timestamp > rhs.timestamp
            }
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func addItem(title: String, dueDate: Date?) {
        let item = Item(
            title: title,
            dueDate: dueDate,
            notificationsEnabled: dueDate != nil
        )
        withAnimation(.snappy) { modelContext.insert(item) }
        guard saveChanges() else { return }
        scheduleReminder(for: item)
    }

    private func update(
        _ item: Item,
        title: String,
        dueDate: Date?,
        notificationsEnabled: Bool
    ) {
        item.title = title
        item.dueDate = dueDate
        item.notificationsEnabled = dueDate != nil && notificationsEnabled
        item.updatedAt = .now
        guard saveChanges() else { return }
        scheduleReminder(for: item)
    }

    private func toggleCompleted(_ item: Item) {
        withAnimation(.snappy) { item.setCompleted(!item.isCompleted) }
        guard saveChanges() else { return }
        item.isCompleted ? ReminderScheduler.cancel(id: item.id) : scheduleReminder(for: item)
    }

    private func delete(_ item: Item) {
        let id = item.id
        withAnimation(.snappy) { modelContext.delete(item) }
        guard saveChanges() else { return }
        ReminderScheduler.cancel(id: id)
    }

    @discardableResult private func saveChanges() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            errorMessage = "Не удалось сохранить: \(error.localizedDescription)"
            return false
        }
    }

    private func scheduleReminder(for item: Item) {
        guard !item.isCompleted,
              item.notificationsEnabled,
              let date = item.dueDate else {
            ReminderScheduler.cancel(id: item.id)
            return
        }
        let id = item.id
        let title = item.title
        Task {
            do { try await ReminderScheduler.schedule(id: id, title: title, at: date) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func repairDuplicateIdentifiers() {
        var seen = Set<UUID>()
        var changed = false

        for item in items {
            if seen.contains(item.id) {
                item.id = UUID()
                item.updatedAt = .now
                changed = true
            }
            seen.insert(item.id)
        }

        if changed { _ = saveChanges() }
    }
}

private enum QuickDuePreset: String, CaseIterable, Identifiable {
    case none, today, tomorrow
    var id: Self { self }
    var title: String { self == .none ? "Без срока" : self == .today ? "Сегодня" : "Завтра" }
    var icon: String { self == .none ? "tray" : self == .today ? "sun.max" : "sunrise" }

    var date: Date? {
        let calendar = Calendar.current
        switch self {
        case .none: return nil
        case .today:
            let evening = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: .now) ?? .now
            return evening > .now ? evening : calendar.date(byAdding: .hour, value: 1, to: .now)
        case .tomorrow:
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) else { return nil }
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        }
    }
}

private struct QuickCaptureCard: View {
    @State private var draft = ""
    @State private var preset: QuickDuePreset
    @State private var ignoredSmartExpression: String?
    @State private var smartResult: ParsedMemoryInput?
    @FocusState private var isFocused: Bool
    let defaultPreset: QuickDuePreset
    let onAdd: (String, Date?) -> Void

    init(defaultPreset: QuickDuePreset, onAdd: @escaping (String, Date?) -> Void) {
        _preset = State(initialValue: defaultPreset)
        self.defaultPreset = defaultPreset
        self.onAdd = onAdd
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(MemoryTheme.accent)
                    .frame(width: 34, height: 34).background(MemoryTheme.accent.opacity(0.12)).clipShape(Circle())
                TextField("Что нужно запомнить?", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .accessibilityIdentifier("quickCaptureField")
                    .onSubmit(submit)
#if os(iOS)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.sentences)
#endif
                Button(action: submit) {
                    Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(trimmedDraft.isEmpty ? Color.secondary.opacity(0.25) : MemoryTheme.accent).clipShape(Circle())
                }
                .buttonStyle(.plain).disabled(trimmedDraft.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }

            if let smartResult {
                HStack(spacing: 11) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MemoryTheme.accent)
                        .frame(width: 28, height: 28)
                        .background(MemoryTheme.accent.opacity(0.12))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(smartDateLabel(for: smartResult.dueDate))
                            .font(.caption.weight(.semibold))
                        if smartResult.title != trimmedDraft {
                            Text("Сохранится: \(smartResult.title)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Button {
                        ignoredSmartExpression = draft
                        self.smartResult = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Не распознавать дату")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(MemoryTheme.accent.opacity(0.075))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .accessibilityIdentifier("smartDateSuggestion")
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Divider().opacity(0.55)
            HStack(spacing: 8) {
                ForEach(QuickDuePreset.allCases) { option in
                    Button {
                        preset = option
                        ignoredSmartExpression = draft
                        smartResult = nil
                    } label: {
                        Label(option.title, systemImage: option.icon)
                            .font(.caption.weight(.medium)).padding(.horizontal, 11).padding(.vertical, 7)
                            .background(isSelected(option) ? MemoryTheme.accent.opacity(0.13) : Color.secondary.opacity(0.08))
                            .foregroundStyle(isSelected(option) ? MemoryTheme.accent : Color.secondary).clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18).memoryCard()
        .animation(.easeInOut(duration: 0.18), value: smartResult != nil)
        .onChange(of: draft) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            smartResult = ignoredSmartExpression == newValue
                ? nil
                : NaturalLanguageDateParser.parse(trimmed)
        }
    }

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func isSelected(_ option: QuickDuePreset) -> Bool {
        smartResult == nil && preset == option
    }

    private func smartDateLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "Сегодня · \(time)" }
        if calendar.isDateInTomorrow(date) { return "Завтра · \(time)" }
        return Self.smartDateFormatter.string(from: date)
    }

    private static let smartDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter
    }()

    private func submit() {
        guard !trimmedDraft.isEmpty else { return }
        if let smartResult {
            onAdd(smartResult.title, smartResult.dueDate)
        } else {
            onAdd(trimmedDraft, preset.date)
        }
        draft = ""
        preset = defaultPreset
        ignoredSmartExpression = nil
        isFocused = false
    }
}

private struct MemoryItemRow: View {
    let item: Item
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(item.isCompleted ? MemoryTheme.accent : Color.secondary.opacity(0.65))
            }
            .buttonStyle(.plain)
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(item.title.isEmpty ? "Без названия" : item.title)
                        .font(.body.weight(.medium)).foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                        .strikethrough(item.isCompleted).multilineTextAlignment(.leading)
                    Label(dateLabel, systemImage: dateIcon).font(.caption).foregroundStyle(dateColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Menu {
                Button(action: onEdit) { Label("Изменить", systemImage: "pencil") }
                Button(role: .destructive, action: onDelete) { Label("Удалить", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").font(.headline).foregroundStyle(.secondary).frame(width: 30, height: 30)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 17).padding(.vertical, 15).memoryCard()
        .contextMenu {
            Button(action: onEdit) { Label("Изменить", systemImage: "pencil") }
            Button(role: .destructive, action: onDelete) { Label("Удалить", systemImage: "trash") }
        }
    }

    private var dateLabel: String {
        if item.isCompleted { return "Выполнено" }
        guard let date = item.dueDate else { return "Без срока" }
        if date < .now { return "Просрочено · \(date.formatted(date: .omitted, time: .shortened))" }
        if Calendar.current.isDateInToday(date) { return "Сегодня · \(date.formatted(date: .omitted, time: .shortened))" }
        if Calendar.current.isDateInTomorrow(date) { return "Завтра · \(date.formatted(date: .omitted, time: .shortened))" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
    private var dateIcon: String {
        if item.isCompleted { return "checkmark" }
        guard item.dueDate != nil else { return "tray" }
        return item.notificationsEnabled ? "bell" : "calendar"
    }
    private var dateColor: Color {
        guard !item.isCompleted, let date = item.dueDate else { return .secondary }
        return date < .now ? .red : MemoryTheme.accent
    }
}

private struct StatPill: View {
    let value: String, label: String, icon: String
    let color: Color
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity)
        .background(color.opacity(0.09)).clipShape(RoundedRectangle(cornerRadius: 15))
    }
}

private struct EmptyMemoryView: View {
    let section: MemorySection
    let hasSearchText: Bool
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 34, weight: .light)).foregroundStyle(MemoryTheme.accent)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.vertical, 42).padding(.horizontal, 24).frame(maxWidth: .infinity).memoryCard()
    }
    private var icon: String { section == .completed ? "checkmark.seal" : section == .search ? "magnifyingglass" : "sparkles" }
    private var title: String {
        switch section {
        case .now: "Всё спокойно"
        case .inbox: "Входящие разобраны"
        case .completed: "Пока нет выполненных"
        case .search: hasSearchText ? "Ничего не нашлось" : "Начните печатать"
        }
    }
    private var message: String {
        switch section {
        case .now: "Запишите мысль выше — Memory сохранит её за вас."
        case .inbox: "Задачи без даты появятся здесь."
        case .completed: "Здесь будет история завершённых дел."
        case .search: hasSearchText ? "Попробуйте другой запрос." : "Мы поищем среди всех записей."
        }
    }
}

#Preview {
    ContentView().modelContainer(for: Item.self, inMemory: true)
}
