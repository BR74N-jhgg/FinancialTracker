//
//  ThemeManager.swift
//  FinancialTracker
//

import Foundation
import Combine
import SwiftUI
import UIKit

@MainActor
public final class ThemeManager: ObservableObject {
    public static let shared = ThemeManager()
    
    @Published public private(set) var currentAppearance: String = "system"
    
    private init() {
        self.currentAppearance = UserDefaults.standard.string(forKey: "app_appearance") ?? "system"
    }
    
    public var activeColorScheme: ColorScheme? {
        switch currentAppearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
    
    public var userInterfaceStyle: UIUserInterfaceStyle {
        switch currentAppearance {
        case "light": return .light
        case "dark": return .dark
        default: return .unspecified
        }
    }
    
    /// Atomically and reliably sets the theme across all windows, with no dropped states during rapid changes.
    public func applyTheme(_ appearance: String) {
        self.currentAppearance = appearance
        UserDefaults.standard.set(appearance, forKey: "app_appearance")
        
        let targetStyle = self.userInterfaceStyle
        
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                if window.overrideUserInterfaceStyle != targetStyle {
                    window.overrideUserInterfaceStyle = targetStyle
                }
            }
        }
    }
}
