import Foundation
import SwiftData

public enum AccountType: String, Codable, CaseIterable {
    case asset = "Asset"         // Cash, Bank Savings, Octopus, PayMe
    case liability = "Liability" // Credit Card, Loan
    
    public var localizedName: String {
        switch self {
        case .asset: return "Asset (Debit/Cash)"
        case .liability: return "Liability (Credit Card)"
        }
    }
}

@Model
public final class PaymentMethodItem {
    public var id: UUID
    public var name: String
    public var iconName: String
    public var colorHex: String
    public var accountTypeRaw: String
    public var initialBalance: Double
    public var currentBalance: Double
    public var statementDay: Int?
    
    public var accountType: AccountType {
        get { AccountType(rawValue: accountTypeRaw) ?? .asset }
        set { accountTypeRaw = newValue.rawValue }
    }
    
    public var isAsset: Bool {
        accountType == .asset
    }
    
    public var isLiability: Bool {
        accountType == .liability
    }
    
    // Convenience property for backwards compatibility with any view accessing sfSymbol
    public var sfSymbol: String {
        iconName
    }
    
    public init(
        id: UUID = UUID(),
        name: String,
        iconName: String = "creditcard.fill",
        colorHex: String = "#007AFF",
        accountType: AccountType = .asset,
        initialBalance: Double = 0.0,
        currentBalance: Double? = nil,
        statementDay: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.accountTypeRaw = accountType.rawValue
        self.initialBalance = initialBalance
        self.currentBalance = currentBalance ?? initialBalance
        self.statementDay = statementDay
    }
    
    public struct DefaultAccountSpec {
        public let name: String
        public let icon: String
        public let color: String
        public let type: AccountType
        public let defaultBalance: Double
        public let statementDay: Int?
    }
    
    public static let defaultAccounts: [DefaultAccountSpec] = [
        DefaultAccountSpec(name: "HSBC Savings", icon: "building.columns.fill", color: "#5856D6", type: .asset, defaultBalance: 50000.0, statementDay: nil),
        DefaultAccountSpec(name: "BOCHK", icon: "banknote.fill", color: "#10B981", type: .asset, defaultBalance: 20000.0, statementDay: nil),
        DefaultAccountSpec(name: "Octopus", icon: "wave.3.forward.circle.fill", color: "#FF9500", type: .asset, defaultBalance: 350.0, statementDay: nil),
        DefaultAccountSpec(name: "Cash", icon: "dollarsign.circle.fill", color: "#34C759", type: .asset, defaultBalance: 800.0, statementDay: nil),
        DefaultAccountSpec(name: "PayMe", icon: "p.circle.fill", color: "#FF2D55", type: .asset, defaultBalance: 1200.0, statementDay: nil),
        DefaultAccountSpec(name: "HSBC Red Card", icon: "creditcard.fill", color: "#E11D48", type: .liability, defaultBalance: -2850.0, statementDay: 7),
        DefaultAccountSpec(name: "Credit Card", icon: "creditcard.fill", color: "#007AFF", type: .liability, defaultBalance: -1420.0, statementDay: 15)
    ]
    
    // Legacy mapping support for SettingsView and AnalyticsView
    public static let defaultMethods: [(name: String, icon: String, color: String)] = [
        ("Apple Pay", "apple.logo", "#000000"),
        ("Credit Card", "creditcard.fill", "#007AFF"),
        ("Octopus", "wave.3.forward.circle.fill", "#FF9500"),
        ("Bank Transfer / FPS", "building.columns.fill", "#5856D6"),
        ("Cash", "banknote.fill", "#34C759")
    ]
}
