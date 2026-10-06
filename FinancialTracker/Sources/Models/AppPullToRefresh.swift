//
//  AppPullToRefresh.swift
//  FinancialTracker
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - 1. Dedicated Class with lazy var
/// A manager class holding the lazy haptic generator at the type level (non-local scope).
final class HapticFeedbackManager {
    static let shared = HapticFeedbackManager()
    private init() {}
    
    // ✅ LAZY VAR: Only allocated in memory the very first time the user pulls down to refresh!
    lazy var mediumImpact: UIImpactFeedbackGenerator = {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        return generator
    }()
    
    func playImpact() {
        mediumImpact.impactOccurred()
        mediumImpact.prepare() // Pre-warms the Taptic Engine for subsequent pulls
    }
}

// MARK: - 2. SwiftUI ViewModifier
struct AppPullToRefreshModifier: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    var onRefresh: (() -> Void)? = nil
    
    init(onRefresh: (() -> Void)? = nil) {
        self.onRefresh = onRefresh
    }
    
    func body(content: Content) -> some View {
        content.refreshable {
            // 1. Brief 350ms delay for smooth spinner dismiss animation
            try? await Task.sleep(nanoseconds: 350_000_000)
            
            // 2. Execute custom view-specific reload action
            await MainActor.run {
                onRefresh?()
            }
            
            // 3. Always synchronize widgets with latest SwiftData context
            WidgetSyncManager.shared.syncWidget(context: modelContext)
            
            // 4. Trigger the lazy generator (created on first call, reused thereafter)
            HapticFeedbackManager.shared.playImpact()
        }
    }
}

// MARK: - 3. View Extension
extension View {
    func appPullToRefresh(action: (() -> Void)? = nil) -> some View {
        modifier(AppPullToRefreshModifier(onRefresh: action))
    }
}
