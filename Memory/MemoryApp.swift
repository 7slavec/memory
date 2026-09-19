//
//  MemoryApp.swift
//  Memory
//
//  Created by Вячеслав Храмышкин on 15.09.2026.
//

import SwiftUI
import SwiftData

@main
struct MemoryApp: App {
    @StateObject private var account = AccountSyncController()
    @AppStorage(AppAppearance.storageKey) private var appAppearance: AppAppearance = .system

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

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

                ContentView()
                    .environmentObject(account)
            }
            .preferredColorScheme(appAppearance.colorScheme)
        }
        .modelContainer(sharedModelContainer)
    }
}
