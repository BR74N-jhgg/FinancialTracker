//
//  DashboardMiniSnapshots.swift
//  Worthly
//

import Foundation
import SwiftUI
import Charts

// MARK: - Models for Dashboard Snapshots (Swift 6 Top-Level Sendable Types)

public struct TrendPoint: Identifiable, Equatable, Sendable {
    public var id: Int { day }
    public let day: Int
    public let amount: Double
    
    public init(day: Int, amount: Double) {
        self.day = day
        self.amount = amount
    }
}

public struct DashboardDayItem: Identifiable, Equatable, Sendable {
    public var id: Int { day }
    public let day: Int
    public let name: String
    public let total: Double
    
    public init(day: Int, name: String, total: Double) {
        self.day = day
        self.name = name
        self.total = total
    }
}

public struct DashboardFlowBar: Identifiable, Equatable, Sendable {
    public var id: String { label }
    public let label: String
    public let amount: Double
    public let isIncome: Bool
    
    public var color: Color {
        isIncome ? .green : .red
    }
    
    public init(label: String, amount: Double, isIncome: Bool) {
        self.label = label
        self.amount = amount
        self.isIncome = isIncome
    }
}

public struct DashboardCatShare: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let colorHex: String
    public let total: Double
    
    public init(name: String, colorHex: String, total: Double) {
        self.name = name
        self.colorHex = colorHex
        self.total = total
    }
}

public struct DashboardMethodItem: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let colorHex: String
    public let total: Double
    
    public init(name: String, colorHex: String, total: Double) {
        self.name = name
        self.colorHex = colorHex
        self.total = total
    }
}

public struct DashboardMerchantItem: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let total: Double
    
    public init(name: String, total: Double) {
        self.name = name
        self.total = total
    }
}

public struct DashboardMetricsSnapshot: Equatable, Sendable {
    public let key: Int
    public let totalSpentThisMonth: Double
    public let monthlyTrendData: [TrendPoint]
    public let dayOfWeek: [DashboardDayItem]
    public let cashFlow: [DashboardFlowBar]
    public let categories: [DashboardCatShare]
    public let paymentMethods: [DashboardMethodItem]
    public let topMerchants: [DashboardMerchantItem]
    
    public init(
        key: Int,
        totalSpentThisMonth: Double,
        monthlyTrendData: [TrendPoint],
        dayOfWeek: [DashboardDayItem],
        cashFlow: [DashboardFlowBar],
        categories: [DashboardCatShare],
        paymentMethods: [DashboardMethodItem],
        topMerchants: [DashboardMerchantItem]
    ) {
        self.key = key
        self.totalSpentThisMonth = totalSpentThisMonth
        self.monthlyTrendData = monthlyTrendData
        self.dayOfWeek = dayOfWeek
        self.cashFlow = cashFlow
        self.categories = categories
        self.paymentMethods = paymentMethods
        self.topMerchants = topMerchants
    }
}

// MARK: - Mini Snapshots
public struct MiniDayOfWeekSnapshot: View {
    let data: [DashboardDayItem]
    
    public init(data: [DashboardDayItem]) {
        self.data = data
    }
    
    public var body: some View {
        Chart(data) { item in
            BarMark(
                x: .value("Day", item.name),
                y: .value("Amount", item.total)
            )
            .foregroundStyle(Color.blue.gradient)
            .cornerRadius(4)
        }
        .frame(height: 120)
    }
}

public struct MiniCashFlowSnapshot: View {
    let data: [DashboardFlowBar]
    
    public init(data: [DashboardFlowBar]) {
        self.data = data
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            Chart(data) { item in
                BarMark(
                    x: .value("Type", item.label),
                    y: .value("Amount", item.amount)
                )
                .foregroundStyle(item.color.gradient)
                .cornerRadius(4)
            }
            .frame(height: 110)
        }
    }
}

public struct MiniCategorySnapshot: View {
    let data: [DashboardCatShare]
    let currency: String
    
    public init(data: [DashboardCatShare], currency: String) {
        self.data = data
        self.currency = currency
    }
    
    public var body: some View {
        if data.isEmpty {
            HStack {
                Spacer()
                Text("No category data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 36)
                Spacer()
            }
        } else {
            HStack(spacing: 16) {
                Chart(data) { item in
                    SectorMark(
                        angle: .value("Amount", item.total),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .foregroundStyle(Color(hex: item.colorHex))
                }
                .frame(width: 100, height: 100)
                
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(data) { item in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: item.colorHex))
                                .frame(width: 8, height: 8)
                            Text(item.name)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(String(format: "%@ %.0f", currency, item.total))
                                .font(.caption.bold())
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

public struct MiniPaymentMethodSnapshot: View {
    let data: [DashboardMethodItem]
    
    public init(data: [DashboardMethodItem]) {
        self.data = data
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            Chart(data) { item in
                BarMark(
                    x: .value("Amount", item.total),
                    y: .value("Method", item.name)
                )
                .foregroundStyle(Color(hex: item.colorHex).gradient)
                .cornerRadius(4)
            }
            .frame(height: 110)
        }
    }
}

public struct MiniTopMerchantsSnapshot: View {
    let data: [DashboardMerchantItem]
    
    public init(data: [DashboardMerchantItem]) {
        self.data = data
    }
    
    public var body: some View {
        Chart(data) { item in
            BarMark(
                x: .value("Amount", item.total),
                y: .value("Merchant", item.name)
            )
            .foregroundStyle(Color.indigo.gradient)
            .cornerRadius(4)
        }
        .frame(height: 110)
    }
}

// MARK: - Circular Progress Helper
public struct CircularProgressView: View {
    public let progress: Double
    
    public init(progress: Double) {
        self.progress = progress
    }
    
    public var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 6)
            
            Circle()
                .trim(from: 0.0, to: CGFloat(min(progress, 1.0)))
                .stroke(
                    progress > 0.9 ? Color.red : (progress > 0.75 ? Color.orange : Color.blue),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)
            
            Text(String(format: "%.0f%%", progress * 100))
                .font(.caption2.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}
