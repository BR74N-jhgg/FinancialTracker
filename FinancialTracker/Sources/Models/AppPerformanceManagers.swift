//
//  AppPerformanceManagers.swift
//  FinancialTracker
//

import Foundation
import UIKit

// MARK: - 1. Lazy JSON Serialization Manager
public final class AppSerializationManager {
    public static let shared = AppSerializationManager()
    private init() {}
    
    // ✅ LAZY VAR: Created once upon first decode call
    public private(set) lazy var jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()
    
    // ✅ LAZY VAR: Created once upon first encode call
    public private(set) lazy var jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        return encoder
    }()
}

public final class AppFormatters {
    public static let shared = AppFormatters()
    private init() {}
    
    /// Lazy NumberFormatter configured with '.' for thousands and ',' for decimals
    public private(set) lazy var financialNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
    
    /// Integer-only formatter for rounded budgets (e.g. 15.000 instead of 15.000,00)
    public private(set) lazy var integerFinancialFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }()
    
    public static func formatAmount(_ amount: Double, fractionDigits: Int = 2) -> String {
        let formatter = fractionDigits == 0 ? shared.integerFinancialFormatter : shared.financialNumberFormatter
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }
    
    public static func formatCurrency(_ amount: Double, currency: String = "HKD", fractionDigits: Int = 2) -> String {
        let formatted = formatAmount(amount, fractionDigits: fractionDigits)
        let curr = currency.isEmpty ? "HKD" : currency
        return "\(curr) \(formatted)"
    }
}

// MARK: - Double Extension for One-Line Formatting
extension Double {
    /// Formats a Double into financial format with '.' thousands and ',' decimals (e.g. 100.000.000,00)
    public var financialFormatted: String {
        AppFormatters.formatAmount(self, fractionDigits: 2)
    }
    
    /// Formats a Double into integer financial format (e.g. 1.000, 15.000)
    public var financialIntegerFormatted: String {
        AppFormatters.formatAmount(self, fractionDigits: 0)
    }
    
    /// Formats a Double with currency code (e.g. HKD 100.000.000,00)
    public func formattedCurrency(_ currency: String = "HKD") -> String {
        AppFormatters.formatCurrency(self, currency: currency, fractionDigits: 2)
    }
}
