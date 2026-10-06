//
//  DayOfWeekReportView.swift
//  FinancialTracker
//

import SwiftUI
import SwiftData
import Charts

fileprivate struct WeekdaySpendingData: Identifiable, Sendable {
    var id: Int { dayNumber }
    let dayNumber: Int
    let name: String
    let total: Double
}

struct DayOfWeekReportView: View {
    let transactions: [TransactionItem]
    let currency: String
    @AppStorage("app_language") private var appLanguage: String = "en"
    
    @State private var weekdayData: [WeekdaySpendingData] = []
    @State private var averageDailySpend: Double = 0.0
    @State private var peakDay: WeekdaySpendingData? = nil
    
    private var calculationKey: Int {
        var hasher = Hasher()
        hasher.combine(transactions.count)
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
        let lang = appLanguage
        
        let result = await Task.detached(priority: .userInitiated) { () -> ([WeekdaySpendingData], Double, WeekdaySpendingData?) in
            let calendar = Calendar.current
            let weekdayNames = L10n.weekdayNames(lang: lang)
            
            var totals = [Int: Double]()
            for i in 1...7 { totals[i] = 0.0 }
            
            for t in inputs {
                let weekday = calendar.component(.weekday, from: t.timestamp)
                totals[weekday, default: 0.0] += t.amount
            }
            
            let order = [2, 3, 4, 5, 6, 7, 1] // Monday through Sunday
            let data = order.map { w in
                WeekdaySpendingData(dayNumber: w, name: weekdayNames[w - 1], total: totals[w] ?? 0.0)
            }
            let sum = totals.values.reduce(0.0, +)
            let avg = sum / 7.0
            let peak = data.max(by: { $0.total < $1.total })
            return (data, avg, peak)
        }.value
        
        self.weekdayData = result.0
        self.averageDailySpend = result.1
        self.peakDay = result.2
    }
    
    private func formatCurrency(_ value: Double, fractionDigits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = currency.isEmpty ? "$" : currency
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? "\(currency)\(String(format: "%.\(fractionDigits)f", value))"
    }
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.tr("Spending by Day of Week", lang: appLanguage))
                    .font(.headline)
                    .lineLimit(1)
                
                Chart {
                    ForEach(weekdayData) { item in
                        BarMark(
                            x: .value("Day", item.name),
                            y: .value("Amount", item.total)
                        )
                        .foregroundStyle(item.dayNumber == peakDay?.dayNumber ? Color.blue : Color.blue.opacity(0.6))
                    }
                    
                    RuleMark(y: .value("Average", averageDailySpend))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .foregroundStyle(.orange)
                        .annotation(position: .top, alignment: .trailing) {
                            Text(L10n.tr("Avg", lang: appLanguage) + ": " + formatCurrency(averageDailySpend, fractionDigits: 0))
                                .font(.caption2.bold())
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                        }
                }
                .frame(height: 230)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    fileprivateDayCard(
                        title: L10n.tr("Daily Average", lang: appLanguage),
                        value: formatCurrency(averageDailySpend),
                        subtitle: L10n.tr("Across 7 weekdays", lang: appLanguage),
                        icon: "divide.circle.fill",
                        color: .orange
                    )
                    
                    fileprivateDayCard(
                        title: L10n.tr("Peak Day", lang: appLanguage),
                        value: peakDay?.name ?? "-",
                        subtitle: formatCurrency(peakDay?.total ?? 0) + " " + L10n.tr("total", lang: appLanguage),
                        icon: "flame.fill",
                        color: .red
                    )
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.tr("Day-by-Day Totals", lang: appLanguage))
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    
                    let maxSpend = max(1.0, peakDay?.total ?? 1.0)
                    ForEach(weekdayData) { item in
                        VStack(spacing: 4) {
                            HStack {
                                Text(item.name).font(.subheadline).lineLimit(1)
                                Spacer()
                                Text(formatCurrency(item.total))
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                            }
                            ProgressView(value: item.total / maxSpend)
                                .tint(item.dayNumber == peakDay?.dayNumber ? .red : .blue)
                        }
                        if item.id != weekdayData.last?.id { Divider() }
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal)
        }
        .task(id: calculationKey) {
            await computeMetrics()
        }
    }
}

fileprivate struct fileprivateDayCard: View {
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
