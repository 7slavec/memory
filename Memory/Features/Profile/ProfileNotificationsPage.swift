import SwiftUI
import SwiftData
import UserNotifications
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ProfileNotificationsPage: View {
    @EnvironmentObject private var account: AccountSyncController
    @Environment(\.scenePhase) private var scenePhase
    @Query private var items: [Item]
    @AppStorage(ReminderScheduler.applicationNotificationsEnabledKey) private var enabled = true
    @State private var permission: UNAuthorizationStatus = .notDetermined
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 0) {
                ProfileSettingsRow(title: "Уведомления", icon: "bell") {
                    Toggle("Уведомления", isOn: Binding(get: { enabled }, set: setEnabled))
                        .labelsHidden().toggleStyle(.switch).tint(MemoryTheme.switchTint)
                }
                if permission == .denied {
                    ProfileNavigationRow(title: "Разрешить в системе", icon: "gearshape", action: openSettings)
                }
            }.memoryCard()

            VStack(spacing: 12) {
                leadTimeRow(kind: .reminder, title: "Напоминания", icon: "checkmark.circle")
                leadTimeRow(kind: .event, title: "События", icon: "calendar")
                Text("Время уведомления для новых записей. Уже созданные записи не изменятся.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
            }
            if let error { Text(error).font(.system(size: 14)).foregroundStyle(MemoryTheme.danger) }
        }
        .disabled(isWorking || account.isSavingPersonalization)
        .task { await refreshPermission() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshPermission() } }
        }
    }

    private func leadTimeRow(kind: EntryKind, title: String, icon: String) -> some View {
        ProfileSettingsRow(title: title, icon: icon) {
            Menu {
                ForEach(ReminderLeadTime.allCases) { lead in
                    Button {
                        isWorking = true
                        Task {
                            do {
                                if kind == .event { try await account.setDefaultEventReminderMinutes(lead.rawValue) }
                                else { try await account.setDefaultReminderMinutes(lead.rawValue) }
                                error = nil
                            } catch { self.error = "Не удалось сохранить время уведомления." }
                            isWorking = false
                        }
                    } label: {
                        if account.defaultReminderMinutes(for: kind) == lead.rawValue {
                            Label(lead.title, systemImage: "checkmark")
                        } else { Text(lead.title) }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(ReminderLeadTime(rawValue: account.defaultReminderMinutes(for: kind))?.compactTitle ?? "В момент")
                        .font(.system(size: 14)).lineLimit(1).minimumScaleFactor(0.85)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium))
                }.padding(.horizontal, 10).frame(minHeight: 44)
                    .background(MemoryTheme.raised, in: Capsule())
            }
#if os(macOS)
            .menuStyle(.borderlessButton)
#endif
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("\(title): время уведомления")
        }.memoryCard()
    }

    private func setEnabled(_ value: Bool) {
        enabled = value
        ReminderScheduler.setApplicationNotificationsEnabled(value)
        guard !VoiceReviewTesting.usesIsolatedStorage else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            error = nil
            if value {
                let center = UNUserNotificationCenter.current()
                if await center.notificationSettings().authorizationStatus == .notDetermined {
                    do { _ = try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
                    catch { self.error = error.localizedDescription }
                }
                await refreshPermission()
                guard permission != .denied else { return }
            }
            for item in items where item.ownerID == account.userID {
                if value, item.deletedAt == nil, !item.isCompleted,
                   item.notificationsEnabled, let date = item.dueDate {
                    do {
                        try await ReminderScheduler.schedule(id: item.id, title: item.title,
                            details: item.details, at: date, offsets: item.effectiveReminderOffsets)
                    } catch { self.error = error.localizedDescription }
                } else { ReminderScheduler.cancel(id: item.id) }
            }
            await refreshPermission()
        }
    }

    private func refreshPermission() async {
        permission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func openSettings() {
#if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
#else
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
#endif
    }
}
