import SwiftData
import SwiftUI
import UserNotifications
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

enum MemorySection: String, CaseIterable, Identifiable {
    case now, all
    var id: Self { self }

    var title: String {
        switch self {
        case .now: "Сейчас"
        case .all: "Все записи"
        }
    }

    var tabTitle: String {
        switch self {
        case .now: "Сейчас"
        case .all: "Все"
        }
    }

    var subtitle: String {
        switch self {
        case .now: "Всё, что важно не забыть"
        case .all: "Поиск и планы по времени"
        }
    }

    var icon: String {
        switch self {
        case .now: "sparkles"
        case .all: "rectangle.stack"
        }
    }

}

#if os(macOS)
private enum DesktopSection: String, CaseIterable, Identifiable {
    case now
    case all
    case inbox
    case archive
    case profile

    var id: Self { self }

    var title: String {
        switch self {
        case .now: "Сейчас"
        case .all: "Все записи"
        case .inbox: "Входящие"
        case .archive: "Архив"
        case .profile: "Профиль"
        }
    }

    var icon: String {
        switch self {
        case .now: "sparkles"
        case .all: "rectangle.stack.fill"
        case .inbox: "tray.full.fill"
        case .archive: "archivebox.fill"
        case .profile: "person.crop.circle.fill"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .now: "1"
        case .all: "2"
        case .inbox: "3"
        case .archive: "4"
        case .profile: "5"
        }
    }
}
#endif

enum AllItemsGroup: CaseIterable, Identifiable {
    case overdue, today, tomorrow, week, later, noDate

    var id: Self { self }

    var title: String {
        switch self {
        case .overdue: "Просрочено"
        case .today: "Сегодня"
        case .tomorrow: "Завтра"
        case .week: "На неделе"
        case .later: "Позже"
        case .noDate: "Без срока"
        }
    }

    var icon: String {
        switch self {
        case .overdue: "exclamationmark"
        case .today: "sun.max.fill"
        case .tomorrow: "sunrise.fill"
        case .week: "calendar"
        case .later: "arrow.right"
        case .noDate: "tray"
        }
    }

    var color: Color {
        switch self {
        case .overdue: .red
        case .today: MemoryTheme.warm
        case .tomorrow, .week, .later: MemoryTheme.accent
        case .noDate: .secondary
        }
    }

    static func group(for item: Item, now: Date, using baseCalendar: Calendar = .current) -> Self {
        guard let dueDate = item.dueDate else { return .noDate }

        var calendar = baseCalendar
        calendar.firstWeekday = 2 // Monday

        if item.isEvent {
            let today = calendar.startOfDay(for: now)
            let startDay = calendar.startOfDay(for: dueDate)
            let endDay = calendar.startOfDay(for: item.endDate ?? dueDate)
            if today >= startDay && today <= endDay { return .today }
        } else if dueDate < now {
            return .overdue
        }

        if calendar.isDate(dueDate, inSameDayAs: now) { return .today }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(dueDate, inSameDayAs: tomorrow) {
            return .tomorrow
        }
        if let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now),
           dueDate < currentWeek.end {
            return .week
        }
        return .later
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var account: AccountSyncController
    @Query(sort: \Item.timestamp, order: .reverse) private var items: [Item]
    @State private var selectedSection: MemorySection = .now
    @State private var searchText = ""
    @State private var editingItem: Item?
    @State private var draftEditingItem: Item?
    @State private var detailedDraftCommitVersion = 0
    @State private var voiceReviewSession: VoiceBatchReviewSession?
    @State private var pendingReviewNavigation: (() -> Void)?
    @State private var isReviewExitConfirmationPresented = false
    @State private var recentlyAddedItem: Item?
    @State private var recentlyAddedBatchCount: Int?
    @State private var batchConfirmationVersion = 0
    @State private var suppressItemOpening = false
    @State private var isAccountPresented = false
    @State private var archiveSearchText = ""
    @State private var inboxSearchText = ""
    @State private var isInboxPresented = false
    @State private var errorMessage: String?
    @State private var currentDate = Date.now
#if os(macOS)
    @State private var notificationsAreDisabled = false
    @State private var desktopSection: DesktopSection = .now
    @State private var isDesktopSidebarCollapsed = false
    @State private var desktopSidebarWidth: CGFloat = 232
    @State private var desktopSidebarDragStartWidth: CGFloat?
    @State private var isDesktopComposerPresented = false
    @State private var isEditingNewDesktopItem = false
#endif
#if os(iOS)
    @AppStorage(ReminderScheduler.applicationNotificationsEnabledKey)
    private var applicationNotificationsEnabled = true
    @AppStorage(AppAppearance.storageKey)
    private var appAppearance: AppAppearance = .system
    @State private var isKeyboardVisible = false
    @State private var hasTriggeredPageSwipe = false
    @State private var isMobileProfilePresented = false
    @State private var isMobileArchivePresented = false
    @State private var isVoiceLabPresented = false
    @State private var isProfileWorking = false
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
        .confirmationDialog("Выйти из просмотра записей?", isPresented: $isReviewExitConfirmationPresented, titleVisibility: .visible) {
            if let session = voiceReviewSession, session.selectedEntryID == nil, session.canSave {
                Button("Сохранить и перейти") {
                    if finishVoiceReview(session) { completeReviewNavigation() }
                }
            }
            Button("Выйти без изменений", role: .destructive) {
                dismissVoiceReview()
                completeReviewNavigation()
            }
            Button("Остаться", role: .cancel) { pendingReviewNavigation = nil }
        } message: {
            Text(voiceReviewSession?.batch.isPersisted == true
                ? "Неприменённые изменения будут потеряны. Созданные записи останутся."
                : "Несохранённые записи будут потеряны.")
        }
        .task {
#if DEBUG
            if VoiceReviewTesting.isEnabled {
                voiceReviewSession = VoiceReviewTesting.session()
                return
            }
#endif
            repairDuplicateIdentifiers()
            await account.restoreSession()
#if os(macOS)
            await refreshNotificationStatus()
#endif
            await synchronize()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                currentDate = .now
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !VoiceReviewTesting.isEnabled else { return }
            currentDate = .now
            Task {
#if os(macOS)
                await refreshNotificationStatus()
#endif
                await synchronize()
            }
        }
        .onChange(of: selectedSection) { _, section in
            if section != .all {
                isInboxPresented = false
            }
        }
#if os(iOS)
        .fullScreenCover(item: $editingItem) { item in
            ItemEditorView(
                item: item,
                onSave: { title, details, kind, date, endDate, reminderOffsets in
                    update(
                        item,
                        title: title,
                        details: details,
                        entryKind: kind,
                        dueDate: date,
                        endDate: endDate,
                        reminderOffsets: reminderOffsets
                    )
                },
                onToggleCompleted: { toggleCompleted(item) },
                onDelete: { delete(item) }
            )
        }
        .fullScreenCover(item: $draftEditingItem) { draft in
            ItemEditorView(
                item: draft,
                onSave: { title, details, kind, date, endDate, reminderOffsets in
                    if addItem(
                        title: title,
                        details: details,
                        entryKind: kind,
                        dueDate: date,
                        endDate: endDate,
                        reminderOffsets: reminderOffsets
                    ) != nil {
                        detailedDraftCommitVersion += 1
                    }
                },
                onToggleCompleted: {},
                onDelete: {},
                isNew: true
            )
        }
        .fullScreenCover(isPresented: $isVoiceLabPresented) {
            VoiceLabView {
                isVoiceLabPresented = false
            }
        }
#endif
#if os(macOS)
        .sheet(isPresented: $isAccountPresented) {
            AccountView()
                .environmentObject(account)
        }
#else
        .fullScreenCover(isPresented: $isAccountPresented) {
            AccountView()
                .environmentObject(account)
        }
#endif
        .alert("Нужно внимание", isPresented: isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Неизвестная ошибка")
        }
    }

#if os(macOS)
    private var desktopLayout: some View {
        desktopWorkspaceLayout
            .frame(minWidth: 620, idealWidth: 1080, minHeight: 600, idealHeight: 760)
        .background(MemoryTheme.background)
    }

    private var desktopWorkspaceLayout: some View {
        GeometryReader { proxy in
            let maximumSidebarWidth = max(224, min(330, proxy.size.width - 520))
            let effectiveSidebarWidth = isDesktopSidebarCollapsed
                ? 72
                : min(max(desktopSidebarWidth, 224), maximumSidebarWidth)
            let resizeHandleWidth: CGFloat = isDesktopSidebarCollapsed ? 1 : 9
            let workspaceWidth = max(proxy.size.width - effectiveSidebarWidth - resizeHandleWidth, 0)
            let showsDetailPane = editingItem != nil && workspaceWidth >= 1_040
            let detailPaneWidth = min(max(workspaceWidth * 0.42, 440), 520)

            HStack(spacing: 0) {
                desktopSidebar
                    .frame(width: effectiveSidebarWidth)

                desktopSidebarResizeHandle

                desktopWorkspaceContent(
                    showsDetailPane: showsDetailPane,
                    detailPaneWidth: detailPaneWidth
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(.easeInOut(duration: 0.22), value: editingItem?.id)
            .animation(.easeInOut(duration: 0.22), value: showsDetailPane)
            .overlay(alignment: .bottomTrailing) {
                if let item = recentlyAddedItem, editingItem == nil {
                    captureConfirmation(for: item)
                        .frame(maxWidth: 420)
                        .padding(24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let count = recentlyAddedBatchCount {
                    batchConfirmation(count: count)
                        .padding(24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: isDesktopSidebarCollapsed)
        .background(MemoryTheme.background)
    }

    @ViewBuilder private func desktopWorkspaceContent(
        showsDetailPane: Bool,
        detailPaneWidth: CGFloat
    ) -> some View {
        if let session = voiceReviewSession {
            voiceReviewPage(session)
        } else {
            ZStack {
                HStack(spacing: 0) {
                    desktopSectionContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(editingItem != nil && !showsDetailPane ? 0 : 1)
                        .allowsHitTesting(editingItem == nil || showsDetailPane)
                        .accessibilityHidden(editingItem != nil && !showsDetailPane)

                    if let item = editingItem, showsDetailPane {
                        desktopItemEditor(item, compact: true)
                            .id(item.id)
                            .frame(width: detailPaneWidth)
                            .padding(.vertical, 16)
                            .padding(.trailing, 16)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }

                if let item = editingItem, !showsDetailPane {
                    desktopItemEditor(item, compact: false)
                        .id(item.id)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .clipped()
        }
    }

    private var desktopSidebar: some View {
        VStack(spacing: 0) {
            Group {
                if isDesktopSidebarCollapsed {
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                            isDesktopSidebarCollapsed = false
                        }
                    } label: {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 42, height: 42)
                            .background(Color.primary.opacity(0.055))
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Развернуть боковую панель")
                } else {
                    HStack(spacing: 12) {
                        Image("NorkaLogo")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .foregroundStyle(.primary)
                            .frame(width: 86, height: 24)

                        Spacer(minLength: 8)

                        Button {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                                isDesktopSidebarCollapsed = true
                            }
                        } label: {
                            Image(systemName: "sidebar.left")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 32, height: 32)
                                .background(Color.primary.opacity(0.055))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Свернуть боковую панель")
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, isDesktopSidebarCollapsed ? 14 : 18)
            .padding(.top, 20)
            .padding(.bottom, 18)

            VStack(spacing: 6) {
                ForEach(DesktopSection.allCases.filter { $0 != .profile }) { section in
                    desktopSidebarButton(section)
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 18)

            Button {
                selectDesktopSection(.profile)
            } label: {
                if isDesktopSidebarCollapsed {
                    Text(desktopProfileInitial)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(MemoryTheme.accent.gradient)
                        .clipShape(Circle())
                        .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 11) {
                        Text(desktopProfileInitial)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(MemoryTheme.accent.gradient)
                            .clipShape(Circle())

                        Text(account.email ?? "Профиль")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(desktopSection == .profile ? MemoryTheme.accent : Color.primary)
            .background(
                desktopSection == .profile
                    ? MemoryTheme.accent.opacity(0.12)
                    : Color.primary.opacity(isDesktopSidebarCollapsed ? 0 : 0.045)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(isDesktopSidebarCollapsed ? 14 : 12)
            .help("Профиль")
            .keyboardShortcut("5", modifiers: .command)
        }
        .background(.ultraThinMaterial)
        .clipped()
    }

    private var desktopSidebarResizeHandle: some View {
        ZStack {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)

            Color.clear
                .frame(width: 9)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            guard !isDesktopSidebarCollapsed else { return }
                            if desktopSidebarDragStartWidth == nil {
                                desktopSidebarDragStartWidth = desktopSidebarWidth
                            }
                            let proposed = (desktopSidebarDragStartWidth ?? desktopSidebarWidth)
                                + value.translation.width
                            desktopSidebarWidth = min(max(proposed, 224), 330)
                        }
                        .onEnded { _ in
                            desktopSidebarDragStartWidth = nil
                        }
                )
        }
        .frame(width: isDesktopSidebarCollapsed ? 1 : 9)
        .help("Изменить ширину боковой панели")
    }

    private func desktopSidebarButton(_ section: DesktopSection) -> some View {
        Button {
            selectDesktopSection(section)
        } label: {
            if isDesktopSidebarCollapsed {
                Image(systemName: section.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .frame(maxWidth: .infinity)
                    .background(
                        desktopSection == section
                            ? MemoryTheme.accent.opacity(0.12)
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            } else {
                HStack(spacing: 11) {
                    Image(systemName: section.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 24)

                    Text(section.title)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)

                    Spacer(minLength: 8)

                    if let count = desktopBadgeCount(for: section), count > 0 {
                        Text("\(count)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .padding(.horizontal, 7)
                            .frame(minHeight: 22)
                            .background(Color.primary.opacity(0.07))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                .background(
                    desktopSection == section
                        ? MemoryTheme.accent.opacity(0.12)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(desktopSection == section ? MemoryTheme.accent : Color.primary)
        .help(section.title)
        .keyboardShortcut(section.shortcut, modifiers: .command)
    }

    private func selectDesktopSection(_ section: DesktopSection) {
        requestVoiceReviewExit {
            withAnimation(.easeOut(duration: 0.16)) {
                desktopSection = section
                editingItem = nil
                isEditingNewDesktopItem = false
                isDesktopComposerPresented = false
            }
        }
    }

    private func desktopBadgeCount(for section: DesktopSection) -> Int? {
        switch section {
        case .now: overdueItems.count + todayItems.count
        case .all: activeItems.count
        case .inbox: inboxItems.count
        case .archive: completedItems.count
        case .profile: nil
        }
    }

    @ViewBuilder private var desktopSectionContent: some View {
        switch desktopSection {
        case .now:
            desktopNowPage
        case .all:
            desktopRecordsPage(
                title: "Все записи",
                search: searchField,
                content: AnyView(activeItemsListContent)
            )
        case .inbox:
            desktopRecordsPage(
                title: "Входящие",
                search: inboxSearchField,
                content: AnyView(desktopInboxContent)
            )
        case .archive:
            desktopRecordsPage(
                title: "Архив",
                search: desktopArchiveSearchField,
                allowsCapture: false,
                content: AnyView(desktopArchiveContent)
            )
        case .profile:
            desktopProfilePage
        }
    }

    private func desktopItemEditor(_ item: Item, compact: Bool) -> some View {
        ItemEditorView(
            item: item,
            onSave: { title, details, kind, date, endDate, reminderOffsets in
                if !isEditingNewDesktopItem {
                    update(
                        item,
                        title: title,
                        details: details,
                        entryKind: kind,
                        dueDate: date,
                        endDate: endDate,
                        reminderOffsets: reminderOffsets
                    )
                } else {
                    if addItem(
                        title: title,
                        details: details,
                        entryKind: kind,
                        dueDate: date,
                        endDate: endDate,
                        reminderOffsets: reminderOffsets
                    ) != nil {
                        detailedDraftCommitVersion += 1
                    }
                }
            },
            onToggleCompleted: { toggleCompleted(item) },
            onDelete: { delete(item) },
            isEmbedded: true,
            isCompactDesktopPane: compact,
            isNew: isEditingNewDesktopItem,
            onDismiss: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    editingItem = nil
                    isEditingNewDesktopItem = false
                }
            }
        )
        .environmentObject(account)
        .background {
            if compact {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: compact ? 22 : 0,
                style: .continuous
            )
        )
        .overlay {
            if compact {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .shadow(
            color: compact ? Color.black.opacity(0.12) : .clear,
            radius: compact ? 20 : 0,
            y: compact ? 8 : 0
        )
    }

    private var desktopNowPage: some View {
        ScrollView {
            VStack(spacing: 28) {
                desktopPageHeader(
                    title: "Сегодня",
                    caption: Self.mainDateFormatter.string(from: currentDate)
                )
                .frame(maxWidth: 760)

                if notificationsAreDisabled {
                    notificationSettingsBanner
                        .frame(maxWidth: 680)
                }

                QuickCaptureCard(
                    defaultPreset: .today,
                    presentation: .desktopWorkspace,
                    detailCommitSignal: detailedDraftCommitVersion,
                    remoteVoiceInterpreter: remoteVoiceInterpreter,
                    onOpenDetails: openDetailedDraft,
                    onReviewBatch: presentVoiceBatch,
                    onAdd: addItem
                )
                .id("mac-workspace-composer")
                .frame(maxWidth: 680)

                desktopPrioritySection
                    .frame(maxWidth: 680)
            }
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
    }

    private func desktopRecordsPage<Search: View>(
        title: String,
        search: Search,
        allowsCapture: Bool = true,
        content: AnyView
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                desktopPageHeader(title: title, caption: nil)
                search
                content
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, allowsCapture ? 130 : 40)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if allowsCapture {
                desktopRecordsCaptureControl
            }
        }
    }

    private var desktopPrioritySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(desktopPriorityIsOverdue ? "Требует внимания" : "Ближайшее")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            if let item = desktopPriorityItem {
                HomePriorityCard(
                    item: item,
                    isOverdue: desktopPriorityIsOverdue,
                    onToggle: { toggleCompleted(item) },
                    onEdit: { editingItem = item }
                )
            } else {
                TodayEmptyView(hasUpcomingItems: false)
            }
        }
    }

    private var desktopPriorityItem: Item? {
        overdueItems.last ?? todayItems.first
    }

    private var desktopPriorityIsOverdue: Bool {
        !overdueItems.isEmpty
    }

    @ViewBuilder private var desktopRecordsCaptureControl: some View {
        if isDesktopComposerPresented {
            QuickCaptureCard(
                defaultPreset: desktopSection == .inbox ? .none : .today,
                presentation: .desktopInline,
                autofocus: true,
                detailCommitSignal: detailedDraftCommitVersion,
                remoteVoiceInterpreter: remoteVoiceInterpreter,
                onDismiss: {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                        isDesktopComposerPresented = false
                    }
                },
                onOpenDetails: openDetailedDraft,
                onReviewBatch: presentVoiceBatch,
                onAdd: { title, details, kind, dueDate, endDate, reminderOffsets in
                    let itemID = addItem(
                        title: title,
                        details: details,
                        entryKind: kind,
                        dueDate: dueDate,
                        endDate: endDate,
                        reminderOffsets: reminderOffsets
                    )
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                        isDesktopComposerPresented = false
                    }
                    return itemID
                }
            )
            .id("desktop-records-composer-\(desktopSection.rawValue)")
            .frame(maxWidth: 570)
            .padding(.horizontal, 30)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            HStack {
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                        isDesktopComposerPresented = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(MemoryTheme.accent.gradient)
                        .clipShape(Circle())
                        .shadow(color: MemoryTheme.accent.opacity(0.2), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
                .help("Добавить напоминание")
                .accessibilityLabel("Добавить напоминание")
            }
            .frame(maxWidth: 820)
            .padding(.horizontal, 30)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .transition(.scale(scale: 0.84, anchor: .bottomTrailing).combined(with: .opacity))
        }
    }

    @ViewBuilder private var desktopInboxContent: some View {
        if searchedInboxItems.isEmpty {
            RecordsEmptyView(
                icon: inboxSearchTextIsEmpty ? "tray" : "magnifyingglass",
                title: inboxSearchTextIsEmpty ? "Входящие пусты" : "Ничего не нашлось",
                message: inboxSearchTextIsEmpty
                    ? "Напоминания без срока появятся здесь."
                    : "Попробуйте другой запрос."
            )
        } else {
            taskRows(searchedInboxItems)
        }
    }

    @ViewBuilder private var desktopArchiveContent: some View {
        if searchedCompletedItems.isEmpty {
            RecordsEmptyView(
                icon: archiveSearchTextIsEmpty ? "archivebox" : "magnifyingglass",
                title: archiveSearchTextIsEmpty ? "Архив пуст" : "Ничего не нашлось",
                message: archiveSearchTextIsEmpty
                    ? "Выполненные напоминания появятся здесь."
                    : "Попробуйте другой запрос."
            )
        } else {
            taskRows(searchedCompletedItems)
        }
    }

    private var desktopArchiveSearchField: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Поиск в архиве", text: $archiveSearchText)
                .textFieldStyle(.plain)
            if !archiveSearchText.isEmpty {
                Button { archiveSearchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(15)
        .memoryCard()
    }

    private func desktopPageHeader(title: String, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 30, weight: .medium, design: .rounded))
            if let caption {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var desktopProfilePage: some View {
        AccountView(
            embedded: true,
            onOpenArchive: { selectDesktopSection(.archive) }
        )
            .environmentObject(account)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var desktopProfileInitial: String {
        guard let first = account.email?.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return "N"
        }
        return String(first).uppercased()
    }

    private var homePriorityItem: Item? {
        if let overdue = overdueItems.last { return overdue }
        if let today = todayItems.first { return today }
        return upcomingItems.first
    }

    private var homePriorityIsOverdue: Bool {
        guard let item = homePriorityItem, let dueDate = item.dueDate else { return false }
        return dueDate < currentDate
    }
#endif

#if os(iOS)
    @ViewBuilder private var mobileLayout: some View {
        if let session = voiceReviewSession {
            voiceReviewPage(session)
        } else {
            mobileMainLayout
        }
    }

    private var mobileMainLayout: some View {
        NavigationStack {
            VStack(spacing: 0) {
                mobilePersistentHeader

                GeometryReader { proxy in
                    ZStack {
                        ZStack {
                            QuickCaptureCard(
                                defaultPreset: .today,
                                isDocked: true,
                                isHome: true,
                                isRecordsPage: selectedSection == .all,
                                externalKeyboardVisible: isKeyboardVisible,
                                priorityItem: homePriorityItem,
                                isPriorityOverdue: homePriorityIsOverdue,
                                additionalPriorityCount: homeAdditionalPriorityCount,
                                detailCommitSignal: detailedDraftCommitVersion,
                                remoteVoiceInterpreter: remoteVoiceInterpreter,
                                onTogglePriority: {
                                    guard let item = homePriorityItem else { return }
                                    toggleCompleted(item)
                                },
                                onEditPriority: {
                                    guard let item = homePriorityItem else { return }
                                    editingItem = item
                                },
                                onShowAll: { navigateMobile(to: .all) },
                                onOpenDetails: openDetailedDraft,
                                onReviewBatch: presentVoiceBatch,
                                onAdd: addItem
                            )
                            .zIndex(2)

                            if selectedSection == .all {
                                mobileRecordsContent
                                    .transition(.move(edge: .leading).combined(with: .opacity))
                                    .zIndex(1)
                            }
                        }
                        .overlay(alignment: .top) {
                            if let item = recentlyAddedItem {
                                captureConfirmation(for: item)
                                    .padding(.horizontal, 18)
                                    .padding(.top, 8)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                                    .zIndex(10)
                            } else if let count = recentlyAddedBatchCount {
                                batchConfirmation(count: count)
                                    .padding(.horizontal, 18)
                                    .padding(.top, 8)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                                    .zIndex(10)
                            }
                        }
                        .offset(x: isMobileProfilePresented ? -proxy.size.width : 0)
                        .allowsHitTesting(!isMobileProfilePresented)

                        mobileProfileDestinationContent
                            .offset(x: isMobileProfilePresented ? 0 : proxy.size.width)
                            .allowsHitTesting(isMobileProfilePresented)
                    }
                    .clipped()
                    .simultaneousGesture(responsiveMobilePageSwipeGesture)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(MemoryTheme.background.ignoresSafeArea())
        }
        .animation(.easeOut(duration: 0.18), value: isKeyboardVisible)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
    }

    @ViewBuilder private var mobilePersistentHeader: some View {
        if isMobileArchivePresented {
            mobileSecondaryHeader(title: "Архив", backAction: handleMobileProfileBack)
                .transition(.opacity)
        } else if isInboxPresented && !isMobileProfilePresented {
            mobileSecondaryHeader(title: "Входящие", backAction: closeInbox)
                .transition(.opacity)
        } else {
            mobilePrimaryHeader
                .transition(.opacity)
        }
    }

    private var mobilePrimaryHeader: some View {
        ZStack {
            Image("NorkaLogo")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(.primary)
                .frame(width: 88, height: 24)
                .accessibilityHidden(true)

            HStack(spacing: 16) {
                Button {
                    if isMobileProfilePresented {
                        handleMobileProfileBack()
                    } else {
                        navigateMobile(to: selectedSection == .now ? .all : .now)
                    }
                } label: {
                    ZStack {
                        if isMobileProfilePresented {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 52, height: 52)
                                .background(Color.primary.opacity(0.065))
                                .clipShape(Circle())
                                .overlay {
                                    Circle().stroke(Color.primary.opacity(0.07), lineWidth: 1)
                                }
                                .transition(.scale(scale: 0.78).combined(with: .opacity))
                        } else if selectedSection == .now {
                            Image(systemName: "rectangle.stack.fill")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 52, height: 52)
                                .background(Color.primary.opacity(0.065))
                                .clipShape(Circle())
                                .overlay {
                                    Circle().stroke(Color.primary.opacity(0.07), lineWidth: 1)
                                }
                                .transition(.scale(scale: 0.78).combined(with: .opacity))
                        } else {
                            GlassVoiceOrb(isListening: false, isProcessing: false, isPulsing: false, size: 34)
                                .frame(width: 52, height: 52)
                                .clipShape(Circle())
                                .contentShape(Circle())
                                .transition(.scale(scale: 0.78).combined(with: .opacity))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isMobileProfilePresented
                        ? isMobileArchivePresented ? "Назад в профиль" : "Назад"
                        : selectedSection == .now ? "Все записи" : "На главный экран"
                )

                Spacer(minLength: 0)

                if isMobileProfilePresented {
                    Color.clear
                        .frame(width: 52, height: 52)
                        .allowsHitTesting(false)
                } else {
                    mobileAccountButton
                        .transition(.scale(scale: 0.78).combined(with: .opacity))
                }
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func mobileSecondaryHeader(
        title: String,
        backAction: @escaping () -> Void
    ) -> some View {
        ZStack {
            Text(title)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)

            HStack(spacing: 16) {
                Button(action: backAction) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Назад")

                Spacer(minLength: 0)

                Color.clear
                    .frame(width: 44, height: 44)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(MemoryTheme.background)
    }

    private var mobileRecordsContent: some View {
        GeometryReader { proxy in
            ZStack {
                mobileDatedRecordsContent
                    .offset(x: isInboxPresented ? -proxy.size.width : 0)
                    .allowsHitTesting(!isInboxPresented)

                mobileInboxContent
                    .offset(x: isInboxPresented ? 0 : proxy.size.width)
                    .allowsHitTesting(isInboxPresented)
            }
            .clipped()
        }
        .background(MemoryTheme.background)
    }

    private var mobileDatedRecordsContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                HStack(spacing: 12) {
                    Text("Все записи")
                        .font(.system(size: 26, weight: .medium, design: .rounded))

                    Spacer(minLength: 8)

                    Button(action: openInbox) {
                        HStack(spacing: 7) {
                            Image(systemName: "tray.full.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Входящие")
                                .lineLimit(1)
                            if !inboxItems.isEmpty {
                                Text("\(inboxItems.count)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(MemoryTheme.accent)
                                    .padding(.horizontal, 6)
                                    .frame(minHeight: 22)
                                    .background(MemoryTheme.accent.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 11)
                        .frame(minHeight: 40)
                        .background(Color.primary.opacity(0.055))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Открывает напоминания без срока")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Section {
                    activeItemsListContent
                        .padding(.top, 2)
                } header: {
                    searchField
                        .padding(.vertical, 8)
                        .background(MemoryTheme.background)
                        .zIndex(5)
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 104)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(MemoryTheme.background)
    }

    private var mobileInboxContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                inboxSearchField

                if searchedInboxItems.isEmpty {
                    RecordsEmptyView(
                        icon: inboxSearchTextIsEmpty ? "tray" : "magnifyingglass",
                        title: inboxSearchTextIsEmpty ? "Входящие пусты" : "Ничего не нашлось",
                        message: inboxSearchTextIsEmpty
                            ? "Напоминания без срока появятся здесь."
                            : "Попробуйте другой запрос."
                    )
                    .padding(.top, 8)
                } else {
                    taskRows(searchedInboxItems)
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 104)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(MemoryTheme.background)
        .simultaneousGesture(internalPageBackSwipeGesture(action: closeInbox))
    }

    private var mobileProfileDestinationContent: some View {
        GeometryReader { proxy in
            ZStack {
                mobileProfileContent
                    .offset(x: isMobileArchivePresented ? -proxy.size.width : 0)
                    .allowsHitTesting(!isMobileArchivePresented)

                mobileArchiveContent
                    .offset(x: isMobileArchivePresented ? 0 : proxy.size.width)
                    .allowsHitTesting(isMobileArchivePresented)
            }
            .clipped()
        }
        .background(MemoryTheme.background)
    }

    private var mobileProfileContent: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 26) {
                    mobileProfileHero

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Создание")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)

                        HStack(spacing: 14) {
                            profileSettingsIcon(account.defaultEntryKind.icon)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Новая запись")
                                    .font(.body.weight(.medium))
                                Text("Если тип не указан в тексте")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)

                            Menu {
                                ForEach(EntryKind.allCases) { kind in
                                    Button {
                                        setDefaultEntryKind(kind)
                                    } label: {
                                        if kind == account.defaultEntryKind {
                                            Label(kind.title, systemImage: "checkmark")
                                        } else {
                                            Text(kind.title)
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(account.defaultEntryKind.title)
                                        .lineLimit(1)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 11)
                                .frame(height: 36)
                                .background(Color.primary.opacity(0.055))
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(16)
                        .memoryCard()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Уведомления")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)

                        VStack(spacing: 0) {
                            HStack(spacing: 14) {
                                profileSettingsIcon("bell.fill")

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Уведомления")
                                        .font(.body.weight(.medium))
                                    Text(applicationNotificationsEnabled ? "Включены" : "Выключены")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 12)

                                Toggle("Уведомления", isOn: applicationNotificationsBinding)
                                    .labelsHidden()
                            }
                            .padding(16)

                            Divider()
                                .padding(.leading, 66)

                            HStack(spacing: 14) {
                                profileSettingsIcon("clock.fill")

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Когда напоминать")
                                        .font(.body.weight(.medium))
                                    Text("Для новых записей")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 8)

                                Menu {
                                    ForEach(ReminderLeadTime.allCases) { option in
                                        Button {
                                            setDefaultReminder(option.rawValue)
                                        } label: {
                                            if option.rawValue == account.defaultReminderMinutes {
                                                Label(option.title, systemImage: "checkmark")
                                            } else {
                                                Text(option.title)
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(defaultReminderTitle)
                                            .lineLimit(1)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 11)
                                    .frame(height: 34)
                                    .background(Color.primary.opacity(0.055))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(16)
                        }
                        .memoryCard()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Оформление")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)

                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 14) {
                                profileSettingsIcon("circle.lefthalf.filled")

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Тема приложения")
                                        .font(.body.weight(.medium))
                                    Text(appAppearance.details)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 0)
                            }

                            Picker("Тема приложения", selection: $appAppearance) {
                                ForEach(AppAppearance.allCases) { appearance in
                                    Text(appearance.title).tag(appearance)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .accessibilityHint("Меняет оформление всего приложения")
                        }
                        .padding(16)
                        .memoryCard()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Записи")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)

                        Button(action: openMobileArchive) {
                            HStack(spacing: 14) {
                                profileSettingsIcon("archivebox.fill")

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Архив")
                                        .font(.body.weight(.medium))
                                    Text("Выполненные напоминания")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 10)

                                if !completedItems.isEmpty {
                                    Text("\(completedItems.count)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(MemoryTheme.accent)
                                        .padding(.horizontal, 9)
                                        .frame(minHeight: 28)
                                        .background(MemoryTheme.accent.opacity(0.11))
                                        .clipShape(Capsule())
                                }

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .memoryCard()
                        .accessibilityHint("Открывает выполненные напоминания")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Голосовой ввод")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)

                        Button {
                            isVoiceLabPresented = true
                        } label: {
                            HStack(spacing: 14) {
                                profileSettingsIcon("waveform.badge.magnifyingglass")

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Voice Lab")
                                        .font(.body.weight(.medium))
                                    Text("Все настройки и тесты голосового ввода")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 10)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .memoryCard()
                        .accessibilityHint("Открывает лабораторию голосового ввода")
                    }

                    Spacer(minLength: 26)

                    if account.isSignedIn {
                        Button(role: .destructive) {
                            signOutFromMobileProfile()
                        } label: {
                            HStack(spacing: 10) {
                                if isProfileWorking {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                }
                                Text("Выйти")
                            }
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.red.opacity(0.09))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isProfileWorking)
                    } else {
                        Button {
                            isAccountPresented = true
                        } label: {
                            Text("Войти или создать аккаунт")
                                .font(.body.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .foregroundStyle(.white)
                                .background(MemoryTheme.accent.gradient)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 620)
                .frame(minHeight: max(proxy.size.height - 44, 0), alignment: .top)
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(MemoryTheme.background)
    }

    private var mobileArchiveContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                archiveSearchField

                if searchedCompletedItems.isEmpty {
                    RecordsEmptyView(
                        icon: archiveSearchTextIsEmpty ? "archivebox" : "magnifyingglass",
                        title: archiveSearchTextIsEmpty ? "Архив пуст" : "Ничего не нашлось",
                        message: archiveSearchTextIsEmpty
                            ? "Выполненные напоминания появятся здесь."
                            : "Попробуйте другой запрос."
                    )
                    .padding(.top, 8)
                } else {
                    taskRows(searchedCompletedItems)
                }
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(MemoryTheme.background)
        .simultaneousGesture(internalPageBackSwipeGesture(action: handleMobileProfileBack))
    }

    private var archiveSearchField: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Поиск в архиве", text: $archiveSearchText)
                .textFieldStyle(.plain)

            if !archiveSearchText.isEmpty {
                Button { archiveSearchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(16)
        .memoryCard()
    }

    private var mobileProfileHero: some View {
        VStack(spacing: 16) {
            Text(profileInitial)
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(MemoryTheme.accent.gradient)
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: MemoryTheme.accent.opacity(0.22), radius: 22, y: 8)

            HStack(spacing: 7) {
                Text(account.email ?? "Локальный профиль")
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Image(systemName: profileSyncIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(profileSyncColor)
                    .accessibilityLabel(account.statusText)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func profileSettingsIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(MemoryTheme.accent)
            .frame(width: 38, height: 38)
            .background(MemoryTheme.accent.opacity(0.11))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var profileInitial: String {
        guard let first = account.email?.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return "N"
        }
        return String(first).uppercased()
    }

    private var profileSyncIcon: String {
        guard account.isSignedIn else { return "icloud.slash" }
        switch account.state {
        case .syncing: return "arrow.triangle.2.circlepath"
        case .failed: return "exclamationmark.triangle.fill"
        default: return "checkmark.icloud.fill"
        }
    }

    private var profileSyncColor: Color {
        if case .failed = account.state { return .red }
        return account.isSignedIn ? MemoryTheme.accent : .secondary
    }

    private var applicationNotificationsBinding: Binding<Bool> {
        Binding(
            get: { applicationNotificationsEnabled },
            set: { setApplicationNotificationsEnabled($0) }
        )
    }

    private var defaultReminderTitle: String {
        ReminderLeadTime(rawValue: account.defaultReminderMinutes)?.compactTitle ?? "В момент"
    }

    private func setDefaultReminder(_ value: Int) {
        Task {
            do {
                try await account.setDefaultReminderMinutes(value)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func setDefaultEntryKind(_ kind: EntryKind) {
        Task {
            do {
                try await account.setDefaultEntryKind(kind)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func setApplicationNotificationsEnabled(_ isEnabled: Bool) {
        applicationNotificationsEnabled = isEnabled
        ReminderScheduler.setApplicationNotificationsEnabled(isEnabled)

        if isEnabled {
            for item in activeItems {
                scheduleReminder(for: item)
            }
        } else {
            for item in items {
                ReminderScheduler.cancel(id: item.id)
            }
        }
    }

    private func signOutFromMobileProfile() {
        guard !isProfileWorking else { return }
        isProfileWorking = true
        Task {
            do {
                try await account.signOut()
                closeMobileProfile()
            } catch {
                errorMessage = error.localizedDescription
            }
            isProfileWorking = false
        }
    }

    private var responsiveMobilePageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isKeyboardVisible, !isMobileProfilePresented, !isInboxPresented else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) * 1.2 else { return }

                if abs(horizontal) > 8 {
                    suppressItemOpening = true
                }

                guard !hasTriggeredPageSwipe, abs(horizontal) > 26 else { return }
                if selectedSection == .now, horizontal > 0 {
                    hasTriggeredPageSwipe = true
                    navigateMobile(to: .all)
                } else if selectedSection == .all, horizontal < 0 {
                    hasTriggeredPageSwipe = true
                    navigateMobile(to: .now)
                }
            }
            .onEnded { value in
                guard !isKeyboardVisible, !isMobileProfilePresented, !isInboxPresented else {
                    resetResponsiveSwipeState()
                    return
                }

                let horizontal = value.translation.width
                let vertical = value.translation.height
                let predicted = value.predictedEndTranslation.width

                if !hasTriggeredPageSwipe,
                   abs(horizontal) > abs(vertical) * 1.2,
                   abs(predicted) > 52 {
                    suppressItemOpening = true
                    if selectedSection == .now, predicted > 0 {
                        navigateMobile(to: .all)
                    } else if selectedSection == .all, predicted < 0 {
                        navigateMobile(to: .now)
                    }
                }

                resetResponsiveSwipeState()
            }
    }

    private func internalPageBackSwipeGesture(
        action: @escaping () -> Void
    ) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) * 1.25,
                      abs(horizontal) > 14 else { return }
                suppressItemOpening = true
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                let predicted = value.predictedEndTranslation.width
                let isHorizontal = abs(horizontal) > abs(vertical) * 1.25

                if isHorizontal,
                   horizontal > 64 || predicted > 120 {
                    action()
                }

                resetResponsiveSwipeState()
            }
    }

    private func resetResponsiveSwipeState() {
        hasTriggeredPageSwipe = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            suppressItemOpening = false
        }
    }

    private func navigateMobile(to section: MemorySection) {
        guard !isMobileProfilePresented else { return }
        guard selectedSection != section else { return }
        requestVoiceReviewExit {
            dismissAppKeyboard()
            isInboxPresented = false
            withAnimation(.easeOut(duration: 0.16)) {
                selectedSection = section
            }
        }
    }

    private func openInbox() {
        guard selectedSection == .all, !isInboxPresented else { return }
        dismissAppKeyboard()
        withAnimation(.easeOut(duration: 0.18)) {
            isInboxPresented = true
        }
    }

    private func closeInbox() {
        guard isInboxPresented else { return }
        dismissAppKeyboard()
        withAnimation(.easeOut(duration: 0.18)) {
            isInboxPresented = false
        }
    }

    private func openMobileProfile() {
        guard !isMobileProfilePresented else { return }
        requestVoiceReviewExit {
            dismissAppKeyboard()
            isMobileArchivePresented = false
            withAnimation(.easeInOut(duration: 0.24)) {
                isMobileProfilePresented = true
            }
        }
    }

    private func openMobileArchive() {
        guard isMobileProfilePresented, !isMobileArchivePresented else { return }
        dismissAppKeyboard()
        withAnimation(.easeOut(duration: 0.18)) {
            isMobileArchivePresented = true
        }
    }

    private func handleMobileProfileBack() {
        if isMobileArchivePresented {
            dismissAppKeyboard()
            withAnimation(.easeOut(duration: 0.18)) {
                isMobileArchivePresented = false
            }
        } else {
            closeMobileProfile()
        }
    }

    private func closeMobileProfile() {
        guard isMobileProfilePresented else { return }
        dismissAppKeyboard()
        withAnimation(.easeInOut(duration: 0.24)) {
            isMobileProfilePresented = false
        }
    }

    private var homePriorityItem: Item? {
        if let overdue = overdueItems.last { return overdue }
        if let today = todayItems.first { return today }
        return upcomingItems.first
    }

    private var homePriorityIsOverdue: Bool {
        guard let item = homePriorityItem, let dueDate = item.dueDate else { return false }
        return dueDate < currentDate
    }

    private var homeAdditionalPriorityCount: Int {
        if homePriorityIsOverdue { return max(overdueItems.count - 1, 0) }
        return 0
    }
#endif

    private func captureConfirmation(for item: Item) -> some View {
        CaptureConfirmationBanner(
            title: item.title,
            dueDate: item.dueDate,
            onEdit: {
                withAnimation(.easeOut(duration: 0.16)) {
                    recentlyAddedItem = nil
                }
                editingItem = item
            },
            onUndo: {
                withAnimation(.easeOut(duration: 0.16)) {
                    recentlyAddedItem = nil
                }
                delete(item)
            }
        )
    }

    private func batchConfirmation(count: Int) -> some View {
        Text(count == 1 ? "Добавлена 1 запись" : count < 5
            ? "Добавлены \(count) записи" : "Добавлено \(count) записей")
            .font(.body.weight(.medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.regularMaterial)
            .clipShape(Capsule())
    }

    private var sectionContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                pageHeader
#if os(macOS)
                if notificationsAreDisabled {
                    notificationSettingsBanner
                }
                if selectedSection == .now {
                    QuickCaptureCard(
                        defaultPreset: .today,
                        isDocked: true,
                        detailCommitSignal: detailedDraftCommitVersion,
                        remoteVoiceInterpreter: remoteVoiceInterpreter,
                        onOpenDetails: openDetailedDraft,
                        onReviewBatch: presentVoiceBatch,
                        onAdd: addItem
                    )
                    .id("mac-main-composer")
                }
#endif
                if selectedSection == .now {
                    nowTaskContent
                } else {
                    allItemsContent
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, scrollBottomPadding)
            .frame(maxWidth: .infinity)
        }
#if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(
            TapGesture().onEnded {
                dismissAppKeyboard()
            }
        )
#endif
        .background(MemoryTheme.background)
    }

    private var scrollBottomPadding: CGFloat {
#if os(iOS)
        selectedSection == .now ? 72 : 44
#else
        36
#endif
    }

#if os(iOS)
    private func dismissAppKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
#endif

    @ViewBuilder private var pageHeader: some View {
        if selectedSection == .now {
            nowPageHeader
        } else {
            standardPageHeader
        }
    }

    private var nowPageHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("NORKA")
                    .font(.caption2.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(MemoryTheme.accent)

                Text("Сегодня")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.8)

                Text(Self.mainDateFormatter.string(from: currentDate))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)
#if os(iOS)
            mobileAccountButton
#endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var standardPageHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(isInboxPresented && selectedSection == .all ? "Входящие" : selectedSection.title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text(isInboxPresented && selectedSection == .all ? "Напоминания без срока" : selectedSection.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
#if os(iOS)
            mobileAccountButton
#else
            if selectedSection == .all {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isInboxPresented.toggle()
                    }
                } label: {
                    Label(
                        isInboxPresented ? "Все записи" : "Входящие \(inboxItems.count)",
                        systemImage: isInboxPresented ? "arrow.left" : "tray.full.fill"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
#endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

#if os(iOS)
    private var mobileAccountButton: some View {
        Button {
            openMobileProfile()
        } label: {
            Image(systemName: "person.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 52, height: 52)
                .background(Color.primary.opacity(0.065))
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(Color.primary.opacity(0.07), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Профиль")
    }
#endif

    private static let mainDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter
    }()

    private static let homeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM, yyyy"
        return formatter
    }()

#if os(macOS)
    private var notificationSettingsBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MemoryTheme.warm)
                .frame(width: 34, height: 34)
                .background(MemoryTheme.warm.opacity(0.13))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Уведомления выключены")
                    .font(.subheadline.weight(.semibold))
                Text("Norka сохранит задачи, но не сможет напомнить о них")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button("Открыть настройки") {
                openNotificationSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(14)
        .background(MemoryTheme.warm.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MemoryTheme.warm.opacity(0.2), lineWidth: 1)
        }
    }
#endif

    @ViewBuilder private var nowTaskContent: some View {
        if !overdueItems.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                MemorySectionHeader(
                    title: "Просрочено",
                    subtitle: "Лучше разобраться с этим сначала",
                    count: overdueItems.count,
                    icon: "exclamationmark",
                    color: .red
                )
                taskRows(overdueItems)
            }
        }

        VStack(alignment: .leading, spacing: 12) {
            MemorySectionHeader(
                title: "Сегодня",
                subtitle: todayItems.isEmpty ? "На сегодня ничего не запланировано" : "Главное на ближайшее время",
                count: todayItems.count,
                icon: "sun.max.fill",
                color: MemoryTheme.warm
            )

            if todayItems.isEmpty {
                TodayEmptyView(hasUpcomingItems: !upcomingItems.isEmpty)
            } else {
                taskRows(todayItems)
            }
        }
    }

    @ViewBuilder private var allItemsContent: some View {
        if isInboxPresented {
            inboxSearchField
            if searchedInboxItems.isEmpty {
                RecordsEmptyView(
                    icon: inboxSearchTextIsEmpty ? "tray" : "magnifyingglass",
                    title: inboxSearchTextIsEmpty ? "Входящие пусты" : "Ничего не нашлось",
                    message: inboxSearchTextIsEmpty
                        ? "Напоминания без срока появятся здесь."
                        : "Попробуйте другой запрос."
                )
            } else {
                taskRows(searchedInboxItems)
            }
        } else {
            searchField
            activeItemsListContent
        }
    }

    @ViewBuilder private var activeItemsListContent: some View {
        if searchedDatedActiveItems.isEmpty {
            RecordsEmptyView(
                icon: searchTextIsEmpty ? "sparkles" : "magnifyingglass",
                title: searchTextIsEmpty ? "Нет записей с датой" : "Ничего не нашлось",
                message: searchTextIsEmpty
                    ? "Записи без срока находятся во Входящих."
                    : "Попробуйте другой запрос."
            )
        } else {
            ForEach(datedItemGroups) { group in
                let groupItems = groupedActiveItems[group] ?? []
                if !groupItems.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        MemorySectionHeader(
                            title: group.title,
                            subtitle: nil,
                            count: groupItems.count,
                            icon: group.icon,
                            color: group.color
                        )
                        taskRows(groupItems)
                    }
                }
            }
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

    private var inboxSearchField: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Поиск во входящих", text: $inboxSearchText).textFieldStyle(.plain)
            if !inboxSearchText.isEmpty {
                Button { inboxSearchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(16)
        .memoryCard()
    }

    private func taskRows(_ source: [Item]) -> some View {
        LazyVStack(spacing: 10) {
            ForEach(source, id: \.persistentModelID) { item in
                MemoryItemRow(
                    item: item,
                    onToggle: { toggleCompleted(item) },
                    onEdit: {
                        guard !suppressItemOpening else { return }
                        editingItem = item
                    },
                    onDelete: { delete(item) }
                )
            }
        }
    }

    private var accountItems: [Item] {
        items.filter { $0.deletedAt == nil && $0.ownerID == account.userID }
    }

    private var activeItems: [Item] {
        sorted(accountItems.filter {
            !$0.isCompleted && $0.dueDate != nil && !isPastEventArchived($0)
        })
    }
    private var overdueItems: [Item] {
        activeItems.filter {
            if $0.isEvent { return false }
            return ($0.dueDate ?? .distantFuture) < currentDate
        }
    }
    private var todayItems: [Item] {
        activeItems.filter {
            guard let dueDate = $0.dueDate else { return false }
            if $0.isEvent {
                return eventOccursToday($0)
            }
            return dueDate >= currentDate && Calendar.current.isDate(dueDate, inSameDayAs: currentDate)
        }
    }
    private var upcomingItems: [Item] {
        let tomorrow = Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: Calendar.current.startOfDay(for: currentDate)
        ) ?? .distantFuture
        return activeItems.filter { ($0.dueDate ?? .distantPast) >= tomorrow }
    }
    private var completedItems: [Item] {
        accountItems
            .filter { $0.isCompleted || isPastEventArchived($0) }
            .sorted {
                ($0.completedAt ?? $0.endDate ?? $0.dueDate ?? $0.updatedAt)
                    > ($1.completedAt ?? $1.endDate ?? $1.dueDate ?? $1.updatedAt)
            }
    }

    private var searchTextIsEmpty: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchedActiveItems: [Item] {
        sorted(accountItems.filter {
            !$0.isCompleted && !isPastEventArchived($0) && matchesSearch($0)
        })
    }

    private var searchedDatedActiveItems: [Item] {
        searchedActiveItems.filter { $0.dueDate != nil }
    }

    private var inboxItems: [Item] {
        sorted(accountItems.filter {
            !$0.isCompleted && !$0.isEvent && $0.dueDate == nil
        })
    }

    private var searchedInboxItems: [Item] {
        inboxItems.filter(matchesInboxSearch)
    }

    private var searchedCompletedItems: [Item] {
        completedItems.filter(matchesArchiveSearch)
    }

    private var archiveSearchTextIsEmpty: Bool {
        archiveSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var inboxSearchTextIsEmpty: Bool {
        inboxSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var datedItemGroups: [AllItemsGroup] {
        [.overdue, .today, .tomorrow, .week, .later]
    }

    private var groupedActiveItems: [AllItemsGroup: [Item]] {
        Dictionary(grouping: searchedDatedActiveItems, by: group(for:))
    }

    private func matchesSearch(_ item: Item) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return item.title.localizedCaseInsensitiveContains(query)
            || (item.details?.localizedCaseInsensitiveContains(query) ?? false)
    }

    private func matchesArchiveSearch(_ item: Item) -> Bool {
        let query = archiveSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return item.title.localizedCaseInsensitiveContains(query)
            || (item.details?.localizedCaseInsensitiveContains(query) ?? false)
    }

    private func matchesInboxSearch(_ item: Item) -> Bool {
        let query = inboxSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return item.title.localizedCaseInsensitiveContains(query)
            || (item.details?.localizedCaseInsensitiveContains(query) ?? false)
    }

    private func group(for item: Item) -> AllItemsGroup {
        AllItemsGroup.group(for: item, now: currentDate)
    }

    private func eventOccursToday(_ item: Item) -> Bool {
        guard item.isEvent, let startDate = item.dueDate else { return false }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: currentDate)
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: item.endDate ?? startDate)
        return today >= startDay && today <= endDay
    }

    private func isPastEventArchived(_ item: Item) -> Bool {
        guard item.isEvent, let startDate = item.dueDate else { return false }
        let finalDate = item.endDate ?? startDate
        let calendar = Calendar.current
        let nextDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: finalDate)
        ) ?? finalDate
        return currentDate >= nextDay
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

    @discardableResult
    private func addItem(
        title: String,
        details: String?,
        entryKind: EntryKind = .reminder,
        dueDate: Date?,
        endDate: Date? = nil,
        reminderOffsets: [Int]? = nil
    ) -> UUID? {
        guard entryKind != .event || dueDate != nil else {
            errorMessage = "Для события укажите дату и время начала."
            return nil
        }
        let item = Item(
            title: title,
            details: details,
            dueDate: dueDate,
            entryKind: entryKind,
            endDate: endDate,
            reminderOffsets: dueDate == nil
                ? []
                : (reminderOffsets ?? [account.defaultReminderMinutes]),
            ownerID: account.userID
        )
        withAnimation(.snappy) { modelContext.insert(item) }
        guard saveChanges() else { return nil }
        scheduleReminder(for: item)
        account.markLocalChange(modelContext: modelContext)
        showCaptureConfirmation(for: item)
        return item.id
    }

    private func voiceReviewPage(_ session: VoiceBatchReviewSession) -> some View {
        VoiceBatchReviewView(
            session: session,
            onCancel: { cancelVoiceReview(session.batch) },
            onSave: { finishVoiceReview(session) },
            header: {
#if os(iOS)
                mobilePrimaryHeader
#else
                EmptyView()
#endif
            }
        )
        .id(session.id)
    }

    private func presentVoiceBatch(_ batch: VoiceBatchReview) {
        let candidate = VoiceBatchReviewSession(batch: batch)
        let presented = candidate.canSave
            ? (persistVoiceBatch(batch.entries, referenceDate: batch.referenceDate) ?? batch)
            : batch
        recentlyAddedItem = nil
        recentlyAddedBatchCount = nil
        editingItem = nil
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            voiceReviewSession = VoiceBatchReviewSession(batch: presented)
        }
    }

    private func requestVoiceReviewExit(_ action: @escaping () -> Void) {
        guard let session = voiceReviewSession else {
            action()
            return
        }
        if session.hasChanges || session.selectedEntryID != nil || !session.batch.isPersisted {
            pendingReviewNavigation = action
            isReviewExitConfirmationPresented = true
        } else {
            dismissVoiceReview()
            action()
        }
    }

    private func completeReviewNavigation() {
        let action = pendingReviewNavigation
        pendingReviewNavigation = nil
        action?()
    }

    private func finishVoiceReview(_ session: VoiceBatchReviewSession) -> Bool {
        if VoiceReviewTesting.isEnabled {
            dismissVoiceReview()
            return true
        }
        let entries = session.entries
        let batch = session.batch
        let savedEntries: [VoiceReviewEntry]
        if batch.isPersisted {
            if entries != batch.entries,
               !updateVoiceBatch(entries, original: batch.entries) {
                return false
            }
            savedEntries = entries
        } else {
            guard let persisted = persistVoiceBatch(entries, referenceDate: batch.referenceDate),
                  persisted.isPersisted else {
                return false
            }
            savedEntries = persisted.entries
        }
        for entry in savedEntries {
            guard let itemID = entry.persistedItemID else { continue }
            let correctedDetails = Item.normalizedDetails(entry.details)
            if entry.title != entry.originalDraft.title
                || correctedDetails != entry.originalDraft.details
                || entry.dueDate != entry.originalDraft.dueDate {
                VoicePersonalizationStore.confirmCorrection(
                    itemID: itemID,
                    title: entry.title,
                    details: correctedDetails,
                    dueDate: entry.dueDate
                )
            }
        }
        dismissVoiceReview()
        return true
    }

    private func cancelVoiceReview(_ batch: VoiceBatchReview) {
        if VoiceReviewTesting.isEnabled {
            dismissVoiceReview()
            return
        }
        guard !batch.isPersisted || cancelVoiceBatch(batch.entries) else { return }
        dismissVoiceReview()
    }

    private func dismissVoiceReview() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            voiceReviewSession = nil
        }
    }

    private func persistVoiceBatch(
        _ entries: [VoiceReviewEntry],
        referenceDate: Date
    ) -> VoiceBatchReview? {
        guard let itemIDs = addVoiceBatch(entries), itemIDs.count == entries.count else {
            return nil
        }
        let persisted = zip(entries, itemIDs).map { entry, itemID -> VoiceReviewEntry in
            var value = entry
            value.persistedItemID = itemID
            VoicePersonalizationStore.beginCapture(
                itemID: itemID,
                transcript: entry.sourceText,
                title: entry.originalDraft.title,
                details: entry.originalDraft.details,
                dueDate: entry.originalDraft.dueDate,
                referenceDate: referenceDate
            )
            return value
        }
        return VoiceBatchReview(referenceDate: referenceDate, entries: persisted)
    }

    private func addVoiceBatch(_ entries: [VoiceReviewEntry]) -> [UUID]? {
        guard !entries.isEmpty,
              entries.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && ($0.kind != .event || $0.dueDate != nil)
                  && ($0.endDate == nil || ($0.dueDate != nil && $0.endDate! >= $0.dueDate!)) }) else {
            return nil
        }
        let newItems = entries.map { entry in
            Item(
                title: entry.title.trimmingCharacters(in: .whitespacesAndNewlines),
                details: entry.details,
                dueDate: entry.dueDate,
                entryKind: entry.kind,
                endDate: entry.kind == .event ? entry.endDate : nil,
                reminderOffsets: entry.dueDate == nil ? [] : entry.reminderOffsets,
                ownerID: account.userID
            )
        }
        withAnimation(.snappy) {
            newItems.forEach(modelContext.insert)
        }
        guard saveChanges() else { return nil }
        newItems.forEach(scheduleReminder)
        account.markLocalChange(modelContext: modelContext)
#if os(macOS)
        if isDesktopComposerPresented {
            withAnimation(.easeInOut(duration: 0.2)) { isDesktopComposerPresented = false }
        }
#endif
        return newItems.map(\.id)
    }

    private func updateVoiceBatch(
        _ entries: [VoiceReviewEntry],
        original: [VoiceReviewEntry]
    ) -> Bool {
        guard !entries.isEmpty,
              entries.allSatisfy({
                  $0.persistedItemID != nil
                      && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && ($0.kind != .event || $0.dueDate != nil)
                      && ($0.endDate == nil || ($0.dueDate != nil && $0.endDate! >= $0.dueDate!))
              }),
              let stored = storedVoiceBatchItems(original) else {
            errorMessage = "Не удалось найти сохранённые записи для редактирования."
            return false
        }

        let edited = Dictionary(uniqueKeysWithValues: entries.compactMap { entry in
            entry.persistedItemID.map { ($0, entry) }
        })
        let removedIDs = original.compactMap(\.persistedItemID).filter { edited[$0] == nil }
        for (id, item) in stored {
            guard let entry = edited[id] else {
                item.markDeleted()
                continue
            }
            item.title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            item.details = Item.normalizedDetails(entry.details)
            item.entryKind = entry.kind
            item.dueDate = entry.dueDate
            item.endDate = entry.kind == .event ? entry.endDate : nil
            item.setReminderOffsets(entry.dueDate == nil ? [] : entry.reminderOffsets)
            item.updatedAt = .now
        }
        guard saveChanges() else { return false }
        stored.values.forEach(scheduleReminder)
        VoicePersonalizationStore.discardCaptures(for: removedIDs)
        account.markLocalChange(modelContext: modelContext)
        return true
    }

    private func cancelVoiceBatch(_ entries: [VoiceReviewEntry]) -> Bool {
        guard let stored = storedVoiceBatchItems(entries) else {
            errorMessage = "Не удалось найти записи для отмены."
            return false
        }
        stored.values.forEach { $0.markDeleted() }
        guard saveChanges() else { return false }
        let ids = Array(stored.keys)
        for id in ids {
            ReminderScheduler.cancel(id: id)
        }
        VoicePersonalizationStore.discardCaptures(for: ids)
        account.markLocalChange(modelContext: modelContext)
        return true
    }

    private func storedVoiceBatchItems(_ entries: [VoiceReviewEntry]) -> [UUID: Item]? {
        let ids = Set(entries.compactMap(\.persistedItemID))
        guard ids.count == entries.count,
              let stored = try? modelContext.fetch(FetchDescriptor<Item>()) else {
            return nil
        }
        let matching = stored.filter { ids.contains($0.id) && $0.deletedAt == nil }
        guard matching.count == ids.count else { return nil }
        return Dictionary(uniqueKeysWithValues: matching.map { ($0.id, $0) })
    }

    private func openDetailedDraft(
        title: String,
        details: String?,
        entryKind: EntryKind,
        dueDate: Date?,
        endDate: Date?
    ) {
        let startDate = dueDate ?? (entryKind == .event ? Self.defaultEventStartDate : nil)
        let draft = Item(
            title: title,
            details: details,
            dueDate: startDate,
            entryKind: entryKind,
            endDate: entryKind == .event ? endDate : nil,
            reminderOffsets: startDate == nil ? [] : [account.defaultReminderMinutes],
            ownerID: account.userID
        )

        dismissKeyboardIfAvailable()
#if os(macOS)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
            isDesktopComposerPresented = false
            isEditingNewDesktopItem = true
            editingItem = draft
        }
#else
        draftEditingItem = draft
#endif
    }

    private static var defaultEventStartDate: Date {
        let calendar = Calendar.current
        let candidate = calendar.date(byAdding: .hour, value: 1, to: .now) ?? .now.addingTimeInterval(3_600)
        return calendar.date(bySetting: .minute, value: 0, of: candidate) ?? candidate
    }

    private func dismissKeyboardIfAvailable() {
#if os(iOS)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
#endif
    }

    private var remoteVoiceInterpreter: (String, Date, Calendar) async throws -> VoiceCaptureResult {
        { transcript, now, calendar in
            try await account.interpretVoiceRemotely(
                transcript,
                now: now,
                calendar: calendar
            )
        }
    }

    private func update(
        _ item: Item,
        title: String,
        details: String?,
        entryKind: EntryKind,
        dueDate: Date?,
        endDate: Date?,
        reminderOffsets: [Int]
    ) {
        item.title = title
        item.details = Item.normalizedDetails(details)
        item.entryKind = entryKind
        item.dueDate = dueDate
        item.endDate = entryKind == .event ? endDate : nil
        item.setReminderOffsets(dueDate == nil ? [] : reminderOffsets)
        item.updatedAt = .now
        guard saveChanges() else { return }
        VoicePersonalizationStore.confirmCorrection(
            itemID: item.id,
            title: item.title,
            details: item.details,
            dueDate: item.dueDate
        )
        scheduleReminder(for: item)
        account.markLocalChange(modelContext: modelContext)
    }

    private func showCaptureConfirmation(for item: Item) {
        let itemID = item.id
        withAnimation(.snappy) {
            recentlyAddedBatchCount = nil
            recentlyAddedItem = item
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard recentlyAddedItem?.id == itemID else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                recentlyAddedItem = nil
            }
        }
    }

    private func showBatchConfirmation(count: Int) {
        batchConfirmationVersion += 1
        let version = batchConfirmationVersion
        withAnimation(.snappy) {
            recentlyAddedItem = nil
            recentlyAddedBatchCount = count
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard batchConfirmationVersion == version else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                recentlyAddedBatchCount = nil
            }
        }
    }

    private func toggleCompleted(_ item: Item) {
        withAnimation(.snappy) { item.setCompleted(!item.isCompleted) }
        guard saveChanges() else { return }
        item.isCompleted ? ReminderScheduler.cancel(id: item.id) : scheduleReminder(for: item)
        account.markLocalChange(modelContext: modelContext)
    }

    private func delete(_ item: Item) {
        let id = item.id
        withAnimation(.snappy) { item.markDeleted() }
        guard saveChanges() else { return }
        ReminderScheduler.cancel(id: id)
        account.markLocalChange(modelContext: modelContext)
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
        guard item.deletedAt == nil,
              !item.isCompleted,
              item.notificationsEnabled,
              let date = item.dueDate else {
            ReminderScheduler.cancel(id: item.id)
            return
        }
        let id = item.id
        let title = item.title
        let details = item.details
        let offsets = item.effectiveReminderOffsets
        Task {
            do {
                try await ReminderScheduler.schedule(
                    id: id,
                    title: title,
                    details: details,
                    at: date,
                    offsets: offsets
                )
            }
            catch ReminderError.notificationsDisabled {
#if os(macOS)
                notificationsAreDisabled = true
#else
                errorMessage = ReminderError.notificationsDisabled.localizedDescription
#endif
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

#if os(macOS)
    private func refreshNotificationStatus() async {
        notificationsAreDisabled = await ReminderScheduler.notificationsAreDisabled()
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
#endif

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

    private func synchronize() async {
        await account.synchronize(modelContext: modelContext)
        for item in items {
            if item.ownerID == account.userID {
                scheduleReminder(for: item)
            } else {
                ReminderScheduler.cancel(id: item.id)
            }
        }
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

enum EntryKindInference {
    static func infer(from text: String, hasDate: Bool) -> EntryKind? {
        let normalized = text
            .lowercased(with: Locale(identifier: "ru_RU"))
            .replacingOccurrences(of: "ё", with: "е")
        let hasExplicitRange = normalized.contains(" с ")
            && (normalized.contains(" до ")
                || normalized.contains(" по ")
                || normalized.contains("—")
                || normalized.contains("–"))
        let actionMarkers = [
            "надо ", "нужно ", "не забыть", "напомни", "напомнить"
        ]
        let actionStems = [
            "купит", "сдела", "отправ", "позвон", "напис", "забрат",
            "оплат", "провер", "подготов", "подат", "заказ", "записат",
            "зайти", "сходить", "получит", "вернут", "доработ", "закончит"
        ]
        let eventPhrases = [
            "встреча", "встречу", "встретиться", "созвон", "вебинар",
            "концерт", "прием", "трениров", "занят", "лекци", "урок",
            "сеанс", "бронь", "перелет", "рейс", "поездка", "отпуск",
            "конференц", "мероприят", "собеседован", "экзамен",
            "день рождения", "годовщина"
        ]
        let hasAction = actionMarkers.contains(where: normalized.contains)
            || actionStems.contains(where: normalized.contains)
        let hasEventNoun = eventPhrases.contains(where: normalized.contains)

        if hasAction && !normalized.contains("встретиться") {
            return .reminder
        }
        if hasEventNoun {
            return .event
        }
        if hasDate && hasExplicitRange {
            return .event
        }
        return nil
    }
}

private enum QuickCaptureFocus: Hashable {
    case title
    case description
}

private enum QuickCapturePresentation {
    case standard
#if os(macOS)
    case desktopWorkspace
    case desktopInline
#endif
}

private struct PendingVoiceClarification {
    let decision: VoiceClarificationDecision
    let draft: ReminderDraft
    let details: String?
    let fallbackDate: Date?
    let referenceDate: Date
}

private struct VoiceClarificationOption: Identifiable {
    let id: String
    let title: String
    let caption: String?
    let dueDate: Date?
}

private struct QuickCaptureSurfaceModifier: ViewModifier {
    let isMinimal: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isMinimal {
            content
                .background(Color.primary.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            content.memoryCard()
        }
    }
}

private struct QuickCaptureCard: View {
    @EnvironmentObject private var account: AccountSyncController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var voiceInput = VoiceInputController()
    @AppStorage(VoicePipelineSettings.structuredInterpreterEnabledKey)
    private var isStructuredInterpreterEnabled = false
    @AppStorage(VoicePipelineSettings.deepSeekInterpreterEnabledKey)
    private var isDeepSeekInterpreterEnabled = false
    @AppStorage(VoicePipelineSettings.clarificationEnabledKey)
    private var isVoiceClarificationEnabled = true
    @State private var draft = ""
    @State private var preset: QuickDuePreset
    @State private var ignoredSmartExpression: String?
    @State private var ignoredKindExpression: String?
    @State private var entryKindOverride: EntryKind?
    @State private var smartResult: ParsedMemoryInput?
    @State private var details = ""
    @State private var isDescriptionPresented = false
    @State private var isVoicePulsing = false
    @State private var smartParsingTask: Task<Void, Never>?
    @State private var voiceSubmissionTask: Task<Void, Never>?
    @State private var shouldSubmitVoiceWhenStopped = false
    @State private var isFinalizingVoiceSubmission = false
    @State private var voiceProcessingStartedAt = Date.now
    @State private var pendingVoiceClarification: PendingVoiceClarification?
    @State private var isRecordsComposerPresented = false
    @Namespace private var homeComposerNamespace
    @Namespace private var captureChromeNamespace
    @FocusState private var focusedField: QuickCaptureFocus?
    let defaultPreset: QuickDuePreset
    let presentation: QuickCapturePresentation
    let isDocked: Bool
    let isHome: Bool
    let isRecordsPage: Bool
    let externalKeyboardVisible: Bool
    let priorityItem: Item?
    let isPriorityOverdue: Bool
    let additionalPriorityCount: Int
    let autofocus: Bool
    let detailCommitSignal: Int
    let remoteVoiceInterpreter: ((String, Date, Calendar) async throws -> VoiceCaptureResult)?
    let onTogglePriority: () -> Void
    let onEditPriority: () -> Void
    let onShowAll: () -> Void
    let onDismiss: () -> Void
    let onOpenDetails: (String, String?, EntryKind, Date?, Date?) -> Void
    let onReviewBatch: (VoiceBatchReview) -> Void
    let onAdd: (String, String?, EntryKind, Date?, Date?, [Int]?) -> UUID?

    init(
        defaultPreset: QuickDuePreset,
        presentation: QuickCapturePresentation = .standard,
        isDocked: Bool = false,
        isHome: Bool = false,
        isRecordsPage: Bool = false,
        externalKeyboardVisible: Bool = false,
        priorityItem: Item? = nil,
        isPriorityOverdue: Bool = false,
        additionalPriorityCount: Int = 0,
        autofocus: Bool = false,
        detailCommitSignal: Int = 0,
        remoteVoiceInterpreter: ((String, Date, Calendar) async throws -> VoiceCaptureResult)? = nil,
        onTogglePriority: @escaping () -> Void = {},
        onEditPriority: @escaping () -> Void = {},
        onShowAll: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {},
        onOpenDetails: @escaping (String, String?, EntryKind, Date?, Date?) -> Void = { _, _, _, _, _ in },
        onReviewBatch: @escaping (VoiceBatchReview) -> Void = { _ in },
        onAdd: @escaping (String, String?, EntryKind, Date?, Date?, [Int]?) -> UUID?
    ) {
        _preset = State(initialValue: defaultPreset)
        self.defaultPreset = defaultPreset
        self.presentation = presentation
        self.isDocked = isDocked
        self.isHome = isHome
        self.isRecordsPage = isRecordsPage
        self.externalKeyboardVisible = externalKeyboardVisible
        self.priorityItem = priorityItem
        self.isPriorityOverdue = isPriorityOverdue
        self.additionalPriorityCount = additionalPriorityCount
        self.autofocus = autofocus
        self.detailCommitSignal = detailCommitSignal
        self.remoteVoiceInterpreter = remoteVoiceInterpreter
        self.onTogglePriority = onTogglePriority
        self.onEditPriority = onEditPriority
        self.onShowAll = onShowAll
        self.onDismiss = onDismiss
        self.onOpenDetails = onOpenDetails
        self.onReviewBatch = onReviewBatch
        self.onAdd = onAdd
    }

    var body: some View {
        Group {
#if os(macOS)
            if presentation == .desktopWorkspace {
                desktopCaptureBody
            } else if isHome {
                homeBody
            } else {
                compactBody
            }
#else
            if isHome {
                ZStack {
                    if isRecordsPage {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)
                    } else {
                        homeBody
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            } else {
                compactBody
            }
#endif
        }
        .overlay(alignment: .bottom) {
            if isHome,
               isRecordsPage,
               !isRecordsComposerPresented,
               !externalKeyboardVisible,
               !voiceInput.isListening,
               !isFinalizingVoiceSubmission,
               pendingVoiceClarification == nil {
                sharedCaptureChrome
                    .frame(maxWidth: .infinity)
                    .transition(.scale(scale: 0.86, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 18) {
            if isHome,
               (!isRecordsPage || isRecordsComposerPresented),
               !voiceInput.isListening,
               !isFinalizingVoiceSubmission,
               pendingVoiceClarification == nil {
                sharedCaptureChrome
                    .frame(maxWidth: .infinity)
                    .background {
                        MemoryTheme.background
                            .ignoresSafeArea(edges: .bottom)
                    }
                }
        }
        .animation(.spring(response: 0.46, dampingFraction: 0.9), value: smartResult != nil)
        .animation(.spring(response: 0.52, dampingFraction: 0.88), value: voiceInput.isListening)
        .animation(.easeInOut(duration: 0.28), value: isFinalizingVoiceSubmission)
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: pendingVoiceClarification != nil)
        .animation(.easeInOut(duration: 0.22), value: isDescriptionPresented)
        .animation(.spring(response: 0.46, dampingFraction: 0.9), value: isComposerExpanded)
        .onChange(of: draft) { oldValue, newValue in
            if !voiceInput.isListening,
               Self.isSingleInsertedLineBreak(from: oldValue, to: newValue) {
                draft = oldValue
                submit()
                return
            }

            smartParsingTask?.cancel()
            if isVoicePreviewActive,
               VoiceCapturePreview.classify(newValue) != .single {
                // One inferred date/type must not describe an uncertain batch.
                smartResult = nil
                return
            }
            smartParsingTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(voiceInput.isListening ? 160 : 70))
                guard !Task.isCancelled else { return }
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                smartResult = ignoredSmartExpression == newValue
                    ? nil
                    : NaturalLanguageDateParser.parse(trimmed)
            }
        }
        .onAppear {
            guard autofocus else { return }
            DispatchQueue.main.async {
                focusedField = .title
            }
        }
        .onChange(of: details) { oldValue, newValue in
            guard !voiceInput.isListening,
                  Self.isSingleInsertedLineBreak(from: oldValue, to: newValue) else { return }
            details = oldValue
            submit()
        }
        .onChange(of: detailCommitSignal) { _, _ in
            resetAfterDetailedCommit()
        }
        .onChange(of: voiceInput.transcript) { _, newValue in
            guard !newValue.isEmpty else { return }
            ignoredSmartExpression = nil
            draft = newValue
        }
        .onChange(of: voiceInput.isListening) { wasListening, isListening in
            if isListening {
                isFinalizingVoiceSubmission = false
                isVoicePulsing = false
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    isVoicePulsing = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.35)) { isVoicePulsing = false }
                if wasListening && shouldSubmitVoiceWhenStopped {
                    voiceProcessingStartedAt = .now
                    isFinalizingVoiceSubmission = true
                    voiceSubmissionTask?.cancel()
                    voiceSubmissionTask = Task { @MainActor in
                        await Task.yield()
                        guard !Task.isCancelled,
                              shouldSubmitVoiceWhenStopped,
                              !voiceInput.isListening else { return }
                        await submitVoiceRecording()
                        shouldSubmitVoiceWhenStopped = false
                        withAnimation(.easeOut(duration: 0.2)) {
                            isFinalizingVoiceSubmission = false
                        }
                    }
                }
            }
        }
        .onChange(of: isRecordsPage) { _, recordsPage in
            focusedField = nil
            withAnimation(.easeOut(duration: 0.16)) {
                isRecordsComposerPresented = false
            }
            if recordsPage && voiceInput.isListening {
                shouldSubmitVoiceWhenStopped = false
                voiceInput.stop()
            }
        }
        .onDisappear {
            shouldSubmitVoiceWhenStopped = false
            isFinalizingVoiceSubmission = false
            voiceSubmissionTask?.cancel()
            smartParsingTask?.cancel()
            voiceInput.stop()
            pendingVoiceClarification = nil
        }
        .alert("Голосовой ввод", isPresented: isShowingVoiceError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(voiceInput.errorMessage ?? "Не удалось распознать речь.")
        }
    }


    @ViewBuilder private var sharedCaptureChrome: some View {
        if isRecordsPage && !isRecordsComposerPresented {
            if !externalKeyboardVisible {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isRecordsComposerPresented = true
                        }
                        DispatchQueue.main.async {
                            focusedField = .title
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(MemoryTheme.accent)
                            .clipShape(Circle())
                            .overlay {
                                Circle().stroke(Color.white.opacity(0.16), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Добавить напоминание")
                    .matchedGeometryEffect(id: "captureChrome", in: captureChromeNamespace)
                    .zIndex(20)
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, 22)
                .padding(.bottom, 10)
            }
        } else {
            homeComposer
                .matchedGeometryEffect(id: "homeComposer", in: homeComposerNamespace)
                .matchedGeometryEffect(id: "captureChrome", in: captureChromeNamespace)
                .frame(maxWidth: 620)
                .padding(.horizontal, 22)
                .padding(.bottom, 10)
        }
    }

#if os(macOS)
    private var desktopCaptureBody: some View {
        VStack(spacing: 28) {
            desktopOrbCluster(size: 164)
            compactBody
                .frame(maxWidth: 540)
                .opacity(isFinalizingVoiceSubmission || pendingVoiceClarification != nil ? 0 : 1)
                .allowsHitTesting(!isFinalizingVoiceSubmission && pendingVoiceClarification == nil)
                .accessibilityHidden(isFinalizingVoiceSubmission || pendingVoiceClarification != nil)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 18)
        .padding(.horizontal, 28)
    }

    private func desktopOrbCluster(size: CGFloat) -> some View {
        VStack(spacing: 18) {
            Button(action: handleVoiceTap) {
                GlassVoiceOrb(
                    isListening: voiceInput.isListening,
                    isProcessing: isFinalizingVoiceSubmission,
                    isPulsing: isVoicePulsing || isFinalizingVoiceSubmission,
                    size: size
                )
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isFinalizingVoiceSubmission || pendingVoiceClarification != nil)
            .accessibilityLabel(voiceOrbAccessibilityLabel)

            Group {
                if pendingVoiceClarification != nil {
                    voiceClarificationCard
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if isFinalizingVoiceSubmission {
                    voiceProcessingStatus
                        .transition(.opacity)
                } else {
                    VStack(spacing: 5) {
                        Text(voiceInput.isListening ? "Говорите…" : "Что нужно запомнить?")
                            .font(.system(size: 19, weight: .medium, design: .rounded))
                            .multilineTextAlignment(.center)

                        Text(voiceInput.isListening ? "Нажмите на сферу, чтобы закончить" : "Голосом или текстом")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                }
            }
        }
    }
#endif

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: isDocked ? 10 : 14) {
            HStack(spacing: isDocked ? 10 : 12) {
                if presentation != .standard && !voiceInput.isListening {
                    Button(action: submit) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(trimmedDraft.isEmpty ? Color.secondary : Color.white)
                            .frame(width: compactControlSize, height: compactControlSize)
                            .background(
                                trimmedDraft.isEmpty
                                    ? Color.secondary.opacity(0.1)
                                    : MemoryTheme.accent
                            )
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmedDraft.isEmpty)
                    .accessibilityLabel("Добавить напоминание")
                } else if isDocked {
                    voiceButton(size: compactControlSize)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(MemoryTheme.accent)
                        .frame(width: compactControlSize, height: compactControlSize)
                        .background(MemoryTheme.accent.opacity(0.12))
                        .clipShape(Circle())
                }

                TextField(
                    voiceInput.isListening ? "Говорите…" : "Что нужно запомнить?",
                    text: $draft,
                    axis: .vertical
                )
                    .textFieldStyle(.plain)
                    .lineLimit(1...(voiceInput.isListening ? 4 : 2))
                    .focused($focusedField, equals: .title)
                    .allowsHitTesting(!voiceInput.isListening)
                    .accessibilityIdentifier("quickCaptureField")
                    .onSubmit(handleSubmitKey)
#if os(iOS)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.sentences)
#endif

                if !isDocked && presentation == .standard {
                    voiceButton(size: compactControlSize)
                }

                if !voiceInput.isListening && isComposerExpanded {
                    detailsDisclosureButton(size: compactControlSize)
                }

                if showsCancelButton {
                    Button(action: cancelDraft) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: compactControlSize, height: compactControlSize)
                            .background(Color.secondary.opacity(0.09))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Отменить ввод")
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }

            captureMetadataChips

            if isDescriptionPresented {
                TextField("Описание, ссылка или важные детали", text: $details, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...5)
                    .focused($focusedField, equals: .description)
#if os(iOS)
                    .submitLabel(.done)
                    .onSubmit(handleSubmitKey)
#endif
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                    }
                    .accessibilityIdentifier("quickCaptureDescriptionField")
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

        }
        .padding(usesMinimalDesktopChrome ? 12 : (isDocked ? 12 : 18))
        .modifier(QuickCaptureSurfaceModifier(isMinimal: usesMinimalDesktopChrome))
    }

    private var homeBody: some View {
        GeometryReader { proxy in
            let isEditing = focusedField != nil
            let orbSize = isEditing || proxy.size.height < 520
                ? 112
                : min(190, max(150, proxy.size.height * 0.25))

            VStack(spacing: 0) {
                VStack(spacing: voiceInput.isListening ? 38 : 30) {
                    homeVoiceOrb(orbSize: orbSize)
                        .offset(y: voiceInput.isListening ? -8 : 0)

                    ZStack(alignment: .top) {
                        Text("Скажи, о чём тебе нужно напомнить?")
                            .font(.system(size: 26, weight: .medium, design: .rounded))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.78)
                            .frame(maxWidth: 380)
                            .opacity(
                                voiceInput.isListening
                                    || isEditing
                                    || isFinalizingVoiceSubmission
                                    || pendingVoiceClarification != nil
                                    ? 0 : 1
                            )

                        if pendingVoiceClarification != nil {
                            voiceClarificationCard
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else if voiceInput.isListening {
                            homeComposer
                                .matchedGeometryEffect(id: "homeComposer", in: homeComposerNamespace)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else if isFinalizingVoiceSubmission {
                            voiceProcessingStatus
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }
                    }
                    .frame(height: 180, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                VStack(spacing: 18) {
                    if !isEditing {
                        homePrioritySection
                    }
                }
                .opacity(
                    voiceInput.isListening || isFinalizingVoiceSubmission || pendingVoiceClarification != nil
                        ? 0 : 1
                )
                .allowsHitTesting(
                    !voiceInput.isListening
                        && !isFinalizingVoiceSubmission
                        && pendingVoiceClarification == nil
                )
            }
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 22)
            .contentShape(Rectangle())
            .onTapGesture {
                guard focusedField != nil else { return }
                dismissKeyboard()
            }
        }
    }

    private func homeVoiceOrb(orbSize: CGFloat) -> some View {
        Button(action: handleHomeVoiceTap) {
            GlassVoiceOrb(
                isListening: voiceInput.isListening,
                isProcessing: isFinalizingVoiceSubmission,
                isPulsing: isVoicePulsing || isFinalizingVoiceSubmission,
                size: orbSize
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isFinalizingVoiceSubmission || pendingVoiceClarification != nil)
        .accessibilityLabel(voiceOrbAccessibilityLabel)
    }

    private var voiceProcessingStatus: some View {
        VStack(spacing: 6) {
            if reduceMotion {
                processingStatusText(processingMessages[0])
            } else {
                TimelineView(.periodic(from: voiceProcessingStartedAt, by: 1.05)) { context in
                    let elapsed = max(0, context.date.timeIntervalSince(voiceProcessingStartedAt))
                    let index = Int(elapsed / 1.05) % processingMessages.count
                    processingStatusText(processingMessages[index])
                        .id(index)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.24), value: index)
                }
            }

            Text("Собираю заголовок, контекст и время")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 380)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Вникаю в контекст. Собираю заголовок, контекст и время")
    }

    private func processingStatusText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 19, weight: .medium, design: .rounded))
            .multilineTextAlignment(.center)
    }

    @ViewBuilder private var voiceClarificationCard: some View {
        if let pendingVoiceClarification {
            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text(
                        pendingVoiceClarification.decision == .time
                            ? "Во сколько напомнить?"
                            : "Когда напомнить?"
                    )
                    .font(.system(size: 19, weight: .medium, design: .rounded))

                    Text(pendingVoiceClarification.draft.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    ForEach(clarificationOptions(for: pendingVoiceClarification)) { option in
                        Button {
                            resolveVoiceClarification(option)
                        } label: {
                            VStack(spacing: 2) {
                                Text(option.title)
                                    .font(.caption.weight(.semibold))
                                if let caption = option.caption {
                                    Text(caption)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .padding(.horizontal, 6)
                            .background(Color.secondary.opacity(0.085))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: 430)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func clarificationOptions(
        for clarification: PendingVoiceClarification
    ) -> [VoiceClarificationOption] {
        switch clarification.decision {
        case .date:
            return [
                VoiceClarificationOption(
                    id: "today",
                    title: "Сегодня",
                    caption: QuickDuePreset.today.date.map(shortTime),
                    dueDate: QuickDuePreset.today.date
                ),
                VoiceClarificationOption(
                    id: "tomorrow",
                    title: "Завтра",
                    caption: QuickDuePreset.tomorrow.date.map(shortTime),
                    dueDate: QuickDuePreset.tomorrow.date
                ),
                VoiceClarificationOption(
                    id: "none",
                    title: "Без срока",
                    caption: nil,
                    dueDate: nil
                )
            ]
        case .time:
            return [
                timeClarificationOption(id: "morning", title: "Утром", hour: 8, clarification: clarification),
                timeClarificationOption(id: "lunch", title: "В обед", hour: 13, clarification: clarification),
                timeClarificationOption(id: "evening", title: "Вечером", hour: 19, clarification: clarification)
            ]
        }
    }

    private func timeClarificationOption(
        id: String,
        title: String,
        hour: Int,
        clarification: PendingVoiceClarification
    ) -> VoiceClarificationOption {
        let calendar = Calendar.current
        let baseDate = clarification.draft.dueDate ?? clarification.referenceDate
        var date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: baseDate)
        if clarification.draft.dueDate == nil,
           let candidate = date,
           candidate <= clarification.referenceDate {
            date = calendar.date(byAdding: .day, value: 1, to: candidate)
        }
        return VoiceClarificationOption(
            id: id,
            title: title,
            caption: date.map(shortTime),
            dueDate: date
        )
    }

    private func shortTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func resolveVoiceClarification(_ option: VoiceClarificationOption) {
        guard let clarification = pendingVoiceClarification else { return }
        commitVoiceDraft(
            clarification.draft,
            details: clarification.details,
            dueDate: option.dueDate,
            referenceDate: clarification.referenceDate
        )
        withAnimation(.easeOut(duration: 0.2)) {
            pendingVoiceClarification = nil
        }
    }

    private var processingMessages: [String] {
        ["Вникаю в контекст…", "Отделяю главное…", "Уточняю время…"]
    }

    private var voiceOrbAccessibilityLabel: String {
        if isFinalizingVoiceSubmission { return "Вникаю в контекст" }
        return voiceInput.isListening ? "Остановить запись" : "Начать голосовой ввод"
    }

    private var homePrioritySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isPriorityOverdue ? "Требует внимания" : "Ближайшее")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    if additionalPriorityCount > 0 {
                        Text("Ещё просрочено: \(additionalPriorityCount)")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }

                Spacer()
            }

            if let priorityItem {
                HomePriorityCard(
                    item: priorityItem,
                    isOverdue: isPriorityOverdue,
                    onToggle: onTogglePriority,
                    onEdit: onEditPriority
                )
            } else {
                HStack(spacing: 13) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(MemoryTheme.accent)
                        .frame(width: 36, height: 36)
                        .background(MemoryTheme.accent.opacity(0.1))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Всё под контролем")
                            .font(.body.weight(.semibold))
                        Text("Ближайших напоминаний пока нет")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(17)
                .memoryCard()
            }
        }
    }

    private var homeComposer: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 10) {
                if !voiceInput.isListening {
                    Button(action: submit) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(trimmedDraft.isEmpty ? Color.secondary : Color.white)
                            .frame(width: 40, height: 40)
                            .background(
                                trimmedDraft.isEmpty
                                    ? Color.secondary.opacity(0.1)
                                    : MemoryTheme.accent
                            )
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmedDraft.isEmpty)
                    .accessibilityLabel("Добавить напоминание")
                    .transition(.scale.combined(with: .opacity))
                }

                TextField(
                    voiceInput.isListening ? "Говорите…" : "Написать напоминание",
                    text: $draft,
                    axis: .vertical
                )
                    .textFieldStyle(.plain)
                    .lineLimit(1...(voiceInput.isListening ? 4 : 2))
                    .fixedSize(horizontal: false, vertical: true)
                    .focused($focusedField, equals: .title)
                    .allowsHitTesting(!voiceInput.isListening)
#if os(iOS)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.sentences)
#endif
                    .onSubmit(handleSubmitKey)
                    .accessibilityIdentifier("quickCaptureField")
                    .padding(.vertical, 9)
                    .contentTransition(.interpolate)

                if !voiceInput.isListening && (focusedField == .title || !trimmedDraft.isEmpty) {
                    detailsDisclosureButton(size: 40)

                    Button(action: cancelDraft) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 40, height: 40)
                            .background(Color.secondary.opacity(0.09))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Отменить ввод")
                    .transition(.scale.combined(with: .opacity))
                }
            }

            captureMetadataChips

            if !voiceInput.isListening && isDescriptionPresented {
                TextField("Описание, ссылка или важные детали", text: $details, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...2)
                    .focused($focusedField, equals: .description)
#if os(iOS)
                    .submitLabel(.done)
                    .onSubmit(handleSubmitKey)
#endif
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .accessibilityIdentifier("quickCaptureDescriptionField")
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.07), radius: 22, y: 10)
    }

    private func handleHomeVoiceTap() {
        handleVoiceTap()
    }

    private func handleVoiceTap() {
        dismissKeyboard()

        if voiceInput.isListening {
            voiceInput.stop()
            return
        }

        voiceSubmissionTask?.cancel()
        isFinalizingVoiceSubmission = false
        shouldSubmitVoiceWhenStopped = true
        Task { @MainActor in
            await voiceInput.toggle(currentText: draft)
            if !voiceInput.isListening && voiceInput.errorMessage != nil {
                shouldSubmitVoiceWhenStopped = false
            }
        }
    }

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedDetails: String { details.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var inferredEntryKind: EntryKind? {
        guard ignoredKindExpression != draft else { return nil }
        return EntryKindInference.infer(from: trimmedDraft, hasDate: resolvedDueDate != nil)
    }

    private var effectiveEntryKind: EntryKind {
        entryKindOverride ?? inferredEntryKind ?? account.defaultEntryKind
    }

    private var resolvedDueDate: Date? {
        smartResult?.dueDate ?? preset.date
    }

    private var resolvedEventEndDate: Date? {
        nil
    }

    private var isVoicePreviewActive: Bool {
        voiceInput.isListening || isFinalizingVoiceSubmission || shouldSubmitVoiceWhenStopped
    }

    private var capturePreviewState: VoiceCapturePreview {
        isVoicePreviewActive ? VoiceCapturePreview.classify(trimmedDraft) : .single
    }

    @ViewBuilder private var captureMetadataChips: some View {
        if !trimmedDraft.isEmpty && capturePreviewState != .uncertain {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if case .multiple(let count) = capturePreviewState {
                        Text(VoiceEntryCountLabel.short(count))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MemoryTheme.accent)
                            .padding(.horizontal, 11)
                            .frame(height: 32)
                            .background(MemoryTheme.accent.opacity(0.1))
                            .clipShape(Capsule())
                            .accessibilityLabel("Предварительно: \(VoiceEntryCountLabel.short(count))")
                    } else if capturePreviewState == .single {
                        if let smartResult {
                            HStack(spacing: 5) {
                                Text(smartDateLabel(for: smartResult.dueDate))
                                    .font(.caption.weight(.semibold))
                                if !voiceInput.isListening {
                                    Button {
                                        ignoredSmartExpression = draft
                                        self.smartResult = nil
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .frame(width: 20, height: 20)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Убрать распознанную дату")
                                }
                            }
                            .foregroundStyle(MemoryTheme.accent)
                            .padding(.leading, 11)
                            .padding(.trailing, voiceInput.isListening ? 11 : 5)
                            .frame(height: 32)
                            .background(MemoryTheme.accent.opacity(0.1))
                            .clipShape(Capsule())
                            .accessibilityIdentifier("smartDateSuggestion")
                        }
                        if !isVoicePreviewActive || inferredEntryKind != nil || entryKindOverride != nil {
                            Button {
                                ignoredKindExpression = draft
                                entryKindOverride = effectiveEntryKind == .event ? .reminder : .event
                            } label: {
                                Text(effectiveEntryKind.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(entryKindChipColor)
                                    .padding(.horizontal, 11)
                                    .frame(height: 32)
                                    .background(entryKindChipColor.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(voiceInput.isListening)
                            .accessibilityLabel("Тип записи: \(effectiveEntryKind.title)")
                            .accessibilityHint("Нажмите, чтобы изменить")
                        }
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var entryKindChipColor: Color {
        effectiveEntryKind == .event ? MemoryTheme.warm : MemoryTheme.accent
    }

    private func detailsDisclosureButton(size: CGFloat) -> some View {
        Button(action: openDetailedEditor) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .background(Color.secondary.opacity(0.09))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Подробные настройки")
        .accessibilityHint("Открывает полный редактор записи")
    }

    private func openDetailedEditor() {
        let title = smartResult?.title ?? trimmedDraft
        let kind = effectiveEntryKind
        onOpenDetails(
            title,
            Item.normalizedDetails(trimmedDetails),
            kind,
            resolvedDueDate,
            resolvedEventEndDate
        )
        focusedField = nil
    }

    private var showsCancelButton: Bool {
#if os(macOS)
        !trimmedDraft.isEmpty || presentation == .desktopInline
#else
        !trimmedDraft.isEmpty
#endif
    }

    private var compactControlSize: CGFloat { isDocked ? 44 : 40 }

    private var usesMinimalDesktopChrome: Bool {
#if os(macOS)
        presentation == .desktopInline
#else
        false
#endif
    }
    private var isComposerExpanded: Bool {
        guard !voiceInput.isListening else { return false }
        return focusedField != nil
            || !trimmedDraft.isEmpty
            || smartResult != nil
            || isDescriptionPresented
            || !trimmedDetails.isEmpty
    }

    private func voiceButton(size: CGFloat) -> some View {
        Button {
            handleVoiceTap()
        } label: {
            Image(systemName: voiceInput.isListening ? "stop.fill" : "mic.fill")
                .font(.system(size: isDocked ? 17 : 14, weight: .semibold))
                .foregroundStyle(voiceInput.isListening ? Color.white : MemoryTheme.accent)
                .frame(width: size, height: size)
                .background(
                    voiceInput.isListening
                        ? Color.red.opacity(0.88)
                        : MemoryTheme.accent.opacity(isDocked ? 0.16 : 0.12)
                )
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(voiceInput.isListening ? "Остановить запись" : "Голосовой ввод")
    }

    private var isShowingVoiceError: Binding<Bool> {
        Binding(
            get: { voiceInput.errorMessage != nil },
            set: { if !$0 { voiceInput.errorMessage = nil } }
        )
    }

    private func isSelected(_ option: QuickDuePreset) -> Bool {
        smartResult == nil && preset == option
    }

    private func smartDateLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let time = MemoryDateFormatting.time(date)
        if calendar.isDateInToday(date) { return "Сегодня · \(time)" }
        if calendar.isDateInTomorrow(date) { return "Завтра · \(time)" }
        return "\(MemoryDateFormatting.editorDate(date)) · \(time)"
    }

    private func handleSubmitKey() {
        if trimmedDraft.isEmpty {
            dismissKeyboard()
        } else {
            submit()
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

    private func dismissKeyboard() {
        focusedField = nil
    }

    private func toggleDescription() {
        if isDescriptionPresented {
            focusedField = .title
            withAnimation(.easeInOut(duration: 0.22)) {
                isDescriptionPresented = false
            }
        } else {
            withAnimation(.easeInOut(duration: 0.22)) {
                isDescriptionPresented = true
            }
            DispatchQueue.main.async {
                focusedField = .description
            }
        }
    }

    @MainActor
    private func submitVoiceRecording() async {
        let spokenText = voiceInput.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spokenText.isEmpty else { return }

        smartParsingTask?.cancel()
        let referenceDate = Date.now
        let calendar = Calendar.current
        let parsedResult = NaturalLanguageDateParser.parse(
            spokenText,
            now: referenceDate,
            calendar: calendar
        )
        let locallySplit = VoiceUtteranceSplitter.split(spokenText)
        let localResult: VoiceCaptureResult?
        if isStructuredInterpreterEnabled || locallySplit.count > 1 {
            localResult = VoiceCaptureResult.local(
                spokenText,
                now: referenceDate,
                calendar: calendar,
                defaultKind: account.defaultEntryKind
            )
        } else {
            localResult = nil
        }
        let interpreted = await enhancedVoiceDraft(
            for: spokenText,
            fallback: localResult,
            now: referenceDate,
            calendar: calendar
        )
        let normalizedDetails = Item.normalizedDetails(trimmedDetails)
        let fallbackDate = preset.date
        if let interpreted, interpreted.entries.count > 1 {
            let reconciledEntries = interpreted.entries.map { entry -> VoiceCaptureEntry in
                let parsed = NaturalLanguageDateParser.parse(
                    entry.sourceText, now: referenceDate, calendar: calendar
                )
                // A date from the semantic parser belongs to this entry; do not
                // overwrite it with a date from another part of the utterance.
                let draft = entry.draft.dueDate == nil && parsed?.dueDate != nil
                    ? VoiceDraftReconciler.reconcile(semantic: entry.draft, deterministic: parsed)
                    : entry.draft
                return VoiceCaptureEntry(
                    sourceText: entry.sourceText,
                    draft: draft,
                    kind: entry.kind,
                    endDate: entry.endDate
                )
            }
            resetVoiceComposer()
            let reviewEntries = reconciledEntries.map {
                VoiceReviewEntry($0, defaultReminderMinutes: account.defaultReminderMinutes)
            }
            onReviewBatch(VoiceBatchReview(referenceDate: referenceDate, entries: reviewEntries))
            return
        }

        let interpretedEntry = interpreted?.entries.first
        let reconciledDraft = interpretedEntry.map {
            VoiceDraftReconciler.reconcile(semantic: $0.draft, deterministic: parsedResult)
        }
        let finalDraft: ReminderDraft

        if let reconciledDraft {
            finalDraft = ReminderDraft(
                transcript: spokenText,
                title: reconciledDraft.title,
                details: normalizedDetails ?? reconciledDraft.details,
                dueDate: reconciledDraft.dueDate,
                reminderOffsets: reconciledDraft.reminderOffsets,
                confidence: reconciledDraft.confidence,
                ambiguities: reconciledDraft.ambiguities
            )
        } else if let parsedResult {
            finalDraft = ReminderDraft(
                transcript: spokenText,
                title: parsedResult.title,
                details: normalizedDetails,
                dueDate: parsedResult.dueDate,
                reminderOffsets: parsedResult.reminderOffsets,
                confidence: .high,
                ambiguities: []
            )
        } else {
            finalDraft = ReminderDraft(
                transcript: spokenText,
                title: spokenText,
                details: normalizedDetails,
                dueDate: nil,
                reminderOffsets: [],
                confidence: .medium,
                ambiguities: [.missingDate]
            )
        }

        resetVoiceComposer()

        if interpretedEntry?.kind == .event && finalDraft.dueDate == nil {
            onReviewBatch(VoiceBatchReview(
                referenceDate: referenceDate,
                entries: [VoiceReviewEntry(VoiceCaptureEntry(
                    sourceText: spokenText,
                    draft: finalDraft,
                    kind: .event,
                    endDate: interpretedEntry?.endDate
                ), defaultReminderMinutes: account.defaultReminderMinutes)]
            ))
            return
        }

        if isVoiceClarificationEnabled,
           let decision = VoiceClarificationPolicy.decision(for: finalDraft) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                pendingVoiceClarification = PendingVoiceClarification(
                    decision: decision,
                    draft: finalDraft,
                    details: finalDraft.details,
                    fallbackDate: fallbackDate,
                    referenceDate: referenceDate
                )
            }
            return
        }

        commitVoiceDraft(
            finalDraft,
            details: finalDraft.details,
            dueDate: finalDraft.dueDate ?? fallbackDate,
            kind: interpretedEntry?.kind,
            endDate: interpretedEntry?.endDate,
            referenceDate: referenceDate
        )
    }

    private func resetVoiceComposer() {
        draft = ""
        details = ""
        isDescriptionPresented = false
        preset = defaultPreset
        ignoredSmartExpression = nil
        ignoredKindExpression = nil
        entryKindOverride = nil
        smartResult = nil
        dismissKeyboard()
    }

    private func commitVoiceDraft(
        _ voiceDraft: ReminderDraft,
        details: String?,
        dueDate: Date?,
        kind: EntryKind? = nil,
        endDate: Date? = nil,
        referenceDate: Date
    ) {
        let inferredKind = EntryKindInference.infer(
            from: voiceDraft.transcript,
            hasDate: dueDate != nil
        )
        let entryKind: EntryKind = dueDate == nil
            ? .reminder
            : (kind ?? inferredKind ?? account.defaultEntryKind)
        let itemID = onAdd(
            voiceDraft.title,
            details,
            entryKind,
            dueDate,
            entryKind == .event ? endDate : nil,
            voiceDraft.reminderOffsets.isEmpty ? nil : voiceDraft.reminderOffsets
        )
        if let itemID {
            VoicePersonalizationStore.beginCapture(
                itemID: itemID,
                transcript: voiceDraft.transcript,
                title: voiceDraft.title,
                details: details,
                dueDate: dueDate,
                referenceDate: referenceDate
            )
        }
    }

    @MainActor
    private func enhancedVoiceDraft(
        for spokenText: String,
        fallback: VoiceCaptureResult?,
        now: Date,
        calendar: Calendar
    ) async -> VoiceCaptureResult? {
        guard isDeepSeekInterpreterEnabled,
              let remoteVoiceInterpreter else { return fallback }

        do {
            return try await withThrowingTaskGroup(of: VoiceCaptureResult.self) { group in
                group.addTask {
                    try await remoteVoiceInterpreter(spokenText, now, calendar)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(5))
                    throw VoiceSemanticError.timedOut
                }

                guard let result = try await group.next() else {
                    throw VoiceSemanticError.emptyResult
                }
                group.cancelAll()
                if let fallback, fallback.entries.count > 1, result.entries.count == 1 {
                    return fallback
                }
                return result
            }
        } catch {
            return fallback
        }
    }

    private func cancelDraft() {
        shouldSubmitVoiceWhenStopped = false
        isFinalizingVoiceSubmission = false
        voiceSubmissionTask?.cancel()
        smartParsingTask?.cancel()
        voiceInput.stop()
        draft = ""
        details = ""
        isDescriptionPresented = false
        preset = defaultPreset
        ignoredSmartExpression = nil
        ignoredKindExpression = nil
        entryKindOverride = nil
        smartResult = nil
        dismissKeyboard()
        if isRecordsPage {
            withAnimation(.easeInOut(duration: 0.2)) {
                isRecordsComposerPresented = false
            }
        }
#if os(macOS)
        if presentation == .desktopInline {
            onDismiss()
        }
#endif
    }

    private func resetAfterDetailedCommit() {
        draft = ""
        details = ""
        isDescriptionPresented = false
        preset = defaultPreset
        ignoredSmartExpression = nil
        ignoredKindExpression = nil
        entryKindOverride = nil
        smartResult = nil
        focusedField = nil

        if isRecordsPage {
            withAnimation(.easeInOut(duration: 0.2)) {
                isRecordsComposerPresented = false
            }
        }
#if os(macOS)
        if presentation == .desktopInline {
            onDismiss()
        }
#endif
    }

    private func submit() {
        guard !trimmedDraft.isEmpty else { return }
        if effectiveEntryKind == .event, resolvedDueDate == nil {
            openDetailedEditor()
            return
        }
        shouldSubmitVoiceWhenStopped = false
        isFinalizingVoiceSubmission = false
        voiceSubmissionTask?.cancel()
        smartParsingTask?.cancel()
        voiceInput.stop()
        if let smartResult {
            _ = onAdd(
                smartResult.title,
                Item.normalizedDetails(trimmedDetails),
                effectiveEntryKind,
                smartResult.dueDate,
                nil,
                smartResult.reminderOffsets.isEmpty ? nil : smartResult.reminderOffsets
            )
        } else {
            _ = onAdd(
                trimmedDraft,
                Item.normalizedDetails(trimmedDetails),
                effectiveEntryKind,
                preset.date,
                nil,
                nil
            )
        }
        draft = ""
        details = ""
        isDescriptionPresented = false
        preset = defaultPreset
        ignoredSmartExpression = nil
        ignoredKindExpression = nil
        entryKindOverride = nil
        dismissKeyboard()
        if isRecordsPage {
            withAnimation(.easeInOut(duration: 0.2)) {
                isRecordsComposerPresented = false
            }
        }
    }
}

private struct GlassVoiceOrb: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRotating = false

    let isListening: Bool
    let isProcessing: Bool
    let isPulsing: Bool
    let size: CGFloat

    private var isActive: Bool { isListening || isProcessing }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            Color(red: 1.0, green: 0.78, blue: 0.33).opacity(0.82),
                            Color(red: 1.0, green: 0.32, blue: 0.58).opacity(0.78),
                            MemoryTheme.accent.opacity(0.74),
                            Color.cyan.opacity(0.44),
                            Color(red: 1.0, green: 0.78, blue: 0.33).opacity(0.82)
                        ],
                        center: .center
                    )
                )
                .frame(width: size + 22, height: size + 22)
                .rotationEffect(.degrees(isRotating ? 360 : 0))
                .blur(radius: isActive ? 19 : 15)
                .opacity(isActive ? 0.7 : 0.42)
                .scaleEffect(isActive && isPulsing ? 1.08 : 1)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.78, blue: 0.33),
                            Color(red: 1.0, green: 0.36, blue: 0.58),
                            MemoryTheme.accent.opacity(0.94)
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                )
                .frame(width: size, height: size)

            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            Color.white.opacity(0.72),
                            Color.cyan.opacity(0.28),
                            Color.clear,
                            Color.purple.opacity(0.46),
                            Color.white.opacity(0.64)
                        ],
                        center: .center
                    )
                )
                .frame(width: size - 2, height: size - 2)
                .opacity(isActive ? 0.92 : 0.72)
                .rotationEffect(.degrees(isRotating ? 360 : 0))
                .mask {
                    ZStack {
                        Circle()
                        Circle()
                            .inset(by: 7)
                            .fill(.black)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(isActive ? 0.42 : 0.32),
                            Color(red: 1.0, green: 0.63, blue: 0.24).opacity(0.32),
                            Color.pink.opacity(0.08),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.58, y: 0.38),
                        startRadius: 2,
                        endRadius: size * 0.58
                    )
                )
                .frame(width: size - 14, height: size - 14)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.purple.opacity(0.46), Color.clear],
                        center: UnitPoint(x: 0.38, y: 0.8),
                        startRadius: 0,
                        endRadius: size * 0.54
                    )
                )
                .frame(width: size - 10, height: size - 10)
                .blendMode(.plusLighter)

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.78), Color.white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.52, height: size * 0.22)
                .blur(radius: 7)
                .rotationEffect(.degrees(-24))
                .offset(x: -size * 0.17, y: -size * 0.27)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.76), Color.white.opacity(0.08), Color.white.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
                .frame(width: size, height: size)
        }
        .frame(width: size + 30, height: size + 30)
        .compositingGroup()
        .shadow(
            color: MemoryTheme.accent.opacity(isActive ? 0.3 : 0.16),
            radius: isActive ? 34 : 24,
            y: 12
        )
        .scaleEffect(isActive && isPulsing ? 1.025 : 1)
        .animation(.easeInOut(duration: 1.5), value: isPulsing)
        .onAppear { updateRotation(isActive: isActive) }
        .onChange(of: isActive) { _, active in
            updateRotation(isActive: active)
        }
        .accessibilityHidden(true)
    }

    private func updateRotation(isActive: Bool) {
        guard !reduceMotion, isActive else {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                isRotating = false
            }
            return
        }

        isRotating = false
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            isRotating = true
        }
    }
}

private struct HomePriorityCard: View {
    let item: Item
    let isOverdue: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            if !item.isEvent {
                Button(action: onToggle) {
                    Image(systemName: "circle")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(isOverdue ? Color.red.opacity(0.8) : Color.secondary.opacity(0.65))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Отметить выполненным")
            }

            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title.isEmpty ? "Без названия" : item.title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    if let details = item.details {
                        Text(details)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)
                    }

                    if item.isEvent {
                        Text(dateLabel)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(MemoryTheme.warm)
                    } else {
                        Label(dateLabel, systemImage: item.notificationsEnabled ? "bell" : "calendar")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(isOverdue ? Color.red : MemoryTheme.accent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [
                    item.isEvent
                        ? MemoryTheme.warm.opacity(0.22)
                        : isOverdue ? Color.red.opacity(0.09) : MemoryTheme.accent.opacity(0.08),
                    MemoryTheme.card
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    item.isEvent
                        ? MemoryTheme.warm.opacity(0.28)
                        : isOverdue ? Color.red.opacity(0.14) : MemoryTheme.accent.opacity(0.1),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.05), radius: 14, y: 7)
    }

    private var dateLabel: String {
        guard let date = item.dueDate else { return "Без срока" }
        if item.isEvent {
            let start = MemoryDateFormatting.time(date)
            if let endDate = item.endDate {
                let end = MemoryDateFormatting.time(endDate)
                if date <= .now, endDate > .now { return "Сейчас · до \(end)" }
                if Calendar.current.isDateInToday(date) { return "Сегодня · \(start)–\(end)" }
                if Calendar.current.isDateInTomorrow(date) { return "Завтра · \(start)–\(end)" }
                return "\(MemoryDateFormatting.shortDate(date)) · \(start)–\(end)"
            }
            if Calendar.current.isDateInToday(date) { return "Сегодня · \(start)" }
            if Calendar.current.isDateInTomorrow(date) { return "Завтра · \(start)" }
            return "\(MemoryDateFormatting.shortDate(date)) · \(start)"
        }
        let time = MemoryDateFormatting.time(date)
        if isOverdue { return "Просрочено · \(time)" }
        if Calendar.current.isDateInToday(date) { return "Сегодня · \(time)" }
        if Calendar.current.isDateInTomorrow(date) { return "Завтра · \(time)" }
        return MemoryDateFormatting.shortDateTime(date)
    }
}

struct MemoryItemRow: View {
    let item: Item
    var onToggle: (() -> Void)? = nil
    let onEdit: () -> Void
    var onDelete: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            if !item.isEvent, let onToggle {
                Button(action: onToggle) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(item.isCompleted ? MemoryTheme.accent : Color.secondary.opacity(0.65))
                }
                .buttonStyle(.plain)
            }
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title.isEmpty ? "Без названия" : item.title)
                        .font(.body.weight(.medium)).foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                        .strikethrough(item.isCompleted).multilineTextAlignment(.leading)
                    if let details = item.details {
                        Text(details)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    if item.isEvent {
                        Text(dateLabel)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(dateColor)
                    } else {
                        Label(dateLabel, systemImage: dateIcon)
                            .font(.caption)
                            .foregroundStyle(dateColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 15)
        .memoryEntryCard(isEvent: item.isEvent)
        .contextMenu {
            Button(action: onEdit) { Label("Изменить", systemImage: "pencil") }
            if let onDelete {
                Button(role: .destructive, action: onDelete) { Label("Удалить", systemImage: "trash") }
            }
        }
    }

    private var dateLabel: String {
        if item.isEvent, let startDate = item.dueDate {
            let start = MemoryDateFormatting.time(startDate)
            if let endDate = item.endDate {
                let end = MemoryDateFormatting.time(endDate)
                if startDate <= .now, endDate > .now { return "Сейчас · до \(end)" }
                if Calendar.current.isDateInToday(startDate) { return "Сегодня · \(start)–\(end)" }
                if Calendar.current.isDateInTomorrow(startDate) { return "Завтра · \(start)–\(end)" }
                return "\(MemoryDateFormatting.shortDate(startDate)) · \(start)–\(end)"
            }
            if Calendar.current.isDateInToday(startDate) { return "Сегодня · \(start)" }
            if Calendar.current.isDateInTomorrow(startDate) { return "Завтра · \(start)" }
            return "\(MemoryDateFormatting.shortDate(startDate)) · \(start)"
        }
        if item.isCompleted {
            guard let completedAt = item.completedAt else { return "Выполнено" }
            return "Выполнено · \(MemoryDateFormatting.shortDate(completedAt))"
        }
        guard let date = item.dueDate else { return "Без срока" }
        if date < .now { return "Просрочено · \(MemoryDateFormatting.time(date))" }
        if Calendar.current.isDateInToday(date) { return "Сегодня · \(MemoryDateFormatting.time(date))" }
        if Calendar.current.isDateInTomorrow(date) { return "Завтра · \(MemoryDateFormatting.time(date))" }
        return MemoryDateFormatting.shortDateTime(date)
    }
    private var dateIcon: String {
        if item.isEvent { return "calendar" }
        if item.isCompleted { return "checkmark" }
        guard item.dueDate != nil else { return "tray" }
        return item.notificationsEnabled ? "bell" : "calendar"
    }
    private var dateColor: Color {
        guard !item.isCompleted, let date = item.dueDate else { return .secondary }
        if item.isEvent, let endDate = item.endDate {
            return endDate < .now ? .secondary : MemoryTheme.warm
        }
        if item.isEvent { return date < .now ? .secondary : MemoryTheme.warm }
        return date < .now ? .red : MemoryTheme.accent
    }
}

private struct CaptureConfirmationBanner: View {
    let title: String
    let dueDate: Date?
    let onEdit: () -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.body.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Label(dueSummary, systemImage: dueDate == nil ? "tray" : "calendar")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(spacing: 10) {
                Button(action: onEdit) {
                    Label("Изменить", systemImage: "pencil")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Изменить")
                .accessibilityLabel("Изменить добавленную задачу")

                Button(action: onUndo) {
                    Label("Отменить", systemImage: "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Отменить добавление")
                .accessibilityLabel("Отменить добавление")
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 24, y: 10)
    }

    private var dueSummary: String {
        guard let dueDate else { return "Без срока" }
        return Self.compactDate(dueDate)
    }

    private static func compactDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "Сегодня · \(time)" }
        if calendar.isDateInTomorrow(date) { return "Завтра · \(time)" }
        return compactDateFormatter.string(from: date)
    }

    private static let compactDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter
    }()
}

private struct MemorySectionHeader: View {
    let title: String
    let subtitle: String?
    let count: Int
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            Spacer(minLength: 8)

            Text("\(count)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .frame(minWidth: 30, minHeight: 30)
                .background(color.opacity(0.1))
                .clipShape(Circle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct TodayEmptyView: View {
    let hasUpcomingItems: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(MemoryTheme.accent)
                .frame(width: 44, height: 44)
                .background(MemoryTheme.accent.opacity(0.11))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("На сегодня всё спокойно")
                    .font(.body.weight(.semibold))
                Text(
                    hasUpcomingItems
                        ? "Будущие записи находятся в разделе «Все»."
                        : "Добавьте задачу, когда появится что-то важное."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .memoryCard()
    }
}

private struct RecordsEmptyView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 34, weight: .light)).foregroundStyle(MemoryTheme.accent)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.vertical, 42).padding(.horizontal, 24).frame(maxWidth: .infinity).memoryCard()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
        .environmentObject(AccountSyncController())
}
