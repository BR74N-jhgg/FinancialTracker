import Foundation
import SwiftUI
import SwiftData
import Charts


// MARK: - Customizable Quick Action Item Model
public struct QuickActionItem: Identifiable, Codable, Equatable {
    public var id: String
    public var title: String
    public var icon: String
    public var colorHex: String
    public var defaultMerchant: String
    public var defaultCategoryName: String
    public var defaultPaymentMethodName: String
    public var defaultAmount: Double?
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        icon: String = "plus.circle.fill",
        colorHex: String = "#007AFF",
        defaultMerchant: String = "",
        defaultCategoryName: String = "",
        defaultPaymentMethodName: String = "",
        defaultAmount: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.colorHex = colorHex
        self.defaultMerchant = defaultMerchant
        self.defaultCategoryName = defaultCategoryName
        self.defaultPaymentMethodName = defaultPaymentMethodName
        self.defaultAmount = defaultAmount
    }
    
    public static let defaultItems: [QuickActionItem] = [
        QuickActionItem(id: "1", title: "Add Expense", icon: "plus.circle.fill", colorHex: "#007AFF", defaultMerchant: "", defaultCategoryName: "", defaultPaymentMethodName: "Apple Pay"),
        QuickActionItem(id: "2", title: "Octopus MTR", icon: "wave.3.forward.circle.fill", colorHex: "#FF9500", defaultMerchant: "MTR", defaultCategoryName: "Transport", defaultPaymentMethodName: "Octopus"),
        QuickActionItem(id: "3", title: "Coffee/Meal", icon: "cup.and.saucer.fill", colorHex: "#34C759", defaultMerchant: "Starbucks", defaultCategoryName: "Dining", defaultPaymentMethodName: "Apple Pay"),
        QuickActionItem(id: "4", title: "Energy / Utility", icon: "bolt.fill", colorHex: "#5856D6", defaultMerchant: "CLP Power", defaultCategoryName: "Bills & Utilities", defaultPaymentMethodName: "FPS"),
        QuickActionItem(id: "5", title: "Groceries", icon: "cart.fill", colorHex: "#AF52DE", defaultMerchant: "Wellcome", defaultCategoryName: "Groceries", defaultPaymentMethodName: "Credit Card")
    ]
}

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

public struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    
    @Query(sort: \TransactionItem.timestamp, order: .reverse) private var transactions: [TransactionItem]
    @Query(sort: \PaymentMethodItem.name) private var allAccounts: [PaymentMethodItem]
    
    @AppStorage("monthly_budget") private var monthlyBudget: Double = 15000.0
    @AppStorage("default_currency") private var defaultCurrency: String = "HKD"
    @AppStorage("app_language") private var appLanguage: String = "en"
    @AppStorage("dashboard_active_snapshot") private var activeSnapshot: String = "dayOfWeek"
    @AppStorage("custom_quick_actions_json") private var quickActionsJson: String = ""
    @AppStorage("is_privacy_mode") private var isPrivacyMode: Bool = false
    
    @State private var showingAddExpense = false
    @State private var selectedItemToEdit: TransactionItem? = nil
    @State private var activeQuickAction: QuickActionItem? = nil
    @State private var selectedTrendDay: Int? = nil
    @State private var showingCustomizeShortcuts = false
    @State private var showingAccountsManager: Bool = false
    
    @State private var totalSpentThisMonth: Double = 0.0
    @State private var monthlyTrendData: [TrendPoint] = []
    @State private var cachedDayOfWeek: [DashboardDayItem] = []
    @State private var cachedCashFlow: [DashboardFlowBar] = []
    @State private var cachedCategories: [DashboardCatShare] = []
    @State private var cachedPaymentMethods: [DashboardMethodItem] = []
    @State private var cachedTopMerchants: [DashboardMerchantItem] = []
    
    // Deduplicates metric calculations and automatically cancels stale tasks
        private var dashboardCalculationKey: Int {
            var hasher = Hasher()
            hasher.combine(transactions.count)
            hasher.combine(monthlyBudget)
            hasher.combine(appLanguage)
            if let first = transactions.first {
                hasher.combine(first.timestamp)
                hasher.combine(first.amount)
            }
            return hasher.finalize()
        }
    
    private var onNavigateToAnalytics: (() -> Void)? = nil

    public init(onNavigateToAnalytics: (() -> Void)? = nil) {
        self.onNavigateToAnalytics = onNavigateToAnalytics
    }
    
    private var totalAssets: Double {
        allAccounts.filter { $0.isAsset }.reduce(0.0) { $0 + $1.currentBalance }
    }
    
    private var totalLiabilities: Double {
        allAccounts.filter { $0.isLiability }.reduce(0.0) { $0 + abs($1.currentBalance) }
    }
    
    private var netWorth: Double {
        totalAssets - totalLiabilities
    }
    
    private var quickActions: [QuickActionItem] {
        if let data = quickActionsJson.data(using: .utf8),
           let items = try? AppSerializationManager.shared.jsonDecoder.decode([QuickActionItem].self, from: data),
           !items.isEmpty {
            return items
        }
        return QuickActionItem.defaultItems
    }

    
    private var remainingBudget: Double {
        max(0.0, monthlyBudget - totalSpentThisMonth)
    }
    
    private var budgetProgress: Double {
        guard monthlyBudget > 0 else { return 0.0 }
        return min(totalSpentThisMonth / monthlyBudget, 1.0)
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    netWorthHeroCard
                    budgetHeroCard
                    interactiveSnapshotsSection
                    customQuickActionsSection
                    recentTransactionsSection
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .appPullToRefresh {
                            recomputeMetrics()
                        }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L10n.tr("Dashboard", lang: appLanguage))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddExpense = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Color.blue)
                            .clipShape(Circle())
                    }
                }
            }
            .sheet(isPresented: $showingAddExpense) {
                AddTransactionView()
            }
            .sheet(item: $selectedItemToEdit) { item in
                EditTransactionView(item: item)
            }
            .sheet(item: $activeQuickAction) { action in
                AddTransactionView(
                    presetMerchant: action.defaultMerchant,
                    presetCategoryName: action.defaultCategoryName,
                    presetPaymentMethodName: action.defaultPaymentMethodName,
                    presetAmount: action.defaultAmount
                )
            }
            .sheet(isPresented: $showingCustomizeShortcuts) {
                CustomizeQuickActionsView(
                    quickActionsJson: $quickActionsJson,
                    currentActions: quickActions,
                    lang: appLanguage
                )
            }
            .sheet(isPresented: $showingAccountsManager) {
                PaymentMethodManagementView()
            }
            .onAppear {
                recomputeMetrics()
            }
            .task(id: dashboardCalculationKey) {
                recomputeMetrics()
            }
            .onChange(of: transactions.count) { _, _ in
                recomputeMetrics()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    recomputeMetrics()
                }
            }
        }
    }

    // MARK: - Instant Synchronous Metrics Calculation (Loads on Frame 1 like Net Worth)
    private func recomputeMetrics() {
        let calendar = Calendar.current
        let now = Date()
        let currentDay = max(1, calendar.component(.day, from: now))
        let lang = appLanguage
        let incomeLabel = L10n.tr("Income", lang: lang)
        let expenseLabel = L10n.tr("Expense", lang: lang)
        let weekdayNames = L10n.weekdayNames(lang: lang)

        let activeTransactions = transactions.filter { !$0.isDeleted }
        let expenses = activeTransactions.filter { $0.type == .expense }
        let thisMonthExpenses = expenses.filter {
            calendar.isDate($0.timestamp, equalTo: now, toGranularity: .month) && !$0.isExcludedFromBudget
        }
        let spent = thisMonthExpenses.reduce(0.0) { $0 + $1.amount }

        // 1. Monthly Trend Pacing (Day 1 through Today)
        var dailyTotals = [Int: Double]()
        for t in thisMonthExpenses {
            let day = calendar.component(.day, from: t.timestamp)
            dailyTotals[day, default: 0.0] += t.amount
        }
        var cumulative: Double = 0.0
        var calculatedPoints: [TrendPoint] = []
        for d in 1...currentDay {
            cumulative += dailyTotals[d] ?? 0.0
            calculatedPoints.append(TrendPoint(day: d, amount: cumulative))
        }

        // 2. Day of Week
        var weekTotals = [Int: Double]()
        for i in 1...7 { weekTotals[i] = 0.0 }
        for t in expenses {
            let w = calendar.component(.weekday, from: t.timestamp)
            weekTotals[w, default: 0.0] += t.amount
        }
        let order = [2, 3, 4, 5, 6, 7, 1]
        let dayOfWeek = order.map {
            DashboardDayItem(day: $0, name: weekdayNames[$0 - 1], total: weekTotals[$0] ?? 0.0)
        }

        // 3. Cash Flow
        let totalIncome = activeTransactions.filter { $0.type == .income }.reduce(0.0) { $0 + $1.amount }
        let cashFlow = [
            DashboardFlowBar(label: incomeLabel, amount: totalIncome, isIncome: true),
            DashboardFlowBar(label: expenseLabel, amount: spent, isIncome: false)
        ]

        // 4. Categories
        var catTotals = [String: Double]()
        var catColors = [String: String]()
        for t in expenses {
            let catName = t.category?.name ?? "Other"
            let catColor = t.category?.colorHex ?? "#007AFF"
            catTotals[catName, default: 0.0] += t.amount
            if catColors[catName] == nil { catColors[catName] = catColor }
        }
        let categories = catTotals.map { name, total in
            DashboardCatShare(name: name, colorHex: catColors[name] ?? "#007AFF", total: total)
        }.sorted { $0.total > $1.total }.prefix(4).map { $0 }

        // 5. Payment Methods
        var methodTotals = [String: Double]()
        var methodColors = [String: String]()
        for t in expenses {
            let pmName = t.paymentMethod?.name ?? "Other"
            let pmColor = t.paymentMethod?.colorHex ?? "#007AFF"
            methodTotals[pmName, default: 0.0] += t.amount
            if methodColors[pmName] == nil { methodColors[pmName] = pmColor }
        }
        let paymentMethods = methodTotals.map { name, total in
            DashboardMethodItem(name: name, colorHex: methodColors[name] ?? "#007AFF", total: total)
        }.sorted { $0.total > $1.total }.prefix(3).map { $0 }

        // 6. Top Merchants
        var merchantTotals = [String: Double]()
        for t in expenses {
            let merch = t.merchant.isEmpty ? "General" : t.merchant
            merchantTotals[merch, default: 0.0] += t.amount
        }
        let topMerchants = merchantTotals.map { name, total in
            DashboardMerchantItem(name: name, total: total)
        }.sorted { $0.total > $1.total }.prefix(4).map { $0 }

        // Update state synchronously on MainActor so Frame 1 is never blank
        self.totalSpentThisMonth = spent
        self.monthlyTrendData = calculatedPoints
        self.cachedDayOfWeek = dayOfWeek
        self.cachedCashFlow = cashFlow
        self.cachedCategories = categories
        self.cachedPaymentMethods = paymentMethods
        self.cachedTopMerchants = topMerchants

        WidgetSyncManager.shared.syncWidget(context: modelContext)
    }


    // MARK: - 0. Net Worth Hero Card
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
/*                    Text(L10n.tr("Assets", lang: appLanguage))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                    */
                    Text(isPrivacyMode ? "••••" : String(totalAssets.formattedCurrency(defaultCurrency)))
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    Circle().fill(Color.orange).frame(width: 8, height: 8)
/*                    Text(L10n.tr("Liabilities", lang: appLanguage))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
 */
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

    // MARK: - 1. Budget Hero Card
    @ViewBuilder
    private var budgetHeroCard: some View {
        // MARK: - Upgraded Apple-Style Monthly Pacing Trend Line
            VStack(alignment: .leading, spacing: 6) {
                // Interactive inspection readout
                HStack {
                    if let selectedDay = selectedTrendDay,
                       let point = monthlyTrendData.first(where: { $0.day == selectedDay }) {
                        Text(String(format: "Day %d: %@", selectedDay, point.amount.formattedCurrency(defaultCurrency)))
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                    } else {
                        Text(L10n.tr("Spending Trajectory", lang: appLanguage))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    let daysInMonth = Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30
                    let today = Calendar.current.component(.day, from: Date())
                    Text("\(today) / \(daysInMonth) days")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Chart {
                    let daysInMonth = Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30
                    let dailyBudgetPace = monthlyBudget > 0 ? (monthlyBudget / Double(daysInMonth)) : 0.0

                    // 1. Ideal Budget Pace Reference Line (Dashed)
                    if monthlyBudget > 0 {
                        LineMark(
                            x: .value("Day", 1),
                            y: .value("Budget Pace", dailyBudgetPace)
                        )
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .foregroundStyle(Color.secondary.opacity(0.35))

                        LineMark(
                            x: .value("Day", daysInMonth),
                            y: .value("Budget Pace", monthlyBudget)
                        )
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                    }

                    // 2. Actual Spend Curve & Gradient Area
                    ForEach(monthlyTrendData) { pt in
                        AreaMark(
                            x: .value("Day", pt.day),
                            y: .value("Spend", pt.amount)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    (pt.amount > (dailyBudgetPace * Double(pt.day)) && monthlyBudget > 0 ? Color.orange : Color.blue).opacity(0.25),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("Day", pt.day),
                            y: .value("Spend", pt.amount)
                        )
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .foregroundStyle(pt.amount > (dailyBudgetPace * Double(pt.day)) && monthlyBudget > 0 ? Color.orange : Color.blue)
                        .interpolationMethod(.monotone)
                    }

                    // 3. Touch Selection RuleMark
                    if let selectedDay = selectedTrendDay,
                       let point = monthlyTrendData.first(where: { $0.day == selectedDay }) {
                        RuleMark(x: .value("Selected Day", selectedDay))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                            .foregroundStyle(Color.primary.opacity(0.6))

                        PointMark(
                            x: .value("Selected Day", selectedDay),
                            y: .value("Spend", point.amount)
                        )
                        .symbolSize(45)
                        .foregroundStyle(Color.blue)
                    }
                }
                .chartXScale(domain: 1...(Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30))
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: [1, 7, 14, 21, 28]) { val in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                        AxisTick().foregroundStyle(.secondary.opacity(0.3))
                        AxisValueLabel {
                            if let intVal = val.as(Int.self) {
                                Text("\(intVal)")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartXSelection(value: $selectedTrendDay)
                .frame(height: 105)
                .padding(.top, 4)
            }
        
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
    }

    // MARK: - 2. Interactive Snapshot Selector
    @ViewBuilder
    private var interactiveSnapshotsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.tr("Financial Breakdown", lang: appLanguage))
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    snapshotPill(title: L10n.tr("Day of Week", lang: appLanguage), key: "dayOfWeek", icon: "calendar")
                    snapshotPill(title: L10n.tr("Categories", lang: appLanguage), key: "categories", icon: "chart.pie.fill")
                    snapshotPill(title: L10n.tr("Cash Flow", lang: appLanguage), key: "cashFlow", icon: "arrow.left.arrow.right")
                    snapshotPill(title: L10n.tr("Payment Share", lang: appLanguage), key: "paymentMethods", icon: "creditcard.fill")
                    snapshotPill(title: L10n.tr("Top Merchants", lang: appLanguage), key: "topMerchants", icon: "building.2.fill")
                }
                .padding(.vertical, 2)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                switch activeSnapshot {
                case "categories":
                    MiniCategorySnapshot(data: cachedCategories, currency: defaultCurrency)
                case "cashFlow":
                    MiniCashFlowSnapshot(data: cachedCashFlow)
                case "paymentMethods":
                    MiniPaymentMethodSnapshot(data: cachedPaymentMethods)
                case "topMerchants":
                    MiniTopMerchantsSnapshot(data: cachedTopMerchants)
                default:
                    MiniDayOfWeekSnapshot(data: cachedDayOfWeek)
                }
                
                Divider()
                    .padding(.top, 6)
                
                Button {
                    onNavigateToAnalytics?()
                } label: {
                    HStack {
                        Text(L10n.tr("View Full Analytics", lang: appLanguage))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundStyle(.blue)
                    .padding(.top, 4)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
        }
    }

    private func snapshotPill(title: String, key: String, icon: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                activeSnapshot = key
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(activeSnapshot == key ? Color.blue : Color(.tertiarySystemFill))
            .foregroundStyle(activeSnapshot == key ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 3. Customizable Quick Actions Section
    @ViewBuilder
    private var customQuickActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.tr("Quick Actions", lang: appLanguage))
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    showingCustomizeShortcuts = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.caption2)
                        Text(L10n.tr("Customize", lang: appLanguage))
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemFill))
                    .foregroundStyle(.primary)
                    .clipShape(Capsule())
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(quickActions) { action in
                        Button {
                            activeQuickAction = action
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: action.icon)
                                    .font(.title2)
                                    .foregroundStyle(Color(hex: action.colorHex))
                                Text(action.title)
                                    .font(.caption.bold())
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .frame(width: 96, height: 74)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - 4. Recent Transactions List
    @ViewBuilder
    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.tr("Recent Transactions", lang: appLanguage))
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            
            if transactions.isEmpty {
                VStack(spacing: 8) {
                    Text(L10n.tr("No transactions recorded yet.", lang: appLanguage))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 0) {
                    ForEach(transactions.prefix(6)) { item in
                        Button {
                            selectedItemToEdit = item
                        } label: {
                            HStack(spacing: 12) {
                                let icon = item.type == .transfer ? "arrow.left.arrow.right" : (item.category?.iconName ?? "tag.fill")
                                let iconColor = item.type == .transfer ? Color.orange : Color(hex: item.category?.colorHex ?? "#007AFF")
                                
                                Image(systemName: icon)
                                    .font(.body)
                                    .foregroundStyle(iconColor)
                                    .frame(width: 36, height: 36)
                                    .background(iconColor.opacity(0.12))
                                    .clipShape(Circle())
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(item.merchant.isEmpty ? (item.category?.name ?? "Other") : item.merchant)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        
                                        if item.isExcludedFromBudget {
                                            Text(L10n.tr("Reimbursable", lang: appLanguage))
                                                .font(.system(size: 9, weight: .bold))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Color.purple.opacity(0.15))
                                                .foregroundStyle(Color.purple)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    
                                    HStack(spacing: 4) {
                                        Text(item.timestamp.formatted(date: .abbreviated, time: .omitted))
                                        if let method = item.paymentMethod {
                                            Text("• \(method.name)")
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                if item.type == .transfer {
                                    Text(String(format: "%@ %.2f", defaultCurrency, item.amount))
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(Color.orange)
                                        .lineLimit(1)
                                } else {
                                    Text(String(format: "%@%@ %.2f", item.type == .income ? "+" : "-", defaultCurrency, item.amount))
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(item.type == .income ? .green : .primary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                        }
                        .buttonStyle(.plain)
                        
                        if item.id != transactions.prefix(6).last?.id {
                            Divider()
                                .padding(.leading, 62)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
            }
        }
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
struct CircularProgressView: View {
    let progress: Double
    
    var body: some View {
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

// MARK: - Customize Quick Actions Sheet
public struct CustomizeQuickActionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var quickActionsJson: String
    let lang: String

    @State private var items: [QuickActionItem] = []
    @State private var editingItem: QuickActionItem? = nil

    public init(quickActionsJson: Binding<String>, currentActions: [QuickActionItem], lang: String) {
        self._quickActionsJson = quickActionsJson
        self._items = State(initialValue: currentActions)
        self.lang = lang
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items) { item in
                        Button {
                            editingItem = item
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.icon)
                                    .font(.title3)
                                    .foregroundStyle(Color(hex: item.colorHex))
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    HStack(spacing: 4) {
                                        if !item.defaultMerchant.isEmpty {
                                            Text(item.defaultMerchant)
                                        }
                                        if !item.defaultCategoryName.isEmpty {
                                            Text("• \(item.defaultCategoryName)")
                                        }
                                        if !item.defaultPaymentMethodName.isEmpty {
                                            Text("• \(item.defaultPaymentMethodName)")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                }

                                Spacer()

                                Image(systemName: "pencil")
                                    .font(.caption.bold())
                                    .foregroundStyle(.blue)
                                    .padding(6)
                                    .background(Color.blue.opacity(0.12))
                                    .clipShape(Circle())
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation {
                                    items.removeAll(where: { $0.id == item.id })
                                    saveChanges()
                                }
                            } label: {
                                Label(L10n.tr("Delete", lang: lang), systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                editingItem = item
                            } label: {
                                Label(L10n.tr("Edit", lang: lang), systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                withAnimation {
                                    items.removeAll(where: { $0.id == item.id })
                                    saveChanges()
                                }
                            } label: {
                                Label(L10n.tr("Delete", lang: lang), systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { indexSet in
                        items.remove(atOffsets: indexSet)
                        saveChanges()
                    }
                    .onMove { indices, newOffset in
                        items.move(fromOffsets: indices, toOffset: newOffset)
                        saveChanges()
                    }
                } header: {
                    Text(L10n.tr("Quick Actions", lang: lang)).lineLimit(1)
                } footer: {
                    Text(lang == "zh-HK" ? "點擊任何快捷鍵即可編輯詳情。向左滑動或在編輯頁面可直接刪除，點擊右上角「排序」可調整先後順序。" : "Tap any shortcut to edit its details. Swipe left or open edit sheet to delete. Use Edit above to reorder.").lineLimit(2)
                }

                Section {
                    Button {
                        let newItem = QuickActionItem(
                            title: "New Action",
                            icon: "tag.fill",
                            colorHex: "#007AFF"
                        )
                        items.append(newItem)
                        editingItem = newItem
                        saveChanges()
                    } label: {
                        Label(L10n.tr("New Shortcut", lang: lang), systemImage: "plus.circle.fill")
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                    }

                    Button(role: .destructive) {
                        items = QuickActionItem.defaultItems
                        saveChanges()
                    } label: {
                        Label(L10n.tr("Reset Defaults", lang: lang), systemImage: "arrow.counterclockwise")
                            .lineLimit(1)
                    }
                }
            }
            .navigationTitle(L10n.tr("Quick Actions", lang: lang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("Done", lang: lang)) {
                        saveChanges()
                        dismiss()
                    }
                    .bold()
                }
            }
            .sheet(item: $editingItem) { item in
                EditQuickActionSheet(
                    item: item,
                    lang: lang,
                    onSave: { updated in
                        if let index = items.firstIndex(where: { $0.id == updated.id }) {
                            items[index] = updated
                            saveChanges()
                        }
                    },
                    onDelete: { toDelete in
                        items.removeAll(where: { $0.id == toDelete.id })
                        saveChanges()
                    }
                )
            }
        }
    }

    private func saveChanges() {
        if let data = try? AppSerializationManager.shared.jsonEncoder.encode(items),
           let str = String(data: data, encoding: .utf8) {
            quickActionsJson = str
        }
    }
}

// MARK: - Edit Quick Action Sheet
struct EditQuickActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var item: QuickActionItem
    let lang: String
    let onSave: (QuickActionItem) -> Void
    var onDelete: ((QuickActionItem) -> Void)? = nil

    @State private var title: String
    @State private var selectedIcon: String
    @State private var selectedColor: String
    @State private var merchant: String
    @State private var categoryName: String
    @State private var paymentMethodName: String

    let availableIcons = [
        "plus.circle.fill", "wave.3.forward.circle.fill", "cup.and.saucer.fill",
        "cart.fill", "fork.knife", "tram.fill", "bag.fill", "fuelpump.fill",
        "film.fill", "heart.fill", "bolt.fill", "banknote.fill"
    ]

    let availableColors = [
        "#007AFF", "#FF9500", "#34C759", "#AF52DE",
        "#FF2D55", "#5856D6", "#FF3B30", "#8E8E93"
    ]

    init(
        item: QuickActionItem,
        lang: String,
        onSave: @escaping (QuickActionItem) -> Void,
        onDelete: ((QuickActionItem) -> Void)? = nil
    ) {
        self._item = State(initialValue: item)
        self.lang = lang
        self.onSave = onSave
        self.onDelete = onDelete
        self._title = State(initialValue: item.title)
        self._selectedIcon = State(initialValue: item.icon)
        self._selectedColor = State(initialValue: item.colorHex)
        self._merchant = State(initialValue: item.defaultMerchant)
        self._categoryName = State(initialValue: item.defaultCategoryName)
        self._paymentMethodName = State(initialValue: item.defaultPaymentMethodName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.tr("Shortcut Title", lang: lang)) {
                    TextField("Title", text: $title)
                        .lineLimit(1)
                }

                Section(L10n.tr("Icon & Color", lang: lang)) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(availableIcons, id: \.self) { icon in
                                Button {
                                    selectedIcon = icon
                                } label: {
                                    Image(systemName: icon)
                                        .font(.title2)
                                        .frame(width: 42, height: 42)
                                        .background(selectedIcon == icon ? Color(hex: selectedColor).opacity(0.2) : Color(.tertiarySystemFill))
                                        .foregroundStyle(selectedIcon == icon ? Color(hex: selectedColor) : .primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(selectedIcon == icon ? Color(hex: selectedColor) : Color.clear, lineWidth: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    HStack(spacing: 12) {
                        ForEach(availableColors, id: \.self) { colorHex in
                            Button {
                                selectedColor = colorHex
                            } label: {
                                Circle()
                                    .fill(Color(hex: colorHex))
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: selectedColor == colorHex ? 2.5 : 0)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Preset Values (Optional)") {
                    TextField(L10n.tr("Preset Merchant", lang: lang), text: $merchant)
                        .lineLimit(1)
                    TextField(L10n.tr("Preset Category", lang: lang), text: $categoryName)
                        .lineLimit(1)
                    TextField(L10n.tr("Preset Payment", lang: lang), text: $paymentMethodName)
                        .lineLimit(1)
                }

                Section {
                    Button(role: .destructive) {
                        onDelete?(item)
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Label(L10n.tr("Delete", lang: lang), systemImage: "trash.fill")
                                .foregroundStyle(.red)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(L10n.tr("Edit Shortcut", lang: lang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Cancel", lang: lang)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("Done", lang: lang)) {
                        var updated = item
                        updated.title = title
                        updated.icon = selectedIcon
                        updated.colorHex = selectedColor
                        updated.defaultMerchant = merchant
                        updated.defaultCategoryName = categoryName
                        updated.defaultPaymentMethodName = paymentMethodName
                        onSave(updated)
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}
