//
//  DataStore.swift
//  FinancialTracker
//

import Foundation
import SwiftData
import WidgetKit

public final class AppDataStore {
    public static let appGroupIdentifier = "group.com.financialtracker.app"
    
    public static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            TransactionItem.self,
            CategoryItem.self,
            PaymentMethodItem.self
        ])
        
        // 1. Attempt Shared App Group SQLite Container
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let sqliteURL = containerURL.appendingPathComponent("FinancialTracker.sqlite")
            let config = ModelConfiguration(schema: schema, url: sqliteURL, cloudKitDatabase: .none)
            if let container = try? ModelContainer(for: schema, configurations: [config]) {
                return container
            }
        }
        
        // 2. Fallback to Local App Storage if App Group is unavailable or locked
        let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: [localConfig]) {
            return container
        }
        
        // 3. Fallback to In-Memory Container to prevent app launch crash loops
        let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return (try? ModelContainer(for: schema, configurations: [memoryConfig])) ?? {
            try! ModelContainer(for: schema)
        }()
    }()
}

// MARK: - Widget Synchronization Manager
public final class WidgetSyncManager {
    public static let shared = WidgetSyncManager()
    
    private init() {}
    
    /// Synchronizes current month's expenses and budget to shared App Group and reloads widgets
    public func syncWidget(context: ModelContext? = nil) {
        let modelContext = context ?? ModelContext(AppDataStore.sharedModelContainer)
        let descriptor = FetchDescriptor<TransactionItem>()
        let allItems = (try? modelContext.fetch(descriptor)) ?? []
        
        let calendar = Calendar.current
        let now = Date()
        let thisMonthItems = allItems.filter {
            calendar.isDate($0.timestamp, equalTo: now, toGranularity: .month) && $0.type == .expense
        }
        let spent = thisMonthItems.reduce(0.0) { $0 + $1.amount }
        
        let budget = UserDefaults.standard.double(forKey: "monthly_budget")
        let activeBudget = budget > 0 ? budget : 15000.0
        let remaining = max(0, activeBudget - spent)
        let currency = UserDefaults.standard.string(forKey: "default_currency") ?? "HKD"
        
        if let sharedDefaults = UserDefaults(suiteName: AppDataStore.appGroupIdentifier) {
            sharedDefaults.set(spent, forKey: "widget_spent_this_month")
            sharedDefaults.set(activeBudget, forKey: "widget_monthly_budget")
            sharedDefaults.set(remaining, forKey: "widget_remaining_budget")
            sharedDefaults.set(currency, forKey: "widget_currency")
            sharedDefaults.set(now.timeIntervalSince1970, forKey: "widget_last_sync_time")
        }
        
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Account Balance & Net Worth Manager
public final class AccountBalanceManager {
    public static let shared = AccountBalanceManager()
    private init() {}
    
    /// Safely recalculates currentBalance for all accounts without crashing on deleted objects
    public func recalculateBalances(context: ModelContext) {
            let accounts = (try? context.fetch(FetchDescriptor<PaymentMethodItem>())) ?? []
            let transactions = (try? context.fetch(FetchDescriptor<TransactionItem>())) ?? []
            
            // 1. Collect valid, active account IDs
            let activeAccounts = accounts.filter { !$0.isDeleted }
            let validAccountIds = Set(activeAccounts.map { $0.id })
            
            // 2. Accumulate transaction amounts per account safely
            var accountDeltas: [UUID: Double] = [:]
            for t in transactions {
                guard !t.isDeleted else { continue }
                
                // Check source account
                if let pm = t.paymentMethod, !pm.isDeleted, validAccountIds.contains(pm.id) {
                    switch t.type {
                    case .expense, .transfer:
                        accountDeltas[pm.id, default: 0.0] -= t.amount
                    case .income:
                        accountDeltas[pm.id, default: 0.0] += t.amount
                    }
                }
                
                // Check destination account for transfers
                if let toPm = t.toPaymentMethod, !toPm.isDeleted, validAccountIds.contains(toPm.id), t.type == .transfer {
                    accountDeltas[toPm.id, default: 0.0] += t.amount
                }
            }
            
            // 3. Update balances
            for account in activeAccounts {
                let delta = accountDeltas[account.id] ?? 0.0
                account.currentBalance = account.initialBalance + delta
            }
            
            try? context.save()
        }
    public func calculateNetWorth(accounts: [PaymentMethodItem]) -> (assets: Double, liabilities: Double, netWorth: Double) {
        var totalAssets: Double = 0.0
        var totalLiabilities: Double = 0.0
        
        for acc in accounts {
            guard !acc.isDeleted else { continue }
            if acc.isAsset {
                totalAssets += acc.currentBalance
            } else {
                totalLiabilities += abs(acc.currentBalance)
            }
        }
        let netWorth = totalAssets - totalLiabilities
        return (totalAssets, totalLiabilities, netWorth)
    }
}

// MARK: - Supported App Languages
public enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case traditionalChinese = "zh-HK"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .english: return "English"
        case .traditionalChinese: return "繁體中文"
        }
    }
}

// MARK: - Initial Setup Seeder (Seeds Default Categories & Accounts Only - No Transactions)
    public final class SampleDataSeeder {
        public static func seedAll(context: ModelContext) {
            // 1. Seed Default Categories if empty
            let catDescriptor = FetchDescriptor<CategoryItem>()
            if (try? context.fetch(catDescriptor))?.isEmpty ?? true {
                for def in CategoryItem.defaultCategories {
                    let cat = CategoryItem(name: def.name, iconName: def.icon, colorHex: def.color)
                    context.insert(cat)
                }
            }
            
            // 2. Seed Default Accounts if empty
            let pmDescriptor = FetchDescriptor<PaymentMethodItem>()
            if (try? context.fetch(pmDescriptor))?.isEmpty ?? true {
                for spec in PaymentMethodItem.defaultAccounts {
                    let pm = PaymentMethodItem(
                        name: spec.name,
                        iconName: spec.icon,
                        colorHex: spec.color,
                        accountType: spec.type,
                        initialBalance: spec.defaultBalance,
                        currentBalance: spec.defaultBalance,
                        statementDay: spec.statementDay
                    )
                    context.insert(pm)
                }
            }
            
            // 3. Save initial setup (0 transactions created)
            try? context.save()
            AccountBalanceManager.shared.recalculateBalances(context: context)
            WidgetSyncManager.shared.syncWidget(context: context)
        }
    }

