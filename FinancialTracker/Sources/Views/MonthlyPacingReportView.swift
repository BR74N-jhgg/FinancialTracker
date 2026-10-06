//
//  MonthlyPacingReportView.swift
//  FinancialTracker
//

import SwiftUI
import SwiftData
import Charts

struct DayPacing: Identifiable, Sendable {
    var id: Int { day }
    let day: Int
    let actualCumulative: Double?
    let budgetPace: Double
}

struct MonthlyPacingReportView: View {
    let transactions: [TransactionItem]
    let budget: Double
    let currency: String
    @AppStorage("app_language") private var appLanguage: String = "en"
    
    @State private var dailyPacingData: [DayPacing] = []
    @State private var totalSpentSoFar: Double = 0.0
    @State private var projectedMonthEnd: Double = 0.0
    @State private var currentDayOfMonth: Int = 1
    @State private var daysInMonth: Int = 30
    
    private var calculationKey: Int {
        var hasher = Hasher()
        hasher.combine(transactions.count)
        hasher.combine(budget)
        hasher.combine(appLanguage)
        if let first = transactions.first {
            hasher.combine(first.timestamp)
            hasher.combine(first.amount)
        }
        return hasher.finalize()
    }
    
    nonisolated private struct ExpenseInput: Sendable {
        let timestamp: Date
        let amount: Double
    }
    
    private func computeMetrics() async {
        let inputs: [ExpenseInput] = transactions.compactMap { item in
            guard item.type == .expense && !item.isExcludedFromBudget else { return nil }
            return ExpenseInput(timestamp: item.timestamp, amount: item.amount)
        }
        let b = budget
        
        let result = await Task.detached(priority: .userInitiated) { () -> ([DayPacing], Double, Double, Int, Int) in
            let calendar = Calendar.current
            let now = Date()
            
            let range = calendar.range(of: .day, in: .month, for: now)
            let totalDays = range?.count ?? 30
            let currentDay = calendar.component(.day, from: now)
            let currentMonth = calendar.component(.month, from: now)
            let currentYear = calendar.component(.year, from: now)
            
            var dayTotals = [Int: Double]()
            for d in 1...totalDays { dayTotals[d] = 0.0 }
            
            for t in inputs {
                let m = calendar.component(.month, from: t.timestamp)
                let y = calendar.component(.year, from: t.timestamp)
                if m == currentMonth && y == currentYear {
                    let day = calendar.component(.day, from: t.timestamp)
                    dayTotals[day, default: 0.0] += t.amount
                }
            }
            
            var runningTotal: Double = 0.0
            var pacingList: [DayPacing] = []
            let dailyBudgetRate = b > 0 ? (b / Double(totalDays)) : 0.0
            
            for d in 1...totalDays {
                let targetPace = dailyBudgetRate * Double(d)
                if d <= currentDay {
                    runningTotal += (dayTotals[d] ?? 0.0)
                    pacingList.append(DayPacing(day: d, actualCumulative: runningTotal, budgetPace: targetPace))
                } else {
                    pacingList.append(DayPacing(day: d, actualCumulative: nil, budgetPace: targetPace))
                }
            }
            
            let projected: Double
            if currentDay > 0 {
                projected = (runningTotal / Double(currentDay)) * Double(totalDays)
            } else {
                projected = runningTotal
            }
            
            return (pacingList, runningTotal, projected, currentDay, totalDays)
        }.value
        
        self.dailyPacingData = result.0
        self.totalSpentSoFar = result.1
        self.projectedMonthEnd = result.2
        self.currentDayOfMonth = result.3
        self.daysInMonth = result.4
    }
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.tr("Monthly Budget Pacing", lang: appLanguage))
                    .font(.headline)
                    .lineLimit(1)
                
                Chart {
                    ForEach(dailyPacingData) { item in
                        LineMark(
                            x: .value("Day", item.day),
                            y: .value("Budget Pace", item.budgetPace)
                        )
                        .foregroundStyle(Color.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        
                        if let actual = item.actualCumulative {
                            LineMark(
                                x: .value("Day", item.day),
                                y: .value("Actual Spend", actual)
                            )
                            .foregroundStyle(actual > item.budgetPace && budget > 0 ? Color.red : Color.blue)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            
                            AreaMark(
                                x: .value("Day", item.day),
                                y: .value("Actual Spend", actual)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [(actual > item.budgetPace && budget > 0 ? Color.red : Color.blue).opacity(0.2), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                    }
                    
                    if budget > 0 {
                        RuleMark(y: .value("Monthly Budget", budget))
                            .foregroundStyle(Color.red.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    }
                }
                .frame(height: 230)
                .chartXScale(domain: 1...max(1, daysInMonth))
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    fileprivatePacingCard(
                        title: L10n.tr("Spent So Far", lang: appLanguage),
                        value: AppFormatters.formatCurrency(totalSpentSoFar, currency: currency),
                        subtitle: "\(currentDayOfMonth) / \(daysInMonth) " + L10n.tr("days", lang: appLanguage),
                        icon: "creditcard.fill",
                        color: .blue
                    )
                    
                    let isOverBudget = budget > 0 && projectedMonthEnd > budget
                    fileprivatePacingCard(
                        title: L10n.tr("Projected Total", lang: appLanguage),
                        value: AppFormatters.formatCurrency(projectedMonthEnd, currency: currency, fractionDigits: 0),
                        subtitle: budget > 0 ? (isOverBudget ? L10n.tr("Over Budget", lang: appLanguage) : L10n.tr("Within Budget", lang: appLanguage)) : L10n.tr("Based on pace", lang: appLanguage),
                        icon: isOverBudget ? "exclamationmark.triangle.fill" : "checkmark.seal.fill",
                        color: isOverBudget ? .red : .green
                    )
                }
                
                HStack(spacing: 12) {
                    fileprivatePacingCard(
                        title: L10n.tr("Monthly Budget", lang: appLanguage),
                        value: budget > 0 ? AppFormatters.formatCurrency(budget, currency: currency, fractionDigits: 0) : L10n.tr("Not Set", lang: appLanguage),
                        subtitle: budget > 0 ? "\(Int(min(999, (totalSpentSoFar / budget) * 100)))% " + L10n.tr("used", lang: appLanguage) : "-",
                        icon: "target",
                        color: .purple
                    )
                    
                    let remaining = max(0, budget - totalSpentSoFar)
                    fileprivatePacingCard(
                        title: L10n.tr("Remaining", lang: appLanguage),
                        value: budget > 0 ? AppFormatters.formatCurrency(remaining, currency: currency, fractionDigits: 0) : "-",
                        subtitle: budget > 0 ? "\(AppFormatters.formatCurrency(remaining / Double(max(1, daysInMonth - currentDayOfMonth)), currency: currency, fractionDigits: 0)) / " + L10n.tr("day left", lang: appLanguage) : "-",
                        icon: "wallet.pass.fill",
                        color: remaining > 0 ? .teal : .red
                    )
                }
            }
            .padding(.horizontal)
        }
        .task(id: calculationKey) {
            await computeMetrics()
        }
    }
}

fileprivate struct fileprivatePacingCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.subheadline)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.headline)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
