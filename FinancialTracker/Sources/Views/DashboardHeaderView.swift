//
//  DashboardHeaderView.swift
//  Worthly
//

import Foundation
import SwiftUI
import Charts

// MARK: - Dashboard Header (Net Worth Hero Card + Monthly Budget Pacing Card)
public struct DashboardHeaderView: View {
    public let netWorth: Double
    public let totalAssets: Double
    public let totalLiabilities: Double
    public let totalSpentThisMonth: Double
    public let monthlyBudget: Double
    public let remainingBudget: Double
    public let budgetProgress: Double
    public let monthlyTrendData: [TrendPoint]
    public let defaultCurrency: String
    public let appLanguage: String
    @Binding public var isPrivacyMode: Bool
    @Binding public var showingAccountsManager: Bool
    @Binding public var selectedTrendDay: Int?

    public init(
        netWorth: Double,
        totalAssets: Double,
        totalLiabilities: Double,
        totalSpentThisMonth: Double,
        monthlyBudget: Double,
        remainingBudget: Double,
        budgetProgress: Double,
        monthlyTrendData: [TrendPoint],
        defaultCurrency: String,
        appLanguage: String,
        isPrivacyMode: Binding<Bool>,
        showingAccountsManager: Binding<Bool>,
        selectedTrendDay: Binding<Int?>
    ) {
        self.netWorth = netWorth
        self.totalAssets = totalAssets
        self.totalLiabilities = totalLiabilities
        self.totalSpentThisMonth = totalSpentThisMonth
        self.monthlyBudget = monthlyBudget
        self.remainingBudget = remainingBudget
        self.budgetProgress = budgetProgress
        self.monthlyTrendData = monthlyTrendData
        self.defaultCurrency = defaultCurrency
        self.appLanguage = appLanguage
        self._isPrivacyMode = isPrivacyMode
        self._showingAccountsManager = showingAccountsManager
        self._selectedTrendDay = selectedTrendDay
    }

    public var body: some View {
        VStack(spacing: 20) {
            netWorthHeroCard
            budgetHeroCard
        }
    }

    // MARK: - 1. Net Worth Hero Card
    @ViewBuilder
    private var netWorthHeroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "banknote.fill")
                        .font(.caption)
                    Text(L10n.tr("Net Worth", lang: appLanguage))
                        .font(.subheadline.bold())
                }
                .foregroundStyle(.white.opacity(0.85))
                
                Spacer()
                
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isPrivacyMode.toggle()
                    }
                } label: {
                    Image(systemName: isPrivacyMode ? "eye.slash.fill" : "eye.fill")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(6)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            
            if isPrivacyMode {
                Text("\(defaultCurrency) ••••••")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } else {
                Text(String(netWorth.formattedCurrency(defaultCurrency)))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text(isPrivacyMode ? "••••" : String(totalAssets.formattedCurrency(defaultCurrency)))
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    Circle().fill(Color.orange).frame(width: 8, height: 8)
                    Text(isPrivacyMode ? "••••" : String(totalLiabilities.formattedCurrency(defaultCurrency)))
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Button {
                    showingAccountsManager = true
                } label: {
                    HStack(spacing: 4) {
                        Text(L10n.tr("Accounts", lang: appLanguage))
                            .font(.caption2.bold())
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.2))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color(hex: "#1E1B4B"), Color(hex: "#2563EB")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.blue.opacity(0.2), radius: 8, x: 0, y: 4)
    }

    // MARK: - 2. Budget Hero Card
    @ViewBuilder
    private var budgetHeroCard: some View {
        let calendar = Calendar.current
        let now = Date()
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let currentDay = max(1, calendar.component(.day, from: now))
        let dailyBudgetPace = monthlyBudget > 0 ? (monthlyBudget / Double(daysInMonth)) : 0.0
        let idealSpendToday = dailyBudgetPace * Double(currentDay)
        let paceDelta = idealSpendToday - totalSpentThisMonth
        let isUnderPace = paceDelta >= 0
        let yMax = max(monthlyBudget * 1.05, totalSpentThisMonth * 1.15, 100.0)
        
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("Monthly Spending", lang: appLanguage))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    Text(isPrivacyMode ? "\(defaultCurrency) ••••" : totalSpentThisMonth.formattedCurrency(defaultCurrency))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Spacer()
                
                CircularProgressView(progress: budgetProgress)
                    .frame(width: 58, height: 58)
            }
            
            ProgressView(value: budgetProgress)
                .tint(budgetProgress > 0.9 ? .red : (budgetProgress > 0.75 ? .orange : .blue))
            
            HStack {
                Text("\(L10n.tr("Budget", lang: appLanguage)): \(defaultCurrency) \(monthlyBudget.financialIntegerFormatted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                Text("\(remainingBudget.formattedCurrency(defaultCurrency)) \(L10n.tr("remaining", lang: appLanguage))")
                    .font(.caption)
                    .foregroundStyle(budgetProgress > 0.9 ? .red : .green)
                    .lineLimit(1)
            }
            
            if monthlyTrendData.isEmpty || (totalSpentThisMonth == 0 && monthlyBudget <= 0) {
                HStack {
                    Spacer()
                    Text(L10n.tr("No expenses logged this month", lang: appLanguage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 30)
                        .lineLimit(1)
                    Spacer()
                }
            } else {
                HStack(spacing: 6) {
                    if let selectedDay = selectedTrendDay,
                       let point = monthlyTrendData.first(where: { $0.day == selectedDay }) {
                        let targetForDay = dailyBudgetPace * Double(selectedDay)
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        Text("Day \(selectedDay): \(point.amount.formattedCurrency(defaultCurrency))")
                            .font(.caption2.bold())
                            .foregroundStyle(.primary)
                        Spacer()
                        if monthlyBudget > 0 {
                            Text("Pace: \(targetForDay.formattedCurrency(defaultCurrency))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Circle()
                            .fill(isUnderPace ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(
                            isUnderPace
                            ? (appLanguage == "zh-HK"
                                ? "進度良好 • 比預算進度少 \(abs(paceDelta).formattedCurrency(defaultCurrency))"
                                : "On Track • \(abs(paceDelta).formattedCurrency(defaultCurrency)) under pace")
                            : (appLanguage == "zh-HK"
                                ? "注意進度 • 比預算進度多 \(abs(paceDelta).formattedCurrency(defaultCurrency))"
                                : "Pacing High • \(abs(paceDelta).formattedCurrency(defaultCurrency)) over pace")
                        )
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isUnderPace ? .green : .orange)
                        .lineLimit(1)
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.secondary.opacity(0.5))
                                .frame(width: 10, height: 2)
                            Text(appLanguage == "zh-HK" ? "理想進度" : "Budget Pace")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 2)
                
                let lineColor: Color = budgetProgress > 0.9 ? .red : (isUnderPace ? .blue : .orange)
                
                Chart {
                    if monthlyBudget > 0 {
                        LineMark(
                            x: .value("Day", 1),
                            y: .value("Ideal Pace", dailyBudgetPace),
                            series: .value("Series", "BudgetPace")
                        )
                        .foregroundStyle(Color.secondary.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        
                        LineMark(
                            x: .value("Day", daysInMonth),
                            y: .value("Ideal Pace", monthlyBudget),
                            series: .value("Series", "BudgetPace")
                        )
                        .foregroundStyle(Color.secondary.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    }
                    
                    ForEach(monthlyTrendData) { pt in
                        AreaMark(
                            x: .value("Day", pt.day),
                            yStart: .value("Baseline", 0),
                            yEnd: .value("Spend", pt.amount)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [lineColor.opacity(0.30), lineColor.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.linear)
                        
                        LineMark(
                            x: .value("Day", pt.day),
                            y: .value("Spend", pt.amount),
                            series: .value("Series", "ActualSpend")
                        )
                        .foregroundStyle(lineColor)
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    }
                    
                    if let activeDay = selectedTrendDay,
                       let activePoint = monthlyTrendData.first(where: { $0.day == activeDay }) {
                        RuleMark(x: .value("Selected Day", activeDay))
                            .foregroundStyle(lineColor.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        
                        PointMark(
                            x: .value("Day", activePoint.day),
                            y: .value("Spend", activePoint.amount)
                        )
                        .symbolSize(65)
                        .foregroundStyle(lineColor)
                    } else if let latestPoint = monthlyTrendData.last {
                        PointMark(
                            x: .value("Day", latestPoint.day),
                            y: .value("Spend", latestPoint.amount)
                        )
                        .symbolSize(150)
                        .foregroundStyle(lineColor.opacity(0.22))
                        
                        PointMark(
                            x: .value("Day", latestPoint.day),
                            y: .value("Spend", latestPoint.amount)
                        )
                        .symbolSize(45)
                        .foregroundStyle(lineColor)
                    }
                }
                .chartXScale(domain: 1...daysInMonth)
                .chartYScale(domain: 0...yMax)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [0, monthlyBudget / 2.0, monthlyBudget]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                            .foregroundStyle(.secondary.opacity(0.2))
                        if let amount = value.as(Double.self), monthlyBudget > 0 {
                            AxisValueLabel {
                                Text(amount >= 1000 ? String(format: "%.0fk", amount / 1000.0) : String(format: "%.0f", amount))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: [1, 8, 15, 22, daysInMonth]) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                        AxisTick().foregroundStyle(.secondary.opacity(0.3))
                        if let day = value.as(Int.self) {
                            AxisValueLabel {
                                Text("\(day)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let plotOriginX = proxy.plotFrame.map { geo[$0].origin.x } ?? 0
                                        let xPos = value.location.x - plotOriginX
                                        if let day: Int = proxy.value(atX: xPos) {
                                            let clamped = min(max(1, day), currentDay)
                                            if selectedTrendDay != clamped {
                                                selectedTrendDay = clamped
                                            }
                                        }
                                    }
                                    .onEnded { _ in
                                        selectedTrendDay = nil
                                    }
                            )
                    }
                }
                .frame(height: 105)
                .padding(.top, 2)
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
    }
}
