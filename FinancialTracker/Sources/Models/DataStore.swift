//
//  DataStore.swift
//  Worthly
//

import Foundation
import SwiftData
import WidgetKit
import os

public final class AppDataStore {
    public static let appGroupIdentifier = "group.com.financialtracker.app"
    public static let logger = Logger(subsystem: "com.bryan.FinancialTracker", category: "DataStore")
    
    public static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            TransactionItem.self,
            CategoryItem.self,
            PaymentMethodItem.self,
            RecurringRuleItem.self
        ])
        
        // 1. Attempt Shared App Group SQLite Container
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let sqliteURL = containerURL.appendingPathComponent("FinancialTracker.sqlite")
            let config = ModelConfiguration(schema: schema, url: sqliteURL, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                logger.error("Failed to open App Group ModelContainer: \(error.localizedDescription, privacy: .public)")
            }
        }
        
        // 2. Fallback to Local App Storage if App Group is unavailable or locked
        let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [localConfig])
        } catch {
            logger.error("Failed to open Local ModelContainer: \(error.localizedDescription, privacy: .public)")
        }
        
        // 3. Fallback to In-Memory Container to prevent app launch crash loops
        let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return (try? ModelContainer(for: schema, configurations: [memoryConfig])) ?? {
            try! ModelContainer(for: schema)
        }()
    }()
    
    public static func saveContext(_ context: ModelContext, caller: String = #function) {
        do {
            if context.hasChanges {
                try context.save()
            }
        } catch {
            logger.error("SwiftData save failed in \(caller, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Widget Synchronization Manager
public final class WidgetSyncManager {
    public static let shared = WidgetSyncManager()
    
    private init() {}
    
    public func syncWidget(context: ModelContext? = nil) {
        let modelContext = context ?? ModelContext(AppDataStore.sharedModelContainer)
        let descriptor = FetchDescriptor<TransactionItem>()
        let allItems: [TransactionItem]
        do {
            allItems = try modelContext.fetch(descriptor)
        } catch {
            AppDataStore.logger.error("WidgetSyncManager fetch failed: \(error.localizedDescription, privacy: .public)")
            allItems = []
        }
        
        let calendar = Calendar.current
        let now = Date()
        let thisMonthItems = allItems.filter {
            calendar.isDate($0.timestamp, equalTo: now, toGranularity: .month) && $0.type == .expense && !$0.isExcludedFromBudget
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

// MARK: - Account Balance & Net Worth Manager (Supports Incremental & Full Recalculation)
public final class AccountBalanceManager {
    public static let shared = AccountBalanceManager()
    private init() {}
    
    /// Recalculates balances across all accounts or only a targeted subset of modified account IDs.
    public func recalculateBalances(
        forAccountIds targetIds: Set<UUID>? = nil,
        context: ModelContext
    ) {
        let accounts: [PaymentMethodItem]
        let transactions: [TransactionItem]
        do {
            accounts = try context.fetch(FetchDescriptor<PaymentMethodItem>())
            transactions = try context.fetch(FetchDescriptor<TransactionItem>())
        } catch {
            AppDataStore.logger.error("AccountBalanceManager fetch failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        
        let activeAccounts = accounts.filter { !$0.isDeleted }
        let targetSet = targetIds ?? Set(activeAccounts.map { $0.id })
        guard !targetSet.isEmpty else { return }
        
        var accountDeltas: [UUID: Double] = [:]
        for t in transactions {
            guard !t.isDeleted else { continue }
            
            if let pm = t.paymentMethod, !pm.isDeleted, targetSet.contains(pm.id) {
                switch t.type {
                case .expense, .transfer:
                    accountDeltas[pm.id, default: 0.0] -= t.amount
                case .income:
                    accountDeltas[pm.id, default: 0.0] += t.amount
                }
            }
            
            if let toPm = t.toPaymentMethod, !toPm.isDeleted, targetSet.contains(toPm.id), t.type == .transfer {
                accountDeltas[toPm.id, default: 0.0] += t.amount
            }
        }
        
        var didChange = false
        for account in activeAccounts where targetSet.contains(account.id) {
            let newBalance = account.initialBalance + (accountDeltas[account.id] ?? 0.0)
            if abs(account.currentBalance - newBalance) > 0.0001 {
                account.currentBalance = newBalance
                didChange = true
            }
        }
        
        if didChange {
            AppDataStore.saveContext(context)
        }
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

// MARK: - Default Account & Category Seeder (Seeds Default Categories & Accounts Only)
public final class SampleDataSeeder {
    /// Seeds the initial default categories and payment methods on first launch without creating fake transactions.
    public static func seedAll(context: ModelContext) {
        let catDescriptor = FetchDescriptor<CategoryItem>()
        if (try? context.fetch(catDescriptor))?.isEmpty ?? true {
            for def in CategoryItem.defaultCategories {
                let cat = CategoryItem(name: def.name, iconName: def.icon, colorHex: def.color)
                context.insert(cat)
            }
        }
        
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
        
        AppDataStore.saveContext(context)
        AccountBalanceManager.shared.recalculateBalances(context: context)
        WidgetSyncManager.shared.syncWidget(context: context)
    }
}

// MARK: - Recurring Payment Engine (Auto-Catch-Up on Launch & Background)
public final class RecurringPaymentManager {
    public static let shared = RecurringPaymentManager()
    private init() {}

    public func processDueRecurringPayments(context: ModelContext) {
        let descriptor = FetchDescriptor<RecurringRuleItem>()
        let rules: [RecurringRuleItem]
        do {
            rules = try context.fetch(descriptor)
        } catch {
            AppDataStore.logger.error("RecurringPaymentManager fetch failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard !rules.isEmpty else { return }

        let now = Date()
        var didCreate = false
        let calendar = Calendar.current

        for rule in rules {
            guard rule.recurrenceFrequency != .never else { continue }
            var dueDate = rule.nextDueDate

            var count = 0
            while dueDate <= now && count < 12 {
                count += 1
                let tx = TransactionItem(
                    timestamp: dueDate,
                    amount: rule.amount,
                    currency: rule.currency,
                    merchant: rule.title,
                    notes: "Recurring (\(rule.recurrenceFrequency.rawValue))",
                    type: rule.type,
                    category: rule.category,
                    paymentMethod: rule.paymentMethod,
                    toPaymentMethod: rule.toPaymentMethod,
                    isExcludedFromBudget: rule.isExcludedFromBudget
                )
                context.insert(tx)
                rule.lastProcessedDate = dueDate
                didCreate = true

                switch rule.recurrenceFrequency {
                case .weekly:
                    dueDate = calendar.date(byAdding: .weekOfYear, value: 1, to: dueDate) ?? dueDate.addingTimeInterval(7 * 86400)
                case .monthly:
                    dueDate = calendar.date(byAdding: .month, value: 1, to: dueDate) ?? dueDate.addingTimeInterval(30 * 86400)
                case .yearly:
                    dueDate = calendar.date(byAdding: .year, value: 1, to: dueDate) ?? dueDate.addingTimeInterval(365 * 86400)
                case .never:
                    break
                }
            }
            rule.nextDueDate = dueDate
        }

        if didCreate {
            AppDataStore.saveContext(context)
            AccountBalanceManager.shared.recalculateBalances(context: context)
            WidgetSyncManager.shared.syncWidget(context: context)
        }
    }
}
