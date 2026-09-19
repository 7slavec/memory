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

private enum AllItemsGroup: CaseIterable, Identifiable {
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
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var account: AccountSyncController
    @Query(sort: \Item.timestamp, order: .reverse) private var items: [Item]
    @State private var selectedSection: MemorySection = .now
    @State private var searchText = ""
    @State private var editingItem: Item?
    @State private var recentlyAddedItem: Item?
    @State private var suppressItemOpening = false
    @State private var isAccountPresented = false
    @State private var archiveSearchText = ""
    @State private var inboxSearchText = ""
    @State private var isInboxPresented = false
    @State private var errorMessage: String?
    @State private var currentDate = Date.now
#if os(macOS)
    @State private var notificationsAreDisabled = false
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
        .task {
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
            guard phase == .active else { return }
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
#if os(macOS)
        .sheet(item: $editingItem) { item in
            ItemEditorView(
                item: item,
                onSave: { title, details, date, reminderOffsets in
                    update(
                        item,
                        title: title,
                        details: details,
                        dueDate: date,
                        reminderOffsets: reminderOffsets
                    )
                },
                onToggleCompleted: { toggleCompleted(item) },
                onDelete: { delete(item) }
            )
        }
#else
        .fullScreenCover(item: $editingItem) { item in
            ItemEditorView(
                item: item,
                onSave: { title, details, date, reminderOffsets in
                    update(
                        item,
                        title: title,
                        details: details,
                        dueDate: date,
                        reminderOffsets: reminderOffsets
                    )
                },
                onToggleCompleted: { toggleCompleted(item) },
                onDelete: { delete(item) }
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
                        Text("Norka").font(.headline)
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
                Button {
                    isAccountPresented = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: account.isSignedIn ? "checkmark.icloud.fill" : "person.crop.circle")
                            .foregroundStyle(MemoryTheme.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(account.email ?? "Аккаунт")
                                .lineLimit(1)
                            Text(account.statusText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(16)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
        } detail: {
            sectionContent
                .frame(maxWidth: 920)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .bottomTrailing) {
                    if let item = recentlyAddedItem {
                        captureConfirmation(for: item)
                            .frame(maxWidth: 470)
                            .padding(24)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
        }
    }
#endif

#if os(iOS)
    private var mobileLayout: some View {
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
                                onTogglePriority: {
                                    guard let item = homePriorityItem else { return }
                                    toggleCompleted(item)
                                },
                                onEditPriority: {
                                    guard let item = homePriorityItem else { return }
                                    editingItem = item
                                },
                                onShowAll: { navigateMobile(to: .all) },
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
                            GlassVoiceOrb(isListening: false, isPulsing: false, size: 34)
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
        .frame(height: 52)
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 2)
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
        dismissAppKeyboard()
        isInboxPresented = false
        withAnimation(.easeOut(duration: 0.16)) {
            selectedSection = section
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
        dismissAppKeyboard()
        isMobileArchivePresented = false
        withAnimation(.easeInOut(duration: 0.24)) {
            isMobileProfilePresented = true
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

    private var activeItems: [Item] { sorted(accountItems.filter { !$0.isCompleted && $0.dueDate != nil }) }
    private var overdueItems: [Item] {
        activeItems.filter { ($0.dueDate ?? .distantFuture) < currentDate }
    }
    private var todayItems: [Item] {
        activeItems.filter {
            guard let dueDate = $0.dueDate else { return false }
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
        accountItems.filter(\.isCompleted).sorted { ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt) }
    }

    private var searchTextIsEmpty: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchedActiveItems: [Item] {
        sorted(accountItems.filter { !$0.isCompleted && matchesSearch($0) })
    }

    private var searchedDatedActiveItems: [Item] {
        searchedActiveItems.filter { $0.dueDate != nil }
    }

    private var inboxItems: [Item] {
        sorted(accountItems.filter { !$0.isCompleted && $0.dueDate == nil })
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
        guard let dueDate = item.dueDate else { return .noDate }

        let calendar = Calendar.current
        if dueDate < currentDate { return .overdue }
        if calendar.isDate(dueDate, inSameDayAs: currentDate) { return .today }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: currentDate),
           calendar.isDate(dueDate, inSameDayAs: tomorrow) {
            return .tomorrow
        }
        let startOfToday = calendar.startOfDay(for: currentDate)
        if let weekHorizon = calendar.date(byAdding: .day, value: 7, to: startOfToday),
           dueDate < weekHorizon {
            return .week
        }
        return .later
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

    private func addItem(title: String, details: String?, dueDate: Date?) {
        let item = Item(
            title: title,
            details: details,
            dueDate: dueDate,
            reminderOffsets: dueDate == nil ? [] : [account.defaultReminderMinutes],
            ownerID: account.userID
        )
        withAnimation(.snappy) { modelContext.insert(item) }
        guard saveChanges() else { return }
        scheduleReminder(for: item)
        account.markLocalChange(modelContext: modelContext)
        showCaptureConfirmation(for: item)
    }

    private func update(
        _ item: Item,
        title: String,
        details: String?,
        dueDate: Date?,
        reminderOffsets: [Int]
    ) {
        item.title = title
        item.details = Item.normalizedDetails(details)
        item.dueDate = dueDate
        item.setReminderOffsets(dueDate == nil ? [] : reminderOffsets)
        item.updatedAt = .now
        guard saveChanges() else { return }
        scheduleReminder(for: item)
        account.markLocalChange(modelContext: modelContext)
    }

    private func showCaptureConfirmation(for item: Item) {
        let itemID = item.id
        withAnimation(.snappy) {
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
        let offsets = item.effectiveReminderOffsets
        Task {
            do {
                try await ReminderScheduler.schedule(
                    id: id,
                    title: title,
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

private enum QuickCaptureFocus: Hashable {
    case title
    case description
}

private struct QuickCaptureCard: View {
    @StateObject private var voiceInput = VoiceInputController()
    @State private var draft = ""
    @State private var preset: QuickDuePreset
    @State private var ignoredSmartExpression: String?
    @State private var smartResult: ParsedMemoryInput?
    @State private var details = ""
    @State private var isDescriptionPresented = false
    @State private var isVoicePulsing = false
    @State private var smartParsingTask: Task<Void, Never>?
    @State private var voiceSubmissionTask: Task<Void, Never>?
    @State private var shouldSubmitVoiceWhenStopped = false
    @State private var isFinalizingVoiceSubmission = false
    @State private var isRecordsComposerPresented = false
    @Namespace private var homeComposerNamespace
    @Namespace private var captureChromeNamespace
    @FocusState private var focusedField: QuickCaptureFocus?
    let defaultPreset: QuickDuePreset
    let isDocked: Bool
    let isHome: Bool
    let isRecordsPage: Bool
    let externalKeyboardVisible: Bool
    let priorityItem: Item?
    let isPriorityOverdue: Bool
    let additionalPriorityCount: Int
    let onTogglePriority: () -> Void
    let onEditPriority: () -> Void
    let onShowAll: () -> Void
    let onAdd: (String, String?, Date?) -> Void

    init(
        defaultPreset: QuickDuePreset,
        isDocked: Bool = false,
        isHome: Bool = false,
        isRecordsPage: Bool = false,
        externalKeyboardVisible: Bool = false,
        priorityItem: Item? = nil,
        isPriorityOverdue: Bool = false,
        additionalPriorityCount: Int = 0,
        onTogglePriority: @escaping () -> Void = {},
        onEditPriority: @escaping () -> Void = {},
        onShowAll: @escaping () -> Void = {},
        onAdd: @escaping (String, String?, Date?) -> Void
    ) {
        _preset = State(initialValue: defaultPreset)
        self.defaultPreset = defaultPreset
        self.isDocked = isDocked
        self.isHome = isHome
        self.isRecordsPage = isRecordsPage
        self.externalKeyboardVisible = externalKeyboardVisible
        self.priorityItem = priorityItem
        self.isPriorityOverdue = isPriorityOverdue
        self.additionalPriorityCount = additionalPriorityCount
        self.onTogglePriority = onTogglePriority
        self.onEditPriority = onEditPriority
        self.onShowAll = onShowAll
        self.onAdd = onAdd
    }

    var body: some View {
        Group {
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
        }
        .safeAreaInset(edge: .bottom, spacing: 18) {
            if isHome && !voiceInput.isListening && !isFinalizingVoiceSubmission {
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
            smartParsingTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(voiceInput.isListening ? 160 : 70))
                guard !Task.isCancelled else { return }
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                smartResult = ignoredSmartExpression == newValue
                    ? nil
                    : NaturalLanguageDateParser.parse(trimmed)
            }
        }
        .onChange(of: details) { oldValue, newValue in
            guard !voiceInput.isListening,
                  Self.isSingleInsertedLineBreak(from: oldValue, to: newValue) else { return }
            details = oldValue
            submit()
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
                    isFinalizingVoiceSubmission = true
                    voiceSubmissionTask?.cancel()
                    voiceSubmissionTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(70))
                        guard !Task.isCancelled,
                              shouldSubmitVoiceWhenStopped,
                              !voiceInput.isListening else { return }
                        submitVoiceRecording()
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

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: isDocked ? 10 : 14) {
            HStack(spacing: isDocked ? 10 : 12) {
                if isDocked {
                    voiceButton(size: 44)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(MemoryTheme.accent)
                        .frame(width: 34, height: 34)
                        .background(MemoryTheme.accent.opacity(0.12))
                        .clipShape(Circle())
                }

                TextField("Что нужно запомнить?", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...2)
                    .focused($focusedField, equals: .title)
                    .accessibilityIdentifier("quickCaptureField")
                    .onSubmit(handleSubmitKey)
#if os(iOS)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.sentences)
#endif

                if !isDocked {
                    voiceButton(size: 34)
                }

                if !trimmedDraft.isEmpty {
                    Button(action: cancelDraft) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: isDocked ? 40 : 34, height: isDocked ? 40 : 34)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Отменить ввод")
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
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

            if !isDocked || isComposerExpanded {
                Divider().opacity(0.55)
                HStack(spacing: 6) {
                    ForEach(QuickDuePreset.allCases) { option in
                        Button {
                            preset = option
                            ignoredSmartExpression = draft
                            smartResult = nil
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: option.icon)
                                    .font(.system(size: 12, weight: .medium))
                                Text(option.title)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                                    .allowsTightening(true)
                            }
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 7)
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(isSelected(option) ? MemoryTheme.accent.opacity(0.13) : Color.secondary.opacity(0.08))
                                .foregroundStyle(isSelected(option) ? MemoryTheme.accent : Color.secondary).clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }

                    Button {
                        toggleDescription()
                    } label: {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .background(
                                (isDescriptionPresented || !trimmedDetails.isEmpty)
                                    ? MemoryTheme.accent.opacity(0.13)
                                    : Color.secondary.opacity(0.08)
                            )
                            .foregroundStyle(
                                (isDescriptionPresented || !trimmedDetails.isEmpty)
                                    ? MemoryTheme.accent
                                    : Color.secondary
                            )
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isDescriptionPresented ? "Скрыть описание" : "Добавить описание")
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(isDocked ? 12 : 18)
        .memoryCard()
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
                            .opacity(voiceInput.isListening || isEditing || isFinalizingVoiceSubmission ? 0 : 1)

                        if voiceInput.isListening {
                            homeComposer
                                .matchedGeometryEffect(id: "homeComposer", in: homeComposerNamespace)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
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
                .opacity(voiceInput.isListening || isFinalizingVoiceSubmission ? 0 : 1)
                .allowsHitTesting(!voiceInput.isListening && !isFinalizingVoiceSubmission)
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
                isPulsing: isVoicePulsing,
                size: orbSize
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(voiceInput.isListening ? "Остановить запись" : "Начать голосовой ввод")
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

            if let smartResult {
                HStack(spacing: 9) {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.semibold))
                    Text(smartDateLabel(for: smartResult.dueDate))
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 4)
                    if !voiceInput.isListening {
                        Button {
                            ignoredSmartExpression = draft
                            self.smartResult = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Убрать распознанную дату")
                    }
                }
                .foregroundStyle(MemoryTheme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(MemoryTheme.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

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

            if !voiceInput.isListening && isComposerExpanded {
                VStack(spacing: 11) {
                    Divider().opacity(0.4)

                    HStack(spacing: 8) {
                        ForEach(QuickDuePreset.allCases) { option in
                            Button {
                                preset = option
                                ignoredSmartExpression = draft
                                smartResult = nil
                            } label: {
                                Label(option.title, systemImage: option.icon)
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .background(
                                        isSelected(option)
                                            ? MemoryTheme.accent.opacity(0.14)
                                            : Color.secondary.opacity(0.07)
                                    )
                                    .foregroundStyle(isSelected(option) ? MemoryTheme.accent : Color.secondary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            toggleDescription()
                        } label: {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 36, height: 36)
                                .background(
                                    isDescriptionPresented
                                        ? MemoryTheme.accent.opacity(0.14)
                                        : Color.secondary.opacity(0.07)
                                )
                                .foregroundStyle(isDescriptionPresented ? MemoryTheme.accent : Color.secondary)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isDescriptionPresented ? "Скрыть описание" : "Добавить описание")
                    }
                }
                .padding(.top, 1)
                .transition(.move(edge: .bottom).combined(with: .opacity))
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

    private func submitVoiceRecording() {
        let spokenText = voiceInput.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spokenText.isEmpty else { return }

        smartParsingTask?.cancel()
        let parsedResult = NaturalLanguageDateParser.parse(spokenText)
        let normalizedDetails = Item.normalizedDetails(trimmedDetails)
        let fallbackDate = preset.date

        draft = ""
        details = ""
        isDescriptionPresented = false
        preset = defaultPreset
        ignoredSmartExpression = nil
        smartResult = nil
        dismissKeyboard()

        if let parsedResult {
            onAdd(
                parsedResult.title,
                normalizedDetails,
                parsedResult.dueDate
            )
        } else {
            onAdd(
                spokenText,
                normalizedDetails,
                fallbackDate
            )
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
        smartResult = nil
        dismissKeyboard()
        if isRecordsPage {
            withAnimation(.easeInOut(duration: 0.2)) {
                isRecordsComposerPresented = false
            }
        }
    }

    private func submit() {
        guard !trimmedDraft.isEmpty else { return }
        shouldSubmitVoiceWhenStopped = false
        isFinalizingVoiceSubmission = false
        voiceSubmissionTask?.cancel()
        smartParsingTask?.cancel()
        voiceInput.stop()
        if let smartResult {
            onAdd(smartResult.title, Item.normalizedDetails(trimmedDetails), smartResult.dueDate)
        } else {
            onAdd(trimmedDraft, Item.normalizedDetails(trimmedDetails), preset.date)
        }
        draft = ""
        details = ""
        isDescriptionPresented = false
        preset = defaultPreset
        ignoredSmartExpression = nil
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
    let isPulsing: Bool
    let size: CGFloat

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
                .blur(radius: isListening ? 19 : 15)
                .opacity(isListening ? 0.7 : 0.42)
                .scaleEffect(isListening && isPulsing ? 1.08 : 1)

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
                .opacity(isListening ? 0.92 : 0.72)
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
                            Color.white.opacity(isListening ? 0.42 : 0.32),
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
            color: MemoryTheme.accent.opacity(isListening ? 0.3 : 0.16),
            radius: isListening ? 34 : 24,
            y: 12
        )
        .scaleEffect(isListening && isPulsing ? 1.025 : 1)
        .animation(.easeInOut(duration: 1.5), value: isPulsing)
        .onAppear { startRotation() }
        .accessibilityHidden(true)
    }

    private func startRotation() {
        guard !reduceMotion else { return }
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
            Button(action: onToggle) {
                Image(systemName: "circle")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(isOverdue ? Color.red.opacity(0.8) : Color.secondary.opacity(0.65))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Отметить выполненным")

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

                    Label(dateLabel, systemImage: item.notificationsEnabled ? "bell" : "calendar")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isOverdue ? Color.red : MemoryTheme.accent)
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
                    isOverdue ? Color.red.opacity(0.09) : MemoryTheme.accent.opacity(0.08),
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
                    isOverdue ? Color.red.opacity(0.14) : MemoryTheme.accent.opacity(0.1),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.05), radius: 14, y: 7)
    }

    private var dateLabel: String {
        guard let date = item.dueDate else { return "Без срока" }
        let time = date.formatted(date: .omitted, time: .shortened)
        if isOverdue { return "Просрочено · \(time)" }
        if Calendar.current.isDateInToday(date) { return "Сегодня · \(time)" }
        if Calendar.current.isDateInTomorrow(date) { return "Завтра · \(time)" }
        return date.formatted(date: .abbreviated, time: .shortened)
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
        if item.isCompleted {
            guard let completedAt = item.completedAt else { return "Выполнено" }
            return "Выполнено · \(completedAt.formatted(date: .abbreviated, time: .omitted))"
        }
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
