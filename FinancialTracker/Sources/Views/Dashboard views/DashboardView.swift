//
//  DashboardView.swift
//  Worthly
//
//  Modularized into focused sub-views:
//  - DashboardView (Coordinator)
//  - DashboardHeaderView
//  - DashboardFeaturedAnalyticsView
//  - DashboardQuickActionsView
//  - DashboardRecentTransactionsView
//

import Foundation
import SwiftUI
import SwiftData
import Charts

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
    
    @State private var cachedSnapshot: DashboardMetricsSnapshot? = nil
    @State private var selectedTrendDay: Int? = nil
    
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
    
    private var currentMetrics: DashboardMetricsSnapshot {
        let key = dashboardCalculationKey
        if let cached = cachedSnapshot, cached.key == key {
            return cached
        }
        return buildMetricsSnapshot(forKey: key)
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
        max(0.0, monthlyBudget - currentMetrics.totalSpentThisMonth)
    }
    
    private var budgetProgress: Double {
        guard monthlyBudget > 0 else { return 0.0 }
        return min(currentMetrics.totalSpentThisMonth / monthlyBudget, 1.0)
    }
    
    public var body: some View {
        let metrics = currentMetrics
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    DashboardHeaderView(
                        netWorth: netWorth,
                        totalAssets: totalAssets,
                        totalLiabilities: totalLiabilities,
                        totalSpentThisMonth: metrics.totalSpentThisMonth,
                        monthlyBudget: monthlyBudget,
                        remainingBudget: remainingBudget,
                        budgetProgress: budgetProgress,
                        monthlyTrendData: metrics.monthlyTrendData,
                        defaultCurrency: defaultCurrency,
                        appLanguage: appLanguage,
                        isPrivacyMode: $isPrivacyMode,
                        showingAccountsManager: $showingAccountsManager,
                        selectedTrendDay: $selectedTrendDay
                    )
                    
                    DashboardFeaturedAnalyticsView(
                        activeSnapshot: $activeSnapshot,
                        dayOfWeek: metrics.dayOfWeek,
                        cashFlow: metrics.cashFlow,
                        categories: metrics.categories,
                        paymentMethods: metrics.paymentMethods,
                        topMerchants: metrics.topMerchants,
                        defaultCurrency: defaultCurrency,
                        appLanguage: appLanguage,
                        onNavigateToAnalytics: onNavigateToAnalytics
                    )
                    
                    DashboardQuickActionsView(
                        quickActions: quickActions,
                        defaultCurrency: defaultCurrency,
                        appLanguage: appLanguage,
                        instantLogBannerText: instantLogBannerText,
                        canUndoInstantLog: lastInstantLoggedTransaction != nil,
                        onTapAction: { handleQuickActionTap($0) },
                        onInstantLogAction: { action, amt in performInstantQuickAction(action, amount: amt) },
                        onCustomAmountAction: { activeQuickAction = $0 },
                        onEditAction: { directEditingQuickAction = $0 },
                        onOpenCustomize: { showingCustomizeShortcuts = true },
                        onUndoInstantLog: { undoLastInstantLog() }
                    )
                    
                    DashboardRecentTransactionsView(
                        transactions: transactions,
                        defaultCurrency: defaultCurrency,
                        appLanguage: appLanguage,
                        onSelectTransaction: { selectedItemToEdit = $0 }
                    )
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

    // MARK: - Quick Action Handlers
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

        let resolvedToMethod: PaymentMethodItem? = {
            guard action.transactionType == .transfer else { return nil }
            let destName = action.toPaymentMethodName ?? "Octopus"
            return allAccounts.first(where: { $0.name.localizedCaseInsensitiveContains(destName) })
        }()

        let merch = action.defaultMerchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? action.title
            : action.defaultMerchant

        let finalMerch: String = {
            if action.transactionType == .transfer {
                return String(format: "%@ → %@", resolvedMethod?.name ?? "Account", resolvedToMethod?.name ?? "Octopus")
            }
            return merch
        }()

        let newTx = TransactionItem(
            timestamp: Date(),
            amount: amount,
            currency: defaultCurrency,
            merchant: finalMerch,
            notes: action.transactionType == .transfer ? "1-Tap Octopus Top-Up" : "1-Tap Quick Action",
            type: action.transactionType,
            category: action.transactionType == .transfer ? nil : resolvedCategory,
            paymentMethod: resolvedMethod,
            toPaymentMethod: resolvedToMethod,
            isExcludedFromBudget: false
        )

        modelContext.insert(newTx)
        AppDataStore.saveContext(modelContext)

        let affectedIds = Set([resolvedMethod?.id, resolvedToMethod?.id].compactMap { $0 })
        if !affectedIds.isEmpty {
            AccountBalanceManager.shared.recalculateBalances(forAccountIds: affectedIds, context: modelContext)
        } else {
            AccountBalanceManager.shared.recalculateBalances(context: modelContext)
        }
        recomputeMetrics(forceSyncWidget: true)

        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif

        let sign = action.transactionType == .income ? "+" : (action.transactionType == .transfer ? "⇄ " : "-")
        withAnimation(.spring(response: 0.3)) {
            lastInstantLoggedTransaction = newTx
            instantLogBannerText = String(format: "%@%@ %.2f • %@", sign, defaultCurrency, amount, finalMerch)
        }
    }

    private func undoLastInstantLog() {
        guard let tx = lastInstantLoggedTransaction else { return }
        let affectedIds = Set([tx.paymentMethod?.id, tx.toPaymentMethod?.id].compactMap { $0 })
        modelContext.delete(tx)
        AppDataStore.saveContext(modelContext)
        if !affectedIds.isEmpty {
            AccountBalanceManager.shared.recalculateBalances(forAccountIds: affectedIds, context: modelContext)
        } else {
            AccountBalanceManager.shared.recalculateBalances(context: modelContext)
        }
        recomputeMetrics(forceSyncWidget: true)
        withAnimation(.easeOut(duration: 0.2)) {
            lastInstantLoggedTransaction = nil
            instantLogBannerText = nil
        }
    }

    // MARK: - Metrics Calculation
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
        
        var trendPoints: [TrendPoint] = []
        var running: Double = 0.0
        for day in 1...currentDay {
            running += dailyTotals[day] ?? 0.0
            trendPoints.append(TrendPoint(day: day, amount: running))
        }
        
        let dayOfWeekItems: [DashboardDayItem] = (1...7).map { wd in
            DashboardDayItem(day: wd, name: weekdayNames[wd - 1], total: weekTotals[wd] ?? 0.0)
        }
        
        let cashFlowItems: [DashboardFlowBar] = [
            DashboardFlowBar(label: incomeLabel, amount: totalIncomeThisMonth, isIncome: true),
            DashboardFlowBar(label: expenseLabel, amount: spentThisMonth, isIncome: false)
        ]
        
        let categoryItems: [DashboardCatShare] = catTotals
            .map { DashboardCatShare(name: $0.key, colorHex: catColors[$0.key] ?? "#007AFF", total: $0.value) }
            .sorted { $0.total > $1.total }
        
        let methodItems: [DashboardMethodItem] = methodTotals
            .map { DashboardMethodItem(name: $0.key, colorHex: methodColors[$0.key] ?? "#007AFF", total: $0.value) }
            .sorted { $0.total > $1.total }
        
        let merchantItems: [DashboardMerchantItem] = Array(
            merchantTotals
                .map { DashboardMerchantItem(name: $0.key, total: $0.value) }
                .sorted { $0.total > $1.total }
                .prefix(4)
        )
        
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
        let key = dashboardCalculationKey
        let snapshot = buildMetricsSnapshot(forKey: key)
        cachedSnapshot = snapshot
        if forceSyncWidget {
            WidgetSyncManager.shared.syncWidget(context: modelContext)
        }
    }
}
