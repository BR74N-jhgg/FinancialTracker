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
    private static let oneTimeMigrationKey = "has_completed_autolog_migration_v1_3"
    
    public static let sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: WorthlySchemaV1.self)
        
        // 1. Attempt Shared App Group SQLite Container
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let sqliteURL = containerURL.appendingPathComponent("FinancialTracker.sqlite")
            let config = ModelConfiguration(schema: schema, url: sqliteURL, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, migrationPlan: WorthlyMigrationPlan.self, configurations: [config])
            } catch {
                logger.error("Failed to open App Group ModelContainer: \(error.localizedDescription, privacy: .public)")
            }
        }
        
        // 2. Fallback to Local App Storage if App Group is unavailable or locked
        let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, migrationPlan: WorthlyMigrationPlan.self, configurations: [localConfig])
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
    
    /// One-time migration replacing the former DashboardView per-render repair loop (9.2-6).
    public static func runOneTimeAutoLogMigrationIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: oneTimeMigrationKey) else { return }
        
        do {
            let transactions = try context.fetch(FetchDescriptor<TransactionItem>())
            let categories = try context.fetch(FetchDescriptor<CategoryItem>())
            let accounts = try context.fetch(FetchDescriptor<PaymentMethodItem>())
            
            var octopusCat = categories.first(where: {
                $0.name.localizedCaseInsensitiveContains("Octopus") || $0.name.localizedCaseInsensitiveContains("八達通")
            })
            if octopusCat == nil && !transactions.isEmpty {
                let newCat = CategoryItem(name: "Octopus", iconName: "wave.3.forward.circle.fill", colorHex: "#FF9500")
                context.insert(newCat)
                octopusCat = newCat
            }
            
            let octopusMethod = accounts.first(where: {
                $0.name.localizedCaseInsensitiveContains("Octopus") || $0.name.localizedCaseInsensitiveContains("八達通")
            })
            
            var didChange = false
            for item in transactions where item.type == .expense {
                let merchLower = item.merchant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                
                // Delete legacy zero-charge transit entry notifications
                if MerchantRuleEngine.isZeroChargeEntryNotification(merchLower) {
                    context.delete(item)
                    didChange = true
                    continue
                }
                
                // Repair legacy balance-sentence misparses
                if merchLower.contains("your new balance is") || merchLower.contains("current balance is") {
                    item.merchant = "MTR"
                    if abs(item.amount - 60.90) < 0.01 {
                        item.amount = 3.20
                    }
                    if let octCat = octopusCat { item.category = octCat }
                    if let oct = octopusMethod { item.paymentMethod = oct }
                    didChange = true
                    continue
                }
                
                // Normalize uncategorized or fallback rows via MerchantRuleEngine
                let currentCatName = item.category?.name ?? "Other"
                if currentCatName == "Other" || item.category == nil {
                    let inferred = MerchantRuleEngine.inferCategoryName(
                        for: item.merchant,
                        rawMerchant: item.merchant,
                        cardName: item.paymentMethod?.name
                    )
                    if inferred != "Other",
                       let matchedCat = categories.first(where: { $0.name.localizedCaseInsensitiveCompare(inferred) == .orderedSame }) {
                        item.category = matchedCat
                        didChange = true
                    }
                }
            }
            
            if didChange {
                saveContext(context)
                AccountBalanceManager.shared.recalculateBalances(context: context)
            }
            UserDefaults.standard.set(true, forKey: oneTimeMigrationKey)
        } catch {
            logger.error("One-time auto-log migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Widget Synchronization Manager
public final class WidgetSyncManager {
    public static let shared = WidgetSyncManager()
    
    private init() {}
    
    public func syncWidget(context: ModelContext? = nil) {
        let modelContext = context ?? ModelContext(AppDataStore.sharedModelContainer)
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let expenseRaw = TransactionType.expense.rawValue
        let descriptor = FetchDescriptor<TransactionItem>(
            predicate: #Predicate<TransactionItem> { tx in
                tx.timestamp >= startOfMonth && tx.typeRaw == expenseRaw && !tx.isExcludedFromBudget
            }
        )
        let thisMonthItems: [TransactionItem]
        do {
            thisMonthItems = try modelContext.fetch(descriptor)
        } catch {
            AppDataStore.logger.error("WidgetSyncManager fetch failed: \(error.localizedDescription, privacy: .public)")
            thisMonthItems = []
        }
        // shortcut: sums raw amounts without FX conversion, upgrade to amountInBase when Phase 2 multi-currency lands
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
        // shortcut: full-table scan up to ~10k rows, upgrade to per-account #Predicate or incremental delta when >10k transactions
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

// MARK: - Recurring Payment Engine (Auto-Catch-Up on Launch, Foreground & Intent)
public final class RecurringPaymentManager {
    public static let shared = RecurringPaymentManager()
    private init() {}

    public func processDueRecurringPayments(context: ModelContext, referenceDate: Date = Date()) {
        let descriptor = FetchDescriptor<RecurringRuleItem>()
        let rules: [RecurringRuleItem]
        do {
            rules = try context.fetch(descriptor)
        } catch {
            AppDataStore.logger.error("RecurringPaymentManager fetch failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard !rules.isEmpty else { return }

        var didCreate = false
        var affectedAccountIds = Set<UUID>()
        let calendar = Calendar.current

        for rule in rules {
            guard !rule.isDeleted, !rule.isPaused, rule.recurrenceFrequency != .never else { continue }
            var dueDate = rule.nextDueDate

            var count = 0
            while dueDate <= referenceDate && count < 12 {
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
                    isExcludedFromBudget: rule.isExcludedFromBudget,
                    ruleId: rule.id
                )
                context.insert(tx)
                if let pmId = rule.paymentMethod?.id { affectedAccountIds.insert(pmId) }
                if let toId = rule.toPaymentMethod?.id { affectedAccountIds.insert(toId) }
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
            AccountBalanceManager.shared.recalculateBalances(
                forAccountIds: affectedAccountIds.isEmpty ? nil : affectedAccountIds,
                context: context
            )
            WidgetSyncManager.shared.syncWidget(context: context)
        }
    }
}

// MARK: - CSV Export & JSON Full Backup / Restore Manager (Phase 1: 9.1-5)
public struct CategoryBackupDTO: Codable, Sendable {
    public let id: UUID
    public let name: String
    public let iconName: String
    public let colorHex: String
}

public struct AccountBackupDTO: Codable, Sendable {
    public let id: UUID
    public let name: String
    public let iconName: String
    public let colorHex: String
    public let accountTypeRaw: String
    public let initialBalance: Double
    public let currentBalance: Double
    public let statementDay: Int?
}

public struct RecurringRuleBackupDTO: Codable, Sendable {
    public let id: UUID
    public let title: String
    public let amount: Double
    public let currency: String
    public let typeRaw: String
    public let recurrenceFrequencyRaw: String
    public let nextDueDate: Date
    public let lastProcessedDate: Date?
    public let isExcludedFromBudget: Bool
    public let isPaused: Bool
    public let categoryName: String?
    public let paymentMethodName: String?
    public let toPaymentMethodName: String?
}

public struct TransactionBackupDTO: Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let amount: Double
    public let currency: String
    public let merchant: String
    public let notes: String
    public let typeRaw: String
    public let isExcludedFromBudget: Bool
    public let ruleId: UUID?
    public let categoryName: String?
    public let paymentMethodName: String?
    public let toPaymentMethodName: String?
}

public struct WorthlyBackupArchive: Codable, Sendable {
    public let schemaVersion: String
    public let exportedAt: Date
    public let categories: [CategoryBackupDTO]
    public let accounts: [AccountBackupDTO]
    public let recurringRules: [RecurringRuleBackupDTO]
    public let transactions: [TransactionBackupDTO]
}

public struct BackupImportSummary: Sendable {
    public let categoriesRestored: Int
    public let accountsRestored: Int
    public let rulesRestored: Int
    public let transactionsRestored: Int
}

public final class BackupManager {
    public static let shared = BackupManager()
    private init() {}

    /// Escapes a CSV field according to RFC 4180
    private func escapeCSV(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }

    /// Generates an RFC 4180 CSV string for all transactions
    public func exportTransactionsCSV(transactions: [TransactionItem]) -> String {
        var lines: [String] = [
            "id,timestamp,type,amount,currency,merchant,category,paymentMethod,toPaymentMethod,isExcludedFromBudget,notes,ruleId"
        ]
        let sorted = transactions.filter { !$0.isDeleted }.sorted { $0.timestamp > $1.timestamp }
        let dateFormatter = ISO8601DateFormatter()

        for tx in sorted {
            let row = [
                tx.id.uuidString,
                dateFormatter.string(from: tx.timestamp),
                tx.type.rawValue,
                String(format: "%.2f", tx.amount),
                escapeCSV(tx.currency),
                escapeCSV(tx.merchant),
                escapeCSV(tx.category?.name ?? ""),
                escapeCSV(tx.paymentMethod?.name ?? ""),
                escapeCSV(tx.toPaymentMethod?.name ?? ""),
                tx.isExcludedFromBudget ? "true" : "false",
                escapeCSV(tx.notes),
                tx.ruleId?.uuidString ?? ""
            ].joined(separator: ",")
            lines.append(row)
        }
        return lines.joined(separator: "\n")
    }

    /// Writes the CSV export to a temporary file URL ready for ShareLink / UIActivityViewController
    public func writeCSVExportFile(transactions: [TransactionItem]) -> URL? {
        let csvString = exportTransactionsCSV(transactions: transactions)
        let dateStamp = Self.fileDateStamp()
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("Worthly_Transactions_\(dateStamp).csv")
        do {
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            AppDataStore.logger.error("Failed to write CSV export file: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Encodes the entire SwiftData store into a portable JSON archive
    public func exportJSONData(context: ModelContext) throws -> Data {
        let categories = try context.fetch(FetchDescriptor<CategoryItem>()).filter { !$0.isDeleted }
        let accounts = try context.fetch(FetchDescriptor<PaymentMethodItem>()).filter { !$0.isDeleted }
        let rules = try context.fetch(FetchDescriptor<RecurringRuleItem>()).filter { !$0.isDeleted }
        let transactions = try context.fetch(FetchDescriptor<TransactionItem>()).filter { !$0.isDeleted }

        let archive = WorthlyBackupArchive(
            schemaVersion: "1.3.0",
            exportedAt: Date(),
            categories: categories.map {
                CategoryBackupDTO(id: $0.id, name: $0.name, iconName: $0.iconName, colorHex: $0.colorHex)
            },
            accounts: accounts.map {
                AccountBackupDTO(
                    id: $0.id,
                    name: $0.name,
                    iconName: $0.iconName,
                    colorHex: $0.colorHex,
                    accountTypeRaw: $0.accountTypeRaw,
                    initialBalance: $0.initialBalance,
                    currentBalance: $0.currentBalance,
                    statementDay: $0.statementDay
                )
            },
            recurringRules: rules.map {
                RecurringRuleBackupDTO(
                    id: $0.id,
                    title: $0.title,
                    amount: $0.amount,
                    currency: $0.currency,
                    typeRaw: $0.typeRaw,
                    recurrenceFrequencyRaw: $0.recurrenceFrequencyRaw,
                    nextDueDate: $0.nextDueDate,
                    lastProcessedDate: $0.lastProcessedDate,
                    isExcludedFromBudget: $0.isExcludedFromBudget,
                    isPaused: $0.isPaused,
                    categoryName: $0.category?.name,
                    paymentMethodName: $0.paymentMethod?.name,
                    toPaymentMethodName: $0.toPaymentMethod?.name
                )
            },
            transactions: transactions.map {
                TransactionBackupDTO(
                    id: $0.id,
                    timestamp: $0.timestamp,
                    amount: $0.amount,
                    currency: $0.currency,
                    merchant: $0.merchant,
                    notes: $0.notes,
                    typeRaw: $0.typeRaw,
                    isExcludedFromBudget: $0.isExcludedFromBudget,
                    ruleId: $0.ruleId,
                    categoryName: $0.category?.name,
                    paymentMethodName: $0.paymentMethod?.name,
                    toPaymentMethodName: $0.toPaymentMethod?.name
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    /// Writes the JSON backup archive to a temporary file URL ready for sharing
    public func writeJSONBackupFile(context: ModelContext) -> URL? {
        do {
            let data = try exportJSONData(context: context)
            let dateStamp = Self.fileDateStamp()
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("Worthly_Backup_\(dateStamp).json")
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            AppDataStore.logger.error("Failed to write JSON backup file: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Restores categories, accounts, recurring rules, and transactions from a JSON backup archive (deduplicating by ID/name)
    public func importJSONData(_ data: Data, context: ModelContext) throws -> BackupImportSummary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(WorthlyBackupArchive.self, from: data)

        var existingCategories = try context.fetch(FetchDescriptor<CategoryItem>()).filter { !$0.isDeleted }
        var existingAccounts = try context.fetch(FetchDescriptor<PaymentMethodItem>()).filter { !$0.isDeleted }
        let existingRules = try context.fetch(FetchDescriptor<RecurringRuleItem>()).filter { !$0.isDeleted }
        let existingTransactions = try context.fetch(FetchDescriptor<TransactionItem>()).filter { !$0.isDeleted }

        var catCount = 0
        for dto in archive.categories {
            if !existingCategories.contains(where: { $0.id == dto.id || $0.name.localizedCaseInsensitiveCompare(dto.name) == .orderedSame }) {
                let newCat = CategoryItem(id: dto.id, name: dto.name, iconName: dto.iconName, colorHex: dto.colorHex)
                context.insert(newCat)
                existingCategories.append(newCat)
                catCount += 1
            }
        }

        var accCount = 0
        for dto in archive.accounts {
            if let existing = existingAccounts.first(where: { $0.id == dto.id || $0.name.localizedCaseInsensitiveCompare(dto.name) == .orderedSame }) {
                if existing.initialBalance == 0 && dto.initialBalance != 0 {
                    existing.initialBalance = dto.initialBalance
                }
                if existing.statementDay == nil {
                    existing.statementDay = dto.statementDay
                }
            } else {
                let newAcc = PaymentMethodItem(
                    id: dto.id,
                    name: dto.name,
                    iconName: dto.iconName,
                    colorHex: dto.colorHex,
                    accountType: AccountType(rawValue: dto.accountTypeRaw) ?? .asset,
                    initialBalance: dto.initialBalance,
                    currentBalance: dto.currentBalance,
                    statementDay: dto.statementDay
                )
                context.insert(newAcc)
                existingAccounts.append(newAcc)
                accCount += 1
            }
        }

        let existingRuleIds = Set(existingRules.map { $0.id })
        var ruleCount = 0
        for dto in archive.recurringRules where !existingRuleIds.contains(dto.id) {
            let cat = dto.categoryName.flatMap { name in existingCategories.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) }
            let pm = dto.paymentMethodName.flatMap { name in existingAccounts.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) }
            let toPm = dto.toPaymentMethodName.flatMap { name in existingAccounts.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) }

            let newRule = RecurringRuleItem(
                id: dto.id,
                title: dto.title,
                amount: dto.amount,
                currency: dto.currency,
                type: TransactionType(rawValue: dto.typeRaw) ?? .expense,
                recurrenceFrequency: RecurrenceFrequency(rawValue: dto.recurrenceFrequencyRaw) ?? .monthly,
                nextDueDate: dto.nextDueDate,
                lastProcessedDate: dto.lastProcessedDate,
                category: cat,
                paymentMethod: pm,
                toPaymentMethod: toPm,
                isExcludedFromBudget: dto.isExcludedFromBudget,
                isPaused: dto.isPaused
            )
            context.insert(newRule)
            ruleCount += 1
        }

        let existingTxIds = Set(existingTransactions.map { $0.id })
        var txCount = 0
        for dto in archive.transactions where !existingTxIds.contains(dto.id) {
            let cat = dto.categoryName.flatMap { name in existingCategories.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) }
            let pm = dto.paymentMethodName.flatMap { name in existingAccounts.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) }
            let toPm = dto.toPaymentMethodName.flatMap { name in existingAccounts.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) }

            let newTx = TransactionItem(
                id: dto.id,
                timestamp: dto.timestamp,
                amount: dto.amount,
                currency: dto.currency,
                merchant: dto.merchant,
                notes: dto.notes,
                type: TransactionType(rawValue: dto.typeRaw) ?? .expense,
                category: cat,
                paymentMethod: pm,
                toPaymentMethod: toPm,
                isExcludedFromBudget: dto.isExcludedFromBudget,
                ruleId: dto.ruleId
            )
            context.insert(newTx)
            txCount += 1
        }

        AppDataStore.saveContext(context)
        AccountBalanceManager.shared.recalculateBalances(context: context)
        WidgetSyncManager.shared.syncWidget(context: context)

        return BackupImportSummary(
            categoriesRestored: catCount,
            accountsRestored: accCount,
            rulesRestored: ruleCount,
            transactionsRestored: txCount
        )
    }

    private static func fileDateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}
