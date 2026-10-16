//
//  MonthlyPacingReportView.swift
//  Worthly
//

import SwiftUI
import SwiftData
import Charts

struct DayPacing: Identifiable, Sendable {
    var id: Int { day }
    let day: Int
    let dailySpend: Double
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
    @State private var currentDayOfMonth: Int = 1
    @State private var daysInMonth: Int = 30
    @State private var noSpendDaysCount: Int = 0
    @State private var biggestDay: (day: Int, amount: Double) = (1, 0.0)
    @State private var selectedDay: Int? = nil
    @State private var showCumulativeChart: Bool = false
    
    private var calculationKey: Int {
        var hasher = Hasher()
        hasher.combine(transactions.count)
        hasher.combine(budget)
        hasher.combine(appLanguage)
        for item in transactions.prefix(10) {
            hasher.combine(item.id)
            hasher.combine(item.timestamp)
            hasher.combine(item.amount)
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
        
        let result = await Task.detached(priority: .userInitiated) { () -> ([DayPacing], Double, Int, Int, Int, Int, Double) in
            let calendar = Calendar.current
            let now = Date()
            
            let range = calendar.range(of: .day, in: .month, for: now)
            let totalDays = range?.count ?? 30
            let currentDay = max(1, calendar.component(.day, from: now))
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
            var zeroDays = 0
            var maxDay = 1
            var maxDayAmount = 0.0
            
            for d in 1...totalDays {
                let targetPace = dailyBudgetRate * Double(d)
                let spendToday = dayTotals[d] ?? 0.0
                if d <= currentDay {
                    runningTotal += spendToday
                    if spendToday == 0 {
                        zeroDays += 1
                    }
                    if spendToday > maxDayAmount {
                        maxDayAmount = spendToday
                        maxDay = d
                    }
                    pacingList.append(DayPacing(day: d, dailySpend: spendToday, actualCumulative: runningTotal, budgetPace: targetPace))
                } else {
                    pacingList.append(DayPacing(day: d, dailySpend: 0.0, actualCumulative: nil, budgetPace: targetPace))
                }
            }
            
            return (pacingList, runningTotal, currentDay, totalDays, zeroDays, maxDay, maxDayAmount)
        }.value
        
        self.dailyPacingData = result.0
        self.totalSpentSoFar = result.1
        self.currentDayOfMonth = result.2
        self.daysInMonth = result.3
        self.noSpendDaysCount = result.4
        self.biggestDay = (result.5, result.6)
    }
    
    var body: some View {
        let dailyTarget = budget > 0 ? (budget / Double(max(1, daysInMonth))) : 0.0
        let remainingDays = max(1, daysInMonth - currentDayOfMonth)
        let remainingBudget = max(0, budget - totalSpentSoFar)
        let safeDailyAllowance = remainingBudget / Double(remainingDays)
        let isOverBudget = budget > 0 && totalSpentSoFar > budget
        let overBudgetAmount = max(0, totalSpentSoFar - budget)
        let monthProgress = Double(currentDayOfMonth) / Double(max(1, daysInMonth))
        let budgetUsedRatio = budget > 0 ? (totalSpentSoFar / budget) : 0.0
        let isAheadOfTime = budgetUsedRatio > monthProgress + 0.05
        
        VStack(spacing: 18) {
            // MARK: - 1. Plain-English Budget Pacing Coach Card
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appLanguage == "zh-HK" ? "本月預算進度" : "Monthly Budget Status")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(AppFormatters.formatCurrency(totalSpentSoFar, currency: currency))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(isOverBudget ? .red : .primary)
                            if budget > 0 {
                                Text("/ \(AppFormatters.formatCurrency(budget, currency: currency, fractionDigits: 0))")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Status Badge
                    Text(
                        isOverBudget
                        ? (appLanguage == "zh-HK" ? "已超支" : "Over Budget")
                        : (isAheadOfTime
                            ? (appLanguage == "zh-HK" ? "花費偏快" : "Spending Fast")
                            : (appLanguage == "zh-HK" ? "進度理想" : "On Track"))
                    )
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        (isOverBudget ? Color.red : (isAheadOfTime ? Color.orange : Color.green)).opacity(0.15)
                    )
                    .foregroundStyle(isOverBudget ? .red : (isAheadOfTime ? .orange : .green))
                    .clipShape(Capsule())
                }
                
                // Visual Two-Bar Comparison: "Money Spent" vs "Time Passed"
                if budget > 0 {
                    VStack(spacing: 10) {
                        // Bar 1: Budget Used
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(appLanguage == "zh-HK" ? "已用預算" : "Budget Used")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int((budgetUsedRatio * 100).rounded()))%")
                                    .font(.caption.bold())
                                    .foregroundStyle(isOverBudget ? .red : (isAheadOfTime ? .orange : .blue))
                            }
                            ProgressView(value: min(1.0, budgetUsedRatio))
                                .tint(isOverBudget ? .red : (isAheadOfTime ? .orange : .blue))
                        }
                        
                        // Bar 2: Month Time Passed
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(appLanguage == "zh-HK" ? "本月時間進度" : "Month Passed")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(
                                    appLanguage == "zh-HK"
                                    ? "第 \(currentDayOfMonth) / \(daysInMonth) 日 (\(Int((monthProgress * 100).rounded()))%)"
                                    : "Day \(currentDayOfMonth) of \(daysInMonth) (\(Int((monthProgress * 100).rounded()))%)"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            ProgressView(value: min(1.0, monthProgress))
                                .tint(.secondary.opacity(0.5))
                        }
                    }
                    .padding(.vertical, 2)
                    
                    // Plain-Language Actionable Advice Banner
                    HStack(spacing: 10) {
                        Image(systemName: isOverBudget ? "exclamationmark.triangle.fill" : "sparkles")
                            .font(.subheadline)
                            .foregroundStyle(isOverBudget ? .red : .blue)
                        
                        if isOverBudget {
                            Text(
                                appLanguage == "zh-HK"
                                ? "本月已超出預算 \(AppFormatters.formatCurrency(overBudgetAmount, currency: currency))。距離月底還有 \(remainingDays) 日，建議暫停非必要消費。"
                                : "You're \(AppFormatters.formatCurrency(overBudgetAmount, currency: currency)) over budget with \(remainingDays) days left. Try to pause non-essential spending."
                            )
                            .font(.caption)
                            .foregroundStyle(.primary)
                        } else {
                            Text(
                                appLanguage == "zh-HK"
                                ? "未來 \(remainingDays) 日，你每日可安心消費最多 \(AppFormatters.formatCurrency(safeDailyAllowance, currency: currency, fractionDigits: 0))。"
                                : "You can safely spend \(AppFormatters.formatCurrency(safeDailyAllowance, currency: currency, fractionDigits: 0)) / day for the remaining \(remainingDays) days."
                            )
                            .font(.caption)
                            .foregroundStyle(.primary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            
            // MARK: - 2. Easy Daily Spending Chart (With Toggle for Cumulative View)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if let selDay = selectedDay,
                           let item = dailyPacingData.first(where: { $0.day == selDay }) {
                            Text(
                                showCumulativeChart
                                ? (appLanguage == "zh-HK" ? "本月 \(selDay) 日累積支出" : "Day \(selDay) Cumulative Spend")
                                : (appLanguage == "zh-HK" ? "本月 \(selDay) 日當日支出" : "Day \(selDay) Spending")
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            
                            Text(
                                AppFormatters.formatCurrency(
                                    showCumulativeChart ? (item.actualCumulative ?? 0) : item.dailySpend,
                                    currency: currency
                                )
                            )
                            .font(.headline.bold())
                            .foregroundStyle(.blue)
                        } else {
                            Text(
                                showCumulativeChart
                                ? (appLanguage == "zh-HK" ? "累積開支趨勢" : "Cumulative Spend Trend")
                                : (appLanguage == "zh-HK" ? "每日消費明細" : "Daily Spending Breakdown")
                            )
                            .font(.headline)
                            .lineLimit(1)
                            
                            if budget > 0 && !showCumulativeChart {
                                Text(
                                    appLanguage == "zh-HK"
                                    ? "虛線 = 每日建議限額 (\(AppFormatters.formatCurrency(dailyTarget, currency: currency, fractionDigits: 0))/日)"
                                    : "Dashed line = Daily target (\(AppFormatters.formatCurrency(dailyTarget, currency: currency, fractionDigits: 0))/day)"
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Simple segmented toggle between Daily Bars (default) and Cumulative Line
                    Picker("Chart Mode", selection: $showCumulativeChart) {
                        Text(appLanguage == "zh-HK" ? "每日" : "Daily").tag(false)
                        Text(appLanguage == "zh-HK" ? "累積" : "Total").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 125)
                }
                
                if !showCumulativeChart {
                    // EASY MODE (DEFAULT): Daily Spending Bars + Daily Target Line
                    let maxDaily = max(biggestDay.amount * 1.15, dailyTarget * 2.0, 100.0)
                    Chart {
                        ForEach(dailyPacingData.filter { $0.day <= currentDayOfMonth }) { item in
                            BarMark(
                                x: .value("Day", item.day),
                                y: .value("Spend", item.dailySpend)
                            )
                            .foregroundStyle(
                                selectedDay == item.day
                                ? Color.indigo.gradient
                                : (budget > 0 && item.dailySpend > dailyTarget * 1.5
                                    ? Color.orange.gradient
                                    : Color.blue.gradient)
                            )
                            .cornerRadius(4)
                        }
                        
                        if budget > 0 {
                            RuleMark(y: .value("Daily Target", dailyTarget))
                                .foregroundStyle(Color.green)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        }
                    }
                    .frame(height: 200)
                    .chartXScale(domain: 1...max(1, daysInMonth))
                    .chartYScale(domain: 0...maxDaily)
                    .chartOverlay { proxy in
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            let originX = proxy.plotFrame.map { geo[$0].origin.x } ?? 0
                                            let xPos = value.location.x - originX
                                            if let d: Int = proxy.value(atX: xPos) {
                                                let clamped = min(max(1, d), currentDayOfMonth)
                                                if selectedDay != clamped {
                                                    selectedDay = clamped
                                                }
                                            }
                                        }
                                        .onEnded { _ in
                                            selectedDay = nil
                                        }
                                )
                        }
                    }
                } else {
                    // CUMULATIVE MODE: Clean Two-Line Chart
                    let yMax = max(budget * 1.15, totalSpentSoFar * 1.15, 100.0)
                    let actualPoints = dailyPacingData.compactMap { item -> (day: Int, actual: Double)? in
                        guard let act = item.actualCumulative else { return nil }
                        return (item.day, act)
                    }
                    let lineColor: Color = isOverBudget ? .red : (isAheadOfTime ? .orange : .blue)
                    
                    Chart {
                        if budget > 0 {
                            ForEach(dailyPacingData) { item in
                                LineMark(
                                    x: .value("Day", item.day),
                                    y: .value("Amount", item.budgetPace),
                                    series: .value("Series", "BudgetPace")
                                )
                                .foregroundStyle(Color.secondary.opacity(0.45))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            }
                            
                            RuleMark(y: .value("Budget", budget))
                                .foregroundStyle(Color.red.opacity(0.6))
                                .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
                        }
                        
                        ForEach(actualPoints, id: \.day) { pt in
                            AreaMark(
                                x: .value("Day", pt.day),
                                yStart: .value("Baseline", 0),
                                yEnd: .value("Amount", pt.actual)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [lineColor.opacity(0.25), lineColor.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            
                            LineMark(
                                x: .value("Day", pt.day),
                                y: .value("Amount", pt.actual),
                                series: .value("Series", "ActualSpend")
                            )
                            .foregroundStyle(lineColor)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        }
                        
                        if let latest = actualPoints.last {
                            PointMark(
                                x: .value("Day", latest.day),
                                y: .value("Amount", latest.actual)
                            )
                            .symbolSize(140)
                            .foregroundStyle(lineColor.opacity(0.22))
                            
                            PointMark(
                                x: .value("Day", latest.day),
                                y: .value("Amount", latest.actual)
                            )
                            .symbolSize(45)
                            .foregroundStyle(lineColor)
                        }
                    }
                    .frame(height: 200)
                    .chartXScale(domain: 1...max(1, daysInMonth))
                    .chartYScale(domain: 0...yMax)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            
            // MARK: - 3. Four Everyday Summary Cards
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    // Card 1: Safe Daily Allowance (or Over Budget)
                    fileprivatePacingCard(
                        title: isOverBudget
                            ? (appLanguage == "zh-HK" ? "超出預算" : "Over Budget By")
                            : (appLanguage == "zh-HK" ? "每日可用限額" : "Safe to Spend / Day"),
                        value: AppFormatters.formatCurrency(
                            isOverBudget ? overBudgetAmount : safeDailyAllowance,
                            currency: currency,
                            fractionDigits: 0
                        ),
                        subtitle: isOverBudget
                            ? (appLanguage == "zh-HK" ? "剩餘 \(remainingDays) 日建議節流" : "\(remainingDays) days left in month")
                            : (appLanguage == "zh-HK" ? "未來 \(remainingDays) 日每日建議" : "For the next \(remainingDays) days"),
                        icon: isOverBudget ? "exclamationmark.triangle.fill" : "hand.thumbsup.fill",
                        color: isOverBudget ? .red : .green
                    )
                    
                    // Card 2: Daily Average So Far
                    let currentDailyAvg = totalSpentSoFar / Double(max(1, currentDayOfMonth))
                    fileprivatePacingCard(
                        title: L10n.tr("Daily Average", lang: appLanguage),
                        value: AppFormatters.formatCurrency(currentDailyAvg, currency: currency, fractionDigits: 0),
                        subtitle: budget > 0
                            ? (appLanguage == "zh-HK"
                                ? "目標: \(AppFormatters.formatCurrency(dailyTarget, currency: currency, fractionDigits: 0)) / 日"
                                : "Target: \(AppFormatters.formatCurrency(dailyTarget, currency: currency, fractionDigits: 0)) / day")
                            : "\(currentDayOfMonth) days logged",
                        icon: "calendar.day.timeline.leading",
                        color: .blue
                    )
                }
                
                HStack(spacing: 12) {
                    // Card 3: Zero-Spend Days (Positive reinforcement!)
                    fileprivatePacingCard(
                        title: appLanguage == "zh-HK" ? "零消費日數" : "No-Spend Days",
                        value: appLanguage == "zh-HK" ? "\(noSpendDaysCount) 日" : "\(noSpendDaysCount) Days",
                        subtitle: appLanguage == "zh-HK"
                            ? "過去 \(currentDayOfMonth) 日內完全無消費"
                            : "Out of \(currentDayOfMonth) days so far",
                        icon: "leaf.fill",
                        color: .teal
                    )
                    
                    // Card 4: Biggest Spend Day
                    fileprivatePacingCard(
                        title: appLanguage == "zh-HK" ? "最高消費日" : "Biggest Spend Day",
                        value: AppFormatters.formatCurrency(biggestDay.amount, currency: currency, fractionDigits: 0),
                        subtitle: biggestDay.amount > 0
                            ? (appLanguage == "zh-HK" ? "本月 \(biggestDay.day) 日" : "Day \(biggestDay.day) of this month")
                            : "-",
                        icon: "flame.fill",
                        color: .orange
                    )
                }
            }
            .padding(.horizontal)
        }
        .task(id: calculationKey) {
            await computeMetrics()
        }
    }
    
    @ViewBuilder
    private func fileprivatePacingCard(
        title: String,
        value: String,
        subtitle: String,
        icon: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
            }
            
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
