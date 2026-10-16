import Foundation
import SwiftUI
import SwiftData
import Charts

// MARK: - Customizable Quick Action Item Model (Supports 1-Tap Instant Expense & Income Logging)
public struct QuickActionItem: Identifiable, Codable, Equatable {
    public var id: String
    public var title: String
    public var icon: String
    public var colorHex: String
    public var defaultMerchant: String
    public var defaultCategoryName: String
    public var defaultPaymentMethodName: String
    public var defaultAmount: Double?
    public var transactionTypeRaw: String?
    public var isInstantOneTap: Bool?
    
    public var transactionType: TransactionType {
        get { TransactionType(rawValue: transactionTypeRaw ?? "Expense") ?? .expense }
        set { transactionTypeRaw = newValue.rawValue }
    }
    
    public var shouldInstantLog: Bool {
        guard let amt = defaultAmount, amt > 0 else { return false }
        return isInstantOneTap ?? true
    }
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        icon: String = "plus.circle.fill",
        colorHex: String = "#007AFF",
        defaultMerchant: String = "",
        defaultCategoryName: String = "",
        defaultPaymentMethodName: String = "",
        defaultAmount: Double? = nil,
        transactionType: TransactionType = .expense,
        isInstantOneTap: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.colorHex = colorHex
        self.defaultMerchant = defaultMerchant
        self.defaultCategoryName = defaultCategoryName
        self.defaultPaymentMethodName = defaultPaymentMethodName
        self.defaultAmount = defaultAmount
        self.transactionTypeRaw = transactionType.rawValue
        self.isInstantOneTap = isInstantOneTap ?? (defaultAmount != nil && (defaultAmount ?? 0) > 0)
    }
    
    public static let defaultItems: [QuickActionItem] = [
        QuickActionItem(id: "1", title: "Add Expense", icon: "plus.circle.fill", colorHex: "#007AFF", defaultMerchant: "", defaultCategoryName: "", defaultPaymentMethodName: "CUHK Credit Card", defaultAmount: nil, transactionType: .expense, isInstantOneTap: false),
        QuickActionItem(id: "2", title: "Octopus MTR", icon: "wave.3.forward.circle.fill", colorHex: "#FF9500", defaultMerchant: "MTR", defaultCategoryName: "Octopus", defaultPaymentMethodName: "Octopus", defaultAmount: 5.60, transactionType: .expense, isInstantOneTap: true),
        QuickActionItem(id: "3", title: "Tram / Bus", icon: "tram.fill", colorHex: "#007AFF", defaultMerchant: "Transit", defaultCategoryName: "Octopus", defaultPaymentMethodName: "Octopus", defaultAmount: 2.20, transactionType: .expense, isInstantOneTap: true),
        QuickActionItem(id: "4", title: "Coffee/Meal", icon: "cup.and.saucer.fill", colorHex: "#34C759", defaultMerchant: "Coffee / Meal", defaultCategoryName: "Dining", defaultPaymentMethodName: "CUHK Credit Card", defaultAmount: 45.00, transactionType: .expense, isInstantOneTap: true),
        QuickActionItem(id: "5", title: "Quick Income", icon: "arrow.down.left.circle.fill", colorHex: "#34C759", defaultMerchant: "Income", defaultCategoryName: "Salary", defaultPaymentMethodName: "Bank Transfer / FPS", defaultAmount: 500.00, transactionType: .income, isInstantOneTap: true)
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

public struct DashboardMetricsSnapshot: Equatable, Sendable {
    public let key: Int
    public let totalSpentThisMonth: Double
    public let monthlyTrendData: [TrendPoint]
    public let dayOfWeek: [DashboardDayItem]
    public let cashFlow: [DashboardFlowBar]
    public let categories: [DashboardCatShare]
    public let paymentMethods: [DashboardMethodItem]
    public let topMerchants: [DashboardMerchantItem]
}

public struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    
    @Query(sort: \TransactionItem.timestamp, order: .reverse) private var transactions: [TransactionItem]
    @Query(sort: \PaymentMethodItem.name) private var allAccounts: [PaymentMethodItem]
    @Query(sort: \CategoryItem.name) private var allCategories: [CategoryItem]
    
    @AppStorage("monthly_budget") private var monthlyBudget: Double = 15000.0
    @AppStorage("default_currency") private var defaultCurrency: String = "HKD"
    @AppStorage("app_language") private var appLanguage: String = "en"
    @AppStorage("dashboard_active_snapshot") private var activeSnapshot: String = "dayOfWeek"
    @AppStorage("custom_quick_actions_json") private var quickActionsJson: String = ""
    @AppStorage("is_privacy_mode") private var isPrivacyMode: Bool = false
    
    @State private var showingAddExpense = false
    @State private var selectedItemToEdit: TransactionItem? = nil
    @State private var activeQuickAction: QuickActionItem? = nil
    @State private var showingCustomizeShortcuts = false
    @State private var showingAccountsManager: Bool = false
    @State private var directEditingQuickAction: QuickActionItem? = nil
    @State private var instantLogBannerText: String? = nil
    @State private var lastInstantLoggedTransaction: TransactionItem? = nil
    
    // Cached snapshot + synchronous fallback ensures Frame-1 rendering on cold launch
    @State private var cachedSnapshot: DashboardMetricsSnapshot? = nil
    @State private var selectedTrendDay: Int? = nil
    
    // Tracks any change to transactions, budget, currency, or language
    private var dashboardCalculationKey: Int {
        var hasher = Hasher()
        hasher.combine(transactions.count)
        hasher.combine(monthlyBudget)
        hasher.combine(appLanguage)
        hasher.combine(defaultCurrency)
        for item in transactions.prefix(12) {
            hasher.combine(item.id)
            hasher.combine(item.amount)
            hasher.combine(item.timestamp)
            hasher.combine(item.type.rawValue)
            hasher.combine(item.isExcludedFromBudget)
            hasher.combine(item.category?.name ?? "")
            hasher.combine(item.paymentMethod?.name ?? "")
        }
        return hasher.finalize()
    }
    
    // Frame-0 safe metrics: if @State cache hasn't caught up yet on cold start,
    // computes synchronously from @Query transactions just like Net Worth does.
    private var currentMetrics: DashboardMetricsSnapshot {
        let key = dashboardCalculationKey
        if let cached = cachedSnapshot, cached.key == key {
            return cached
        }
        return buildMetricsSnapshot(forKey: key)
    }
    
    private var totalSpentThisMonth: Double {
        currentMetrics.totalSpentThisMonth
    }
    
    private var monthlyTrendData: [TrendPoint] {
        currentMetrics.monthlyTrendData
    }
    
    private var cachedDayOfWeek: [DashboardDayItem] {
        currentMetrics.dayOfWeek
    }
    
    private var cachedCashFlow: [DashboardFlowBar] {
        currentMetrics.cashFlow
    }
    
    private var cachedCategories: [DashboardCatShare] {
        currentMetrics.categories
    }
    
    private var cachedPaymentMethods: [DashboardMethodItem] {
        currentMetrics.paymentMethods
    }
    
    private var cachedTopMerchants: [DashboardMerchantItem] {
        currentMetrics.topMerchants
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
                recomputeMetrics(forceSyncWidget: true)
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
            .sheet(item: $directEditingQuickAction) { itemToEdit in
                EditQuickActionSheet(
                    item: itemToEdit,
                    lang: appLanguage,
                    onSave: { updated in
                        var current = quickActions
                        if let idx = current.firstIndex(where: { $0.id == updated.id }) {
                            current[idx] = updated
                        } else {
                            current.append(updated)
                        }
                        if let data = try? AppSerializationManager.shared.jsonEncoder.encode(current),
                           let str = String(data: data, encoding: .utf8) {
                            quickActionsJson = str
                        }
                    },
                    onDelete: { toDelete in
                        var current = quickActions
                        current.removeAll(where: { $0.id == toDelete.id })
                        if let data = try? AppSerializationManager.shared.jsonEncoder.encode(current),
                           let str = String(data: data, encoding: .utf8) {
                            quickActionsJson = str
                        }
                    }
                )
            }
            .sheet(isPresented: $showingAccountsManager) {
                PaymentMethodManagementView()
            }
            .onAppear {
                recomputeMetrics(forceSyncWidget: true)
            }
            .task(id: dashboardCalculationKey) {
                recomputeMetrics(forceSyncWidget: true)
            }
            .onChange(of: transactions.count) { _, _ in
                recomputeMetrics(forceSyncWidget: true)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    recomputeMetrics(forceSyncWidget: false)
                }
            }
        }
    }

    // MARK: - Synchronous, Zero-Delay Metrics Calculation
    private func buildMetricsSnapshot(forKey key: Int) -> DashboardMetricsSnapshot {
        let calendar = Calendar.current
        let now = Date()
        let currentDay = max(1, calendar.component(.day, from: now))
        let lang = appLanguage
        let incomeLabel = L10n.tr("Income", lang: lang)
        let expenseLabel = L10n.tr("Expense", lang: lang)
        let weekdayNames = L10n.weekdayNames(lang: lang)
        
        var spentThisMonth: Double = 0.0
        var totalIncomeThisMonth: Double = 0.0
        var dailyTotals = [Int: Double]()
        var weekTotals: [Int: Double] = [1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0]
        var catTotals = [String: Double]()
        var catColors = [String: String]()
        var methodTotals = [String: Double]()
        var methodColors = [String: String]()
        var merchantTotals = [String: Double]()
        
        for item in transactions {
            let isCurrentMonth = calendar.isDate(item.timestamp, equalTo: now, toGranularity: .month)
            
            if item.type == .income {
                if isCurrentMonth {
                    totalIncomeThisMonth += item.amount
                }
                continue
            }
            
            guard item.type == .expense else { continue }
            
            let amount = item.amount
            let catName = item.category?.name ?? "Other"
            let catColor = item.category?.colorHex ?? "#007AFF"
            let pmName = item.paymentMethod?.name ?? "Other"
            let pmColor = item.paymentMethod?.colorHex ?? "#007AFF"
            let merch = item.merchant.isEmpty ? catName : item.merchant
            
            if isCurrentMonth && !item.isExcludedFromBudget {
                spentThisMonth += amount
                let day = calendar.component(.day, from: item.timestamp)
                dailyTotals[day, default: 0.0] += amount
            }
            
            let weekday = calendar.component(.weekday, from: item.timestamp)
            weekTotals[weekday, default: 0.0] += amount
            
            catTotals[catName, default: 0.0] += amount
            if catColors[catName] == nil {
                catColors[catName] = catColor
            }
            
            methodTotals[pmName, default: 0.0] += amount
            if methodColors[pmName] == nil {
                methodColors[pmName] = pmColor
            }
            
            merchantTotals[merch, default: 0.0] += amount
        }
        
        // 1. Cumulative Monthly Trend Pacing (Day 1 ... Today)
        var cumulative: Double = 0.0
        var trendPoints: [TrendPoint] = []
        trendPoints.reserveCapacity(currentDay)
        for day in 1...currentDay {
            cumulative += dailyTotals[day] ?? 0.0
            trendPoints.append(TrendPoint(day: day, amount: cumulative))
        }
        
        // 2. Day of Week (Mon -> Sun)
        let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]
        let dayOfWeekItems = weekdayOrder.map { w in
            let safeName = (w - 1 >= 0 && w - 1 < weekdayNames.count) ? weekdayNames[w - 1] : "D\(w)"
            return DashboardDayItem(day: w, name: safeName, total: weekTotals[w] ?? 0.0)
        }
        
        // 3. Cash Flow
        let cashFlowItems = [
            DashboardFlowBar(label: incomeLabel, amount: totalIncomeThisMonth, isIncome: true),
            DashboardFlowBar(label: expenseLabel, amount: spentThisMonth, isIncome: false)
        ]
        
        // 4. Top Categories
        let categoryItems = catTotals.map { name, total in
            DashboardCatShare(name: name, colorHex: catColors[name] ?? "#007AFF", total: total)
        }
        .sorted { $0.total > $1.total }
        .prefix(4)
        .map { $0 }
        
        // 5. Top Payment Methods
        let methodItems = methodTotals.map { name, total in
            DashboardMethodItem(name: name, colorHex: methodColors[name] ?? "#007AFF", total: total)
        }
        .sorted { $0.total > $1.total }
        .prefix(3)
        .map { $0 }
        
        // 6. Top Merchants
        let merchantItems = merchantTotals.map { name, total in
            DashboardMerchantItem(name: name, total: total)
        }
        .sorted { $0.total > $1.total }
        .prefix(4)
        .map { $0 }
        
        return DashboardMetricsSnapshot(
            key: key,
            totalSpentThisMonth: spentThisMonth,
            monthlyTrendData: trendPoints,
            dayOfWeek: dayOfWeekItems,
            cashFlow: cashFlowItems,
            categories: categoryItems,
            paymentMethods: methodItems,
            topMerchants: merchantItems
        )
    }
    
    private func recomputeMetrics(forceSyncWidget: Bool = false) {
        repairAutoLoggedTransactionsIfNeeded()
        let key = dashboardCalculationKey
        let snapshot = buildMetricsSnapshot(forKey: key)
        cachedSnapshot = snapshot
        if forceSyncWidget {
            WidgetSyncManager.shared.syncWidget(context: modelContext)
        }
    }

    private func repairAutoLoggedTransactionsIfNeeded() {
        guard !transactions.isEmpty else { return }
        var octopusCat = allCategories.first(where: { $0.name.localizedCaseInsensitiveContains("Octopus") || $0.name.localizedCaseInsensitiveContains("八達通") })
        if octopusCat == nil {
            let newCat = CategoryItem(name: "Octopus", iconName: "wave.3.forward.circle.fill", colorHex: "#FF9500")
            modelContext.insert(newCat)
            octopusCat = newCat
        }
        let groceriesCat = allCategories.first(where: { $0.name.localizedCaseInsensitiveContains("Groceries") })
        let shoppingCat = allCategories.first(where: { $0.name.localizedCaseInsensitiveContains("Shopping") })
        let octopusMethod = allAccounts.first(where: { $0.name.localizedCaseInsensitiveContains("Octopus") || $0.name.localizedCaseInsensitiveContains("八達通") })
        let primaryCuhkCard = allAccounts.first(where: { $0.name == "CUHK Credit Card" })

        var didChange = false

        // Ensure CUHK Credit Card has a distinct credit card icon & blue color so it never clashes with purple Bank Transfer / FPS
        if let cuhk = primaryCuhkCard {
            if cuhk.colorHex == "#5856D6" {
                cuhk.colorHex = "#007AFF"
                cuhk.iconName = "creditcard.fill"
                didChange = true
            }
        }

        for item in transactions where item.type == .expense {
            let catName = item.category?.name ?? "Other"
            let merchLower = item.merchant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            // Merge duplicate "Hang Seng CUHK..." account into "CUHK Credit Card"
            if let pmName = item.paymentMethod?.name,
               pmName != "CUHK Credit Card",
               pmName.localizedCaseInsensitiveContains("CUHK"),
               let cuhk = primaryCuhkCard {
                item.paymentMethod = cuhk
                didChange = true
            }

            // Fix Fortress -> Shopping (instead of Groceries)
            if (merchLower.contains("fortress") || merchLower.contains("豐澤")),
               let sCat = shoppingCat,
               catName != sCat.name {
                item.category = sCat
                didChange = true
            }

            // Automatically route Octopus / transit taps to the dedicated "Octopus" category
            if catName == "Other" || catName == "Transport" || item.category == nil {
                if merchLower.isEmpty || merchLower == "wallet purchase" || merchLower.contains("octopus") || merchLower.contains("mtr") || merchLower.contains("kmb") {
                    if let octCat = octopusCat {
                        item.category = octCat
                        didChange = true
                    }
                    if let oct = octopusMethod, item.paymentMethod?.name != oct.name {
                        item.paymentMethod = oct
                        didChange = true
                    }
                } else if merchLower.contains("lung fung") || merchLower.contains("龍豐") {
                    if let gCat = groceriesCat {
                        item.category = gCat
                        didChange = true
                    }
                    if let oct = octopusMethod, item.paymentMethod?.name != oct.name {
                        item.paymentMethod = oct
                        didChange = true
                    }
                } else if merchLower.contains("ichicake") || merchLower.contains("bindo*") || merchLower.contains("kpay*") || merchLower.contains("bodybuilding") {
                    if let gCat = groceriesCat {
                        item.category = gCat
                        didChange = true
                    }
                }
            }
        }

        if didChange {
            try? modelContext.save()
            AccountBalanceManager.shared.recalculateBalances(context: modelContext)
        }
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

    // MARK: - 1. Budget Hero Card (Upgraded Proportional Trend & Pace Line)
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
        
        // Proportional Y-axis ceiling so 9% spend looks like 9% of budget, while keeping the full month pace visible
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
                // Interactive Scrubbing / Pace Status Header
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
                    // 1. Ideal Budget Pace Line (Day 1 -> End of Month)
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
                    
                    // 2. Actual Cumulative Spending Area & Line (Day 1 -> Today)
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
                    
                    // 3. Current Day Endpoint Marker (or Selected Scrub Day Marker)
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

    // MARK: - 3. Customizable Quick Actions Section (With 1-Tap Instant Logging & Undo Toast)
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
            
            if let bannerText = instantLogBannerText {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(bannerText)
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    if lastInstantLoggedTransaction != nil {
                        Button {
                            undoLastInstantLog()
                        } label: {
                            Text(appLanguage == "zh-HK" ? "撤銷" : "Undo")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.15))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(quickActions) { action in
                        Button {
                            handleQuickActionTap(action)
                        } label: {
                            VStack(spacing: 5) {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: action.icon)
                                        .font(.title3)
                                        .foregroundStyle(Color(hex: action.colorHex))
                                        .frame(width: 36, height: 28)
                                    
                                    if action.shouldInstantLog {
                                        Image(systemName: "bolt.fill")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(3)
                                            .background(action.transactionType == .income ? Color.green : Color.blue)
                                            .clipShape(Circle())
                                            .offset(x: 8, y: -3)
                                    }
                                }
                                
                                Text(action.title)
                                    .font(.caption.bold())
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                
                                if let amt = action.defaultAmount, amt > 0 {
                                    Text(
                                        String(
                                            format: "%@%@ %.1f",
                                            action.transactionType == .income ? "+" : "-",
                                            defaultCurrency,
                                            amt
                                        )
                                    )
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(action.transactionType == .income ? .green : .secondary)
                                    .lineLimit(1)
                                } else {
                                    Text(appLanguage == "zh-HK" ? "輸入金額" : "Tap to enter")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(width: 104, height: 84)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if let amt = action.defaultAmount, amt > 0 {
                                Button {
                                    performInstantQuickAction(action, amount: amt)
                                } label: {
                                    Label(
                                        appLanguage == "zh-HK" ? "一鍵即時記帳" : "Instant Log Now",
                                        systemImage: "bolt.fill"
                                    )
                                }
                            }
                            Button {
                                activeQuickAction = action
                            } label: {
                                Label(
                                    appLanguage == "zh-HK" ? "自訂金額記帳..." : "Log with Custom Amount...",
                                    systemImage: "keyboard"
                                )
                            }
                            Button {
                                directEditingQuickAction = action
                            } label: {
                                Label(
                                    appLanguage == "zh-HK" ? "編輯此快捷鍵..." : "Edit Shortcut...",
                                    systemImage: "pencil"
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func handleQuickActionTap(_ action: QuickActionItem) {
        if action.shouldInstantLog, let amt = action.defaultAmount, amt > 0 {
            performInstantQuickAction(action, amount: amt)
        } else {
            activeQuickAction = action
        }
    }

    private func performInstantQuickAction(_ action: QuickActionItem, amount: Double) {
        let resolvedCategory: CategoryItem? = {
            if !action.defaultCategoryName.isEmpty {
                if let match = allCategories.first(where: {
                    $0.name.localizedCaseInsensitiveCompare(action.defaultCategoryName) == .orderedSame ||
                    $0.name.localizedCaseInsensitiveContains(action.defaultCategoryName)
                }) {
                    return match
                }
            }
            return allCategories.first
        }()

        let resolvedMethod: PaymentMethodItem? = {
            if !action.defaultPaymentMethodName.isEmpty {
                if let match = allAccounts.first(where: {
                    $0.name.localizedCaseInsensitiveCompare(action.defaultPaymentMethodName) == .orderedSame ||
                    $0.name.localizedCaseInsensitiveContains(action.defaultPaymentMethodName)
                }) {
                    return match
                }
            }
            return allAccounts.first
        }()

        let merch = action.defaultMerchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? action.title
            : action.defaultMerchant

        let newTx = TransactionItem(
            timestamp: Date(),
            amount: amount,
            currency: defaultCurrency,
            merchant: merch,
            notes: "1-Tap Quick Action",
            type: action.transactionType,
            category: resolvedCategory,
            paymentMethod: resolvedMethod,
            isExcludedFromBudget: false
        )

        modelContext.insert(newTx)
        try? modelContext.save()
        AccountBalanceManager.shared.recalculateBalances(context: modelContext)
        recomputeMetrics(forceSyncWidget: true)

        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif

        let sign = action.transactionType == .income ? "+" : "-"
        withAnimation(.spring(response: 0.3)) {
            lastInstantLoggedTransaction = newTx
            instantLogBannerText = String(format: "%@%@ %.2f • %@", sign, defaultCurrency, amount, merch)
        }
    }

    private func undoLastInstantLog() {
        guard let tx = lastInstantLoggedTransaction else { return }
        modelContext.delete(tx)
        try? modelContext.save()
        AccountBalanceManager.shared.recalculateBalances(context: modelContext)
        recomputeMetrics(forceSyncWidget: true)
        withAnimation(.easeOut(duration: 0.2)) {
            lastInstantLoggedTransaction = nil
            instantLogBannerText = nil
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
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(width: 38, height: 38)
                                    .background(iconColor)
                                    .clipShape(Circle())
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(item.merchant.isEmpty ? (item.category?.name ?? "Other") : item.merchant)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                        
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
                                    
                                    HStack(spacing: 5) {
                                        Image(systemName: item.paymentMethod?.iconName ?? "creditcard")
                                        Text(item.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                                            .lineLimit(1)
                                    }
                                    .font(.caption)
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

// MARK: - Edit Quick Action Sheet (With 1-Tap Expense / Income & Fixed Amount)
struct EditQuickActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryItem.name) private var categories: [CategoryItem]
    @Query(sort: \PaymentMethodItem.name) private var paymentMethods: [PaymentMethodItem]
    @AppStorage("default_currency") private var defaultCurrency: String = "HKD"

    @State private var item: QuickActionItem
    let lang: String
    let onSave: (QuickActionItem) -> Void
    var onDelete: ((QuickActionItem) -> Void)? = nil

    @State private var title: String
    @State private var selectedIcon: String
    @State private var selectedColor: String
    @State private var transactionType: TransactionType
    @State private var amountString: String
    @State private var isInstantOneTap: Bool
    @State private var merchant: String
    @State private var categoryName: String
    @State private var paymentMethodName: String

    let availableIcons = [
        "plus.circle.fill", "wave.3.forward.circle.fill", "cup.and.saucer.fill",
        "cart.fill", "fork.knife", "tram.fill", "bag.fill", "fuelpump.fill",
        "film.fill", "heart.fill", "bolt.fill", "banknote.fill", "arrow.down.left.circle.fill"
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
        self._transactionType = State(initialValue: item.transactionType)
        if let amt = item.defaultAmount, amt > 0 {
            self._amountString = State(initialValue: String(format: "%.2f", amt))
        } else {
            self._amountString = State(initialValue: "")
        }
        self._isInstantOneTap = State(initialValue: item.isInstantOneTap ?? (item.defaultAmount != nil && (item.defaultAmount ?? 0) > 0))
        self._merchant = State(initialValue: item.defaultMerchant)
        self._categoryName = State(initialValue: item.defaultCategoryName)
        self._paymentMethodName = State(initialValue: item.defaultPaymentMethodName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(lang == "zh-HK" ? "一鍵記帳設定 (1-Tap Instant Log)" : "1-Tap Instant Logging") {
                    Picker(lang == "zh-HK" ? "類型" : "Type", selection: $transactionType) {
                        Text(L10n.tr("Expense", lang: lang)).tag(TransactionType.expense)
                        Text(L10n.tr("Income", lang: lang)).tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text(lang == "zh-HK" ? "固定金額 (\(defaultCurrency))" : "Fixed Amount (\(defaultCurrency))")
                        Spacer()
                        TextField(lang == "zh-HK" ? "留空則每次輸入" : "Leave blank to ask", text: $amountString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.body.bold())
                            .foregroundStyle(transactionType == .income ? .green : .blue)
                            .onChange(of: amountString) { _, newValue in
                                if let val = Double(newValue), val > 0 {
                                    isInstantOneTap = true
                                }
                            }
                    }

                    if let val = Double(amountString), val > 0 {
                        Toggle(
                            lang == "zh-HK" ? "點擊即直接記帳 (免開表單)" : "1-Tap Instant Log (Skip Form)",
                            isOn: $isInstantOneTap
                        )
                    }
                }

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

                Section(lang == "zh-HK" ? "預設商戶、分類及帳戶" : "Preset Details") {
                    TextField(L10n.tr("Preset Merchant", lang: lang), text: $merchant)
                        .lineLimit(1)

                    Picker(L10n.tr("Preset Category", lang: lang), selection: $categoryName) {
                        Text(lang == "zh-HK" ? "預設" : "Default").tag("")
                        ForEach(categories) { cat in
                            Text(cat.name).tag(cat.name)
                        }
                    }

                    Picker(L10n.tr("Preset Payment", lang: lang), selection: $paymentMethodName) {
                        Text(lang == "zh-HK" ? "預設" : "Default").tag("")
                        ForEach(paymentMethods) { pm in
                            Text(pm.name).tag(pm.name)
                        }
                    }
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
                        updated.transactionType = transactionType
                        if let val = Double(amountString), val > 0 {
                            updated.defaultAmount = val
                            updated.isInstantOneTap = isInstantOneTap
                        } else {
                            updated.defaultAmount = nil
                            updated.isInstantOneTap = false
                        }
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
