//
//  ContentView.swift
//  FinancialTracker
//

import SwiftUI
import SwiftData

public struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("app_language") private var appLanguage: String = "en"
    @AppStorage("has_completed_initial_demo_setup_v3") private var hasCompletedInitialSetup: Bool = false
    
    @State private var selectedTab: Int = 0
    @State private var isLoadingScreenVisible: Bool = true
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Main App Navigation
            TabView(selection: $selectedTab) {
                DashboardView(onNavigateToAnalytics: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedTab = 2
                    }
                })
                .tabItem {
                    Label(L10n.tr("Dashboard", lang: appLanguage), systemImage: "chart.bar.xaxis")
                }
                .tag(0)
                .gesture(swipeGesture(currentTab: 0))
                
                TransactionListView()
                    .tabItem {
                        Label(L10n.tr("Transactions", lang: appLanguage), systemImage: "list.bullet.rectangle.portrait")
                    }
                    .tag(1)
                
                AnalyticsView()
                    .tabItem {
                        Label(L10n.tr("Analytics", lang: appLanguage), systemImage: "chart.pie.fill")
                    }
                    .tag(2)
                    .gesture(swipeGesture(currentTab: 2))
                
                SettingsView()
                    .tabItem {
                        Label(L10n.tr("Settings", lang: appLanguage), systemImage: "gearshape.fill")
                    }
                    .tag(3)
                    .gesture(swipeGesture(currentTab: 3))
            }
            
            // Initial Launch & Loading Screen
            if isLoadingScreenVisible {
                LoadingScreenView()
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
                    .zIndex(100)
            }
        }
        .environment(\.locale, Locale(identifier: appLanguage))
        .task {
                    // Run initialization asynchronously
                    seedDefaultsIfNeeded()
                    WidgetSyncManager.shared.syncWidget(context: modelContext)
                    
                    // Dismiss loading screen immediately with a smooth fade
                    withAnimation(.easeOut(duration: 0.25)) {
                        isLoadingScreenVisible = false
                    }
                }
    }
    
    // Smooth horizontal swipe gesture to switch between pages
    private func swipeGesture(currentTab: Int) -> some Gesture {
        DragGesture(minimumDistance: 35, coordinateSpace: .local)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) * 1.5, abs(horizontal) > 45 else { return }
                if horizontal < 0 {
                    if currentTab < 3 {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedTab = currentTab + 1
                        }
                    }
                } else if horizontal > 0 {
                    if currentTab > 0 {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedTab = currentTab - 1
                        }
                    }
                }
            }
    }
    
    private func seedDefaultsIfNeeded() {
        // Runs ONCE on initial startup: populates categories, accounts, and sample transactions.
        guard !hasCompletedInitialSetup else { return }
        SampleDataSeeder.seedAll(context: modelContext)
        hasCompletedInitialSetup = true
    }
}
