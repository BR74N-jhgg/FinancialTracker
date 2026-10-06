//
//  FinancialTrackerApp.swift
//  FinancialTracker
//

import SwiftUI
import SwiftData

@main
struct FinancialTrackerApp: App {
    @ObservedObject private var themeManager = ThemeManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(themeManager.activeColorScheme)
                .onAppear {
                    themeManager.applyTheme(themeManager.currentAppearance)
                }
        }
        .modelContainer(AppDataStore.sharedModelContainer)
    }
}
