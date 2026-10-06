//
//  AnalyticsModels.swift
//  FinancialTracker
//

import SwiftUI
import Charts

public enum AnalyticsReportType: String, CaseIterable, Identifiable {
    case dayOfWeek = "Day of Week"         // Option 3 (Default)
    case monthlyPacing = "Monthly Pacing"  // Option 1
    case cashFlow = "Cash Flow"            // Option 2
    case paymentMethods = "Payment Share"  // Option 4
    case topMerchants = "Top Merchants"    // Option 5
    case categories = "Categories"         // Category breakdown
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .dayOfWeek: return "calendar.day.timeline.leading"
        case .monthlyPacing: return "chart.line.uptrend.xyaxis"
        case .cashFlow: return "arrow.left.arrow.right"
        case .paymentMethods: return "creditcard.fill"
        case .topMerchants: return "building.2.fill"
        case .categories: return "chart.pie.fill"
        }
    }
}


// MARK: - Models for Analytics Charts (Swift 6 Top-Level Sendable Types)

public struct DaySpend: Identifiable, Equatable, Sendable {
    public var id: Int { dayNumber }
    public let dayNumber: Int
    public let name: String
    public let total: Double
    
    public init(dayNumber: Int, name: String, total: Double) {
        self.dayNumber = dayNumber
        self.name = name
        self.total = total
    }
}

public struct DayTrajectory: Identifiable, Equatable, Sendable {
    public var id: Int { day }
    public let day: Int
    public let cumulativeAmount: Double
    
    public init(day: Int, cumulativeAmount: Double) {
        self.day = day
        self.cumulativeAmount = cumulativeAmount
    }
}

public struct FlowItem: Identifiable, Equatable, Sendable {
    public var id: String { type }
    public let type: String
    public let localizedType: String
    public let amount: Double
    public let isIncome: Bool
    
    public var color: Color {
        isIncome ? .green : .red
    }
    
    public init(type: String, localizedType: String, amount: Double, isIncome: Bool) {
        self.type = type
        self.localizedType = localizedType
        self.amount = amount
        self.isIncome = isIncome
    }
}

public struct MethodShare: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let icon: String
    public let colorHex: String
    public let total: Double
    public let count: Int
    
    public init(name: String, icon: String, colorHex: String, total: Double, count: Int) {
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.total = total
        self.count = count
    }
}

public struct MerchantRank: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let total: Double
    public let count: Int
    
    public init(name: String, total: Double, count: Int) {
        self.name = name
        self.total = total
        self.count = count
    }
}

public struct CatTotal: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let icon: String
    public let colorHex: String
    public let total: Double
    
    public init(name: String, icon: String, colorHex: String, total: Double) {
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.total = total
    }
}


// MARK: - Reusable Insight Card
struct InsightCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Image(systemName: icon).font(.caption).foregroundStyle(color)
            }
            Text(value).font(.title3.bold()).lineLimit(1)
            Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

