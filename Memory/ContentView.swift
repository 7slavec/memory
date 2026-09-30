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
    @Query private var recordLinks: [RecordLink]
    @State private var linkPopupItemID: UUID?
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
    @State private var isKeyboardVisible = false
    @State private var isMobileProfilePresented = false
    @State private var mobileProfilePage = ProfilePage.profile
    private var isMobileArchivePresented: Bool { mobileProfilePage == .archive }
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
            if VoiceReviewTesting.isUnitTestHost { return }
            if VoiceReviewTesting.isEnabled {
                if VoiceReviewTesting.isProfileEnabled {
#if os(macOS)
                    desktopSection = .profile
#else
                    isMobileProfilePresented = true
#endif
                } else if VoiceReviewTesting.isLinksEnabled {
                    let first = Item(title: "Отправить заявку", notificationsEnabled: false)
                    let second = Item(title: "Вебинар по дизайну", notificationsEnabled: false)
                    let third = Item(title: "Прочитать материалы", notificationsEnabled: false)
                    modelContext.insert(first)
                    modelContext.insert(second)
                    modelContext.insert(third)
                    try? modelContext.save()
                    editingItem = first
                } else {
                    voiceReviewSession = VoiceReviewTesting.session(context: modelContext)
                }
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
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return }
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
                await account.refreshPersonalization()
            }
        }
        .onChange(of: selectedSection) { _, section in
            if section != .all {
                isInboxPresented = false
            }
        }
#if os(iOS)
        .fullScreenCover(item: $editingItem) { item in
            RecordEditorFlow(
                item: item,
                onSave: { current, title, details, kind, date, endDate, reminderOffsets in
                    update(
                        current,
                        title: title,
                        details: details,
                        entryKind: kind,
                        dueDate: date,
                        endDate: endDate,
                        reminderOffsets: reminderOffsets
                    )
                },
                onToggleCompleted: { toggleCompleted($0) },
                onDelete: { delete($0) },
                onDismiss: { editingItem = nil }
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
                        return true
                    }
                    return false
                },
                onToggleCompleted: { true },
                onDelete: { true },
                isNew: true
            )
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
            let showsDetailPane = editingItem != nil && workspaceWidth >= 760
            let detailPaneWidth = min(max(workspaceWidth * 0.48, 360), 480)

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
            ZStack(alignment: .trailing) {
                desktopSectionContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.trailing, showsDetailPane ? detailPaneWidth + 16 : 0)
                    .opacity(editingItem != nil && !showsDetailPane ? 0 : 1)
                    .allowsHitTesting(editingItem == nil || showsDetailPane)
                    .accessibilityHidden(editingItem != nil && !showsDetailPane)

                // Keep one editor identity when resizing across the breakpoint:
                // changing its width must not discard the user's draft.
                if let item = editingItem {
                    desktopItemEditor(item, compact: showsDetailPane)
                        .id(item.id)
                        .frame(width: showsDetailPane ? detailPaneWidth : nil)
                        .frame(maxWidth: showsDetailPane ? nil : .infinity)
                        .padding(.vertical, showsDetailPane ? 16 : 0)
                        .padding(.trailing, showsDetailPane ? 16 : 0)
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
                    ProfileAvatarView(avatar: account.personalization.avatar, size: 42)
                        .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 11) {
                        ProfileAvatarView(avatar: account.personalization.avatar, size: 36)

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
        .background(MemoryTheme.card)
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
                            ? MemoryTheme.accent
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
                        ? MemoryTheme.accent
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(desktopSection == section ? MemoryTheme.onAccent : Color.primary)
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
        RecordEditorFlow(
            item: item,
            onSave: { current, title, details, kind, date, endDate, reminderOffsets in
                if !isEditingNewDesktopItem {
                    return update(
                        current,
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
                        return true
                    }
                    return false
                }
            },
            onToggleCompleted: { toggleCompleted($0) },
            onDelete: { delete($0) },
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
                HStack {
                    Text(Self.mainDateFormatter.string(from: currentDate))
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: 680)

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
                .frame(maxWidth: 580)

                desktopPrioritySection
                    .frame(maxWidth: 560)
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
        DesktopRecordsPage(allowsCapture: allowsCapture, onCreate: {
            withAnimation(MemoryTheme.motion) { isDesktopComposerPresented = true }
        }, heading: {
            desktopPageHeader(title: title, caption: nil)
        }, search: { search }, records: { content })
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
                    onEdit: { editingItem = item },
                    linkedCount: RecordLinkIndex(items: items, links: recordLinks, ownerID: account.userID).count(for: item.id),
                    onOpenLinkedRecord: { editingItem = $0 }
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
        HStack(spacing: 10) {
            desktopArchiveSearchInput
            ArchiveClearButton(itemIDs: completedItems.map(\.id), onClear: clearArchive)
        }
    }

    private var desktopProfileArchivePage: some View {
        ScrollView {
            VStack(spacing: 18) {
                desktopArchiveSearchField
                desktopArchiveContent
            }
            .frame(maxWidth: 620).padding(.horizontal, 22).padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
    }

    private var desktopArchiveSearchInput: some View {
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
        ProfileScreen(archiveCount: completedItems.count,
                      archiveContent: AnyView(desktopProfileArchivePage),
                      onSignIn: { isAccountPresented = true })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    .frame(height: MemoryMotion.mobileHeaderHeight)
                    .transaction { $0.animation = nil }

                GeometryReader { proxy in
                    ZStack {
                        ZStack {
                            QuickCaptureCard(
                                defaultPreset: .today,
                                isDocked: true,
                                isHome: true,
                                isRecordsPage: selectedSection == .all,
                                isPageSwiping: suppressItemOpening,
                                externalKeyboardVisible: isKeyboardVisible,
                                priorityItem: homePriorityItem,
                                isPriorityOverdue: homePriorityIsOverdue,
                                additionalPriorityCount: homeAdditionalPriorityCount,
                                priorityLinkedCount: homePriorityItem.map {
                                    RecordLinkIndex(items: items, links: recordLinks, ownerID: account.userID).count(for: $0.id)
                                } ?? 0,
                                onOpenPriorityLinkedRecord: { editingItem = $0 },
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

                            mobileRecordsContent
                                .memoryPageVisibility(selectedSection == .all, hiddenX: -MemoryMotion.pageDistance)
                                .zIndex(1)
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
                        .memoryPageVisibility(!isMobileProfilePresented, hiddenX: -MemoryMotion.pageDistance)

                        mobileProfileDestinationContent
                            .memoryPageVisibility(isMobileProfilePresented, hiddenX: MemoryMotion.pageDistance)
                    }
                    .clipped()
                    .contentShape(Rectangle())
                    .simultaneousGesture(responsiveMobilePageSwipeGesture)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(MemoryTheme.background.ignoresSafeArea())
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
    }

    @ViewBuilder private var mobilePersistentHeader: some View {
        if isMobileProfilePresented {
            mobileSecondaryHeader(title: mobileProfilePage.rawValue, backAction: handleMobileProfileBack)
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
                            Image(systemName: "waveform")
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(.primary)
                                .frame(width: 52, height: 52)
                                .background(MemoryTheme.card)
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
                    .memoryPageVisibility(!isInboxPresented, hiddenX: -MemoryMotion.pageDistance)

                mobileInboxContent
                    .memoryPageVisibility(isInboxPresented, hiddenX: MemoryMotion.pageDistance)
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
                .padding(.horizontal, 22)
                Section {
                    activeItemsListContent
                        .padding(.top, 2)
                        .padding(.horizontal, 22)
                } header: {
                    searchField
                        .padding(.horizontal, 22)
                        .padding(.vertical, 8)
                        .background(MemoryTheme.background)
                        .zIndex(5)
                }
            }
            .frame(maxWidth: 804)
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
        mobileProfileContent
    }

    private var mobileProfileContent: some View {
        ProfileScreen(archiveCount: completedItems.count,
                      isVisible: isMobileProfilePresented,
                      navigation: $mobileProfilePage,
                      showsHeader: false,
                      archiveContent: AnyView(mobileArchiveContent),
                      onSignIn: { isAccountPresented = true })
    }
    private var mobileArchiveContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    archiveSearchField
                    ArchiveClearButton(itemIDs: completedItems.map(\.id), onClear: clearArchive)
                }

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


    private var responsiveMobilePageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard !isKeyboardVisible, !isMobileProfilePresented, !isInboxPresented,
                      editingItem == nil, draftEditingItem == nil, linkPopupItemID == nil else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) * 1.2 else { return }

                if abs(horizontal) > 18, !suppressItemOpening {
                    suppressItemOpening = true
                }
            }
            .onEnded { value in
                guard !isKeyboardVisible, !isMobileProfilePresented, !isInboxPresented,
                      editingItem == nil, draftEditingItem == nil, linkPopupItemID == nil else {
                    resetResponsiveSwipeState()
                    return
                }

                let horizontal = value.translation.width
                let vertical = value.translation.height
                let predicted = value.predictedEndTranslation.width

                if abs(horizontal) > 26,
                   abs(horizontal) > abs(vertical) * 1.2,
                   (abs(horizontal) > 44 || abs(predicted) > 52) {
                    suppressItemOpening = true
                    if selectedSection == .now, horizontal > 0 {
                        navigateMobile(to: .all)
                    } else if selectedSection == .all, horizontal < 0 {
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
            selectedSection = section
        }
    }

    private func openInbox() {
        guard selectedSection == .all, !isInboxPresented else { return }
        dismissAppKeyboard()
        isInboxPresented = true
    }

    private func closeInbox() {
        guard isInboxPresented else { return }
        dismissAppKeyboard()
        isInboxPresented = false
    }

    private func openMobileProfile() {
        guard !isMobileProfilePresented else { return }
        requestVoiceReviewExit {
            dismissAppKeyboard()
            mobileProfilePage = .profile
            isMobileProfilePresented = true
        }
    }

    private func handleMobileProfileBack() {
        if mobileProfilePage != .profile {
            dismissAppKeyboard()
            mobileProfilePage = .profile
        } else {
            closeMobileProfile()
        }
    }

    private func closeMobileProfile() {
        guard isMobileProfilePresented else { return }
        dismissAppKeyboard()
        isMobileProfilePresented = false
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
            ProfileAvatarView(avatar: account.personalization.avatar, size: 52)
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
        let groups = groupedActiveItems
        let linkIndex = RecordLinkIndex(items: items, links: recordLinks, ownerID: account.userID)
        if groups.isEmpty {
            RecordsEmptyView(
                icon: searchTextIsEmpty ? "sparkles" : "magnifyingglass",
                title: searchTextIsEmpty ? "Нет записей с датой" : "Ничего не нашлось",
                message: searchTextIsEmpty
                    ? "Записи без срока находятся во Входящих."
                    : "Попробуйте другой запрос."
            )
        } else {
            ForEach(datedItemGroups) { group in
                let groupItems = groups[group] ?? []
                if !groupItems.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        MemorySectionHeader(
                            title: group.title,
                            subtitle: nil,
                            count: groupItems.count,
                            icon: group.icon,
                            color: group.color
                        )
                        taskRows(groupItems, linkIndex: linkIndex)
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

    private func taskRows(_ source: [Item], linkIndex: RecordLinkIndex? = nil) -> some View {
        let index = linkIndex ?? RecordLinkIndex(items: items, links: recordLinks, ownerID: account.userID)
        return LazyVStack(spacing: 12) {
            ForEach(source, id: \.persistentModelID) { item in
                MemoryItemRow(
                    item: item,
                    onToggle: { toggleCompleted(item) },
                    onEdit: {
                        guard !suppressItemOpening else { return }
                        editingItem = item
                    },
                    onDelete: { delete(item) },
                    linkedCount: index.count(for: item.id),
                    onOpenLinks: {
                        guard !suppressItemOpening else { return }
                        linkPopupItemID = item.id
                    }
                )
                .recordLinksPopup(item: item, isPresented: Binding(
                    get: { linkPopupItemID == item.id },
                    set: { if !$0 && linkPopupItemID == item.id { linkPopupItemID = nil } }
                )) { linked in
                    linkPopupItemID = nil
                    editingItem = linked
                }
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
                : (reminderOffsets ?? [account.defaultReminderMinutes(for: entryKind)]),
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
            onSaveExisting: update,
            onToggleExisting: toggleCompleted,
            onDeleteExisting: delete,
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
        if session.hasChanges || session.selectedEntryID != nil || session.externalItem != nil || !session.batch.isPersisted {
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
        let newItems: [Item]
        do {
            newItems = try VoiceBatchPersistence.create(entries, ownerID: account.userID, context: modelContext)
        } catch {
            errorMessage = "Не удалось сохранить: \(error.localizedDescription)"
            return nil
        }
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
        do {
            try VoiceBatchPersistence.stageDeletion(removedIDs.compactMap { stored[$0] }, context: modelContext)
        } catch {
            VoiceBatchPersistence.rollback(modelContext)
            errorMessage = "Не удалось изменить записи: \(error.localizedDescription)"
            return false
        }
        for (id, item) in stored {
            guard let entry = edited[id] else { continue }
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
        do {
            try VoiceBatchPersistence.stageDeletion(Array(stored.values), context: modelContext)
        } catch {
            VoiceBatchPersistence.rollback(modelContext)
            errorMessage = "Не удалось отменить записи: \(error.localizedDescription)"
            return false
        }
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
        let matching = stored.filter { ids.contains($0.id) && $0.deletedAt == nil && $0.ownerID == account.userID }
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
            reminderOffsets: startDate == nil ? [] : [account.defaultReminderMinutes(for: entryKind)],
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

    @discardableResult private func update(
        _ item: Item,
        title: String,
        details: String?,
        entryKind: EntryKind,
        dueDate: Date?,
        endDate: Date?,
        reminderOffsets: [Int]
    ) -> Bool {
#if DEBUG
        if VoiceReviewTesting.isLinksEnabled && ProcessInfo.processInfo.arguments.contains("--uitest-save-failure") {
            return false
        }
#endif
        item.title = title
        item.details = Item.normalizedDetails(details)
        item.entryKind = entryKind
        item.dueDate = dueDate
        item.endDate = entryKind == .event ? endDate : nil
        item.setReminderOffsets(dueDate == nil ? [] : reminderOffsets)
        item.updatedAt = .now
        guard saveChanges() else { return false }
        VoicePersonalizationStore.confirmCorrection(
            itemID: item.id,
            title: item.title,
            details: item.details,
            dueDate: item.dueDate
        )
        scheduleReminder(for: item)
        account.markLocalChange(modelContext: modelContext)
        return true
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

    @discardableResult private func toggleCompleted(_ item: Item) -> Bool {
        withAnimation(.snappy) { item.setCompleted(!item.isCompleted) }
        guard saveChanges() else { return false }
        item.isCompleted ? ReminderScheduler.cancel(id: item.id) : scheduleReminder(for: item)
        account.markLocalChange(modelContext: modelContext)
        return true
    }

    @discardableResult private func delete(_ item: Item) -> Bool {
        let id = item.id
        do { try RecordLinkService.markDeleted(for: item, context: modelContext) }
        catch { modelContext.rollback(); errorMessage = error.localizedDescription; return false }
        withAnimation(.snappy) { item.markDeleted() }
        guard saveChanges() else { return false }
        ReminderScheduler.cancel(id: id)
        account.markLocalChange(modelContext: modelContext)
        return true
    }

    private func clearArchive(_ ids: Set<UUID>) {
        do {
            let removed = try ArchiveDeletion.clear(ids: ids, ownerID: account.userID, context: modelContext)
            removed.forEach { ReminderScheduler.cancel(id: $0) }
            if !removed.isEmpty { account.markLocalChange(modelContext: modelContext) }
        } catch { errorMessage = "Не удалось очистить архив: \(error.localizedDescription)" }
    }

    @discardableResult private func saveChanges() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.processPendingChanges()
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

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
        .environmentObject(AccountSyncController())
}
