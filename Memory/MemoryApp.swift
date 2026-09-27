//
//  MemoryApp.swift
//  Memory
//
//  Created by Вячеслав Храмышкин on 15.09.2026.
//

import SwiftUI
import SwiftData
import UserNotifications
#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if os(macOS)
final class MemoryAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self

        // Test hosts and the DEBUG-only in-memory UI fixture must not activate
        // the user's existing app and terminate before XCTest can connect.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              !VoiceReviewTesting.isEnabled, !DesignCatalogMode.isEnabled else { return }
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        guard let existingApplication = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { $0.processIdentifier != currentProcessID }) else { return }

        existingApplication.activate(options: [.activateAllWindows])
        NSApplication.shared.terminate(nil)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
#else
final class MemoryAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
#endif

private struct InitialAccessRootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var account: AccountSyncController
    @AppStorage("hasCompletedInitialAccessChoice")
    private var hasCompletedInitialAccessChoice = false
    @AppStorage("isInitialAccessPreviewPending")
    private var isInitialAccessPreviewPending = false
    @State private var hasStartedInitialAccess = false
    @State private var isLogoVisible = false
    @State private var isAuthenticationPresented = false
    @State private var hasFinishedInitialAccessPreview = false

    private var isInitialAccessPreviewRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--preview-initial-access")
    }

    private var isInitialAccessPreview: Bool {
        isInitialAccessPreviewRequested || isInitialAccessPreviewPending
    }

    private var needsInitialAccess: Bool {
        !hasCompletedInitialAccessChoice
            || (isInitialAccessPreview && !hasFinishedInitialAccessPreview)
    }

    var body: some View {
        ZStack {
            MemoryTheme.background
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if DesignCatalogMode.isEnabled {
#if DEBUG
                DesignCatalogView()
#else
                EmptyView()
#endif
            } else if VoiceReviewTesting.isEnabled || !needsInitialAccess {
                ContentView()
                    .transition(.opacity)
            } else if isAuthenticationPresented {
                AccountView(
                    showsDismissButton: false,
                    onContinueLocally: completeInitialAccess,
                    onAuthenticationCompleted: completeInitialAccess,
                    forcesAuthentication: isInitialAccessPreview
                )
                .transition(
                    .opacity.combined(
                        with: reduceMotion ? .identity : .scale(scale: 0.985)
                    )
                )
            } else {
                initialLogo
            }
        }
        .task {
            guard !VoiceReviewTesting.isEnabled, !DesignCatalogMode.isEnabled else { return }
            if isInitialAccessPreviewRequested {
                isInitialAccessPreviewPending = true
            }
            await prepareInitialAccessIfNeeded()
        }
    }

    private var initialLogo: some View {
        Image("NorkaLogo")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundStyle(.primary)
            .frame(width: 154, height: 48)
            .opacity(isLogoVisible ? 1 : 0)
            .scaleEffect(reduceMotion || isLogoVisible ? 1 : 0.92)
            .blur(radius: reduceMotion || isLogoVisible ? 0 : 7)
            .accessibilityLabel("Norka")
    }

    @MainActor
    private func prepareInitialAccessIfNeeded() async {
        guard needsInitialAccess, !hasStartedInitialAccess else { return }
        hasStartedInitialAccess = true

        if reduceMotion {
            isLogoVisible = true
        } else {
            withAnimation(.spring(response: 0.72, dampingFraction: 0.86)) {
                isLogoVisible = true
            }
        }

        async let minimumLogoDuration: Void = waitForInitialLogo()
        await account.restoreSession()
        await minimumLogoDuration

        guard !Task.isCancelled else { return }
        if account.isSignedIn && !isInitialAccessPreview {
            completeInitialAccess()
        } else {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.32)) {
                isAuthenticationPresented = true
            }
        }
    }

    private func waitForInitialLogo() async {
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 180 : 900))
    }

    @MainActor
    private func completeInitialAccess() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
            hasCompletedInitialAccessChoice = true
            isAuthenticationPresented = false
            hasFinishedInitialAccessPreview = true
            isInitialAccessPreviewPending = false
        }
    }
}

@main
struct MemoryApp: App {
#if os(macOS)
    @NSApplicationDelegateAdaptor(MemoryAppDelegate.self) private var appDelegate
#else
    @UIApplicationDelegateAdaptor(MemoryAppDelegate.self) private var appDelegate
#endif
    @StateObject private var account = AccountSyncController()
    @AppStorage(AppAppearance.storageKey) private var appAppearance: AppAppearance = .system

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: VoiceReviewTesting.isEnabled || DesignCatalogMode.isEnabled)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ZStack {
                MemoryTheme.background
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                InitialAccessRootView()
                    .environmentObject(account)
            }
            .preferredColorScheme(appAppearance.colorScheme)
        }
        .modelContainer(sharedModelContainer)
#if os(macOS)
        .defaultSize(width: 1080, height: 760)
        .windowResizability(.contentMinSize)
#endif
    }
}
