//
//  FinancialIntents.swift
//  Worthly
//

import Foundation
import AppIntents
import SwiftData
import os

// MARK: - Zero-Touch Wallet, Travel Card & Notification Auto-Logging Intent
public struct AutoLogWalletPaymentIntent: AppIntent {
    public static var title: LocalizedStringResource = "Auto-Log Wallet & Travel Card"
    public static var description = IntentDescription("Automatically logs Wallet, Express Transit, and Notification transactions in the background with smart amount extraction, merchant categorization, and card matching.")
    public static var openAppWhenRun: Bool = false
    public static var isDiscoverable: Bool = true

    @Parameter(
        title: "Amount",
        description: "Transaction amount (leave blank when using Notification trigger to auto-extract from Notification Text)"
    )
    public var amount: Double?

    @Parameter(
        title: "Notification or Raw Text",
        description: "Pass Notification Body (or Subtitle) from the Notification Automation trigger to automatically extract the exact dynamic Octopus / card amount and merchant"
    )
    public var notificationText: String?

    @Parameter(
        title: "Merchant",
        description: "Merchant name from the transaction or Notification Subtitle (e.g. 'HK$3.20 for Train')"
    )
    public var merchant: String?

    @Parameter(
        title: "Card or Pass",
        description: "Pass 'Card or Pass' or Notification Title (e.g. Octopus, CUHK Credit Card)"
    )
    public var cardOrPassName: String?

    @Parameter(
        title: "Category",
        description: "Optional category override. If omitted, Worthly auto-categorizes based on merchant and card."
    )
    public var categoryName: String?

    @Parameter(
        title: "Notes",
        description: "Optional notes (defaults to 'Auto-logged transaction')"
    )
    public var notes: String?

    public init() {}

    public init(
        amount: Double? = nil,
        notificationText: String? = nil,
        merchant: String? = nil,
        cardOrPassName: String? = nil,
        categoryName: String? = nil,
        notes: String? = nil
    ) {
        self.amount = amount
        self.notificationText = notificationText
        self.merchant = merchant
        self.cardOrPassName = cardOrPassName
        self.categoryName = categoryName
        self.notes = notes
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let container = AppDataStore.sharedModelContainer
        let context = container.mainContext
        let currency = UserDefaults.standard.string(forKey: "default_currency") ?? "HKD"

        // 1. Single Upfront Fetch of Accounts and Categories
        let existingMethods: [PaymentMethodItem]
        do {
            existingMethods = try context.fetch(FetchDescriptor<PaymentMethodItem>())
        } catch {
            AppDataStore.logger.error("AutoLogWalletPaymentIntent failed to fetch PaymentMethodItem: \(error.localizedDescription, privacy: .public)")
            existingMethods = []
        }

        let existingCategories: [CategoryItem]
        do {
            existingCategories = try context.fetch(FetchDescriptor<CategoryItem>())
        } catch {
            AppDataStore.logger.error("AutoLogWalletPaymentIntent failed to fetch CategoryItem: \(error.localizedDescription, privacy: .public)")
            existingCategories = []
        }

        let combinedAllText = [merchant, notificationText, notes, cardOrPassName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")

        // 2. Ignore $0 Entry-Gate / Card Read notifications
        if (amount == nil || amount == 0) && MerchantRuleEngine.isZeroChargeEntryNotification(combinedAllText) {
            return .result(value: "Skipped: Entry gate / Card Read notification with no charge.")
        }

        let extracted = MerchantRuleEngine.extractAmountAndMerchant(
            subtitleOrMerchant: merchant,
            bodyOrNotificationText: notificationText,
            notesText: notes
        )

        let resolvedAmount: Double? = {
            if let explicitAmt = amount, abs(explicitAmt) > 0 {
                return abs(explicitAmt)
            }
            if let parsedAmt = extracted.fareAmount, parsedAmt > 0 {
                return parsedAmt
            }
            return nil
        }()

        guard let positiveAmount = resolvedAmount, positiveAmount > 0 else {
            return .result(value: "Skipped: No transaction fare detected in tap or notification.")
        }

        let effectiveRawMerchant = extracted.merchant ?? merchant

        // 3. AAVS / Auto Top-Up
        if MerchantRuleEngine.isAAVSTopUp(merchant: effectiveRawMerchant, fullText: combinedAllText) {
            let summary = handleAAVSTopUp(
                amount: positiveAmount,
                currency: currency,
                existingMethods: existingMethods,
                in: context
            )
            return .result(value: summary)
        }

        // 4. Standard Expense Flow
        let resolvedPaymentMethod = resolvePaymentMethod(
            cardOrPass: cardOrPassName ?? notificationText,
            merchantHint: effectiveRawMerchant,
            existingMethods: existingMethods,
            in: context
        )

        let effectiveCardName: String? = {
            if let rawCard = cardOrPassName?.trimmingCharacters(in: .whitespacesAndNewlines), !rawCard.isEmpty {
                return rawCard
            }
            return resolvedPaymentMethod?.name
        }()

        let resolvedMerchant = MerchantRuleEngine.normalizeMerchantName(from: effectiveRawMerchant, cardName: effectiveCardName)

        let resolvedCategory = resolveCategory(
            for: resolvedMerchant,
            rawMerchant: effectiveRawMerchant,
            cardName: effectiveCardName,
            explicitCategory: categoryName,
            existingCategories: existingCategories,
            in: context
        )

        let finalNotes = resolveNotes(merchant: resolvedMerchant, paymentMethod: resolvedPaymentMethod)

        let transaction = TransactionItem(
            timestamp: Date(),
            amount: positiveAmount,
            currency: currency,
            merchant: resolvedMerchant,
            notes: finalNotes,
            type: .expense,
            category: resolvedCategory,
            paymentMethod: resolvedPaymentMethod,
            isExcludedFromBudget: false
        )

        context.insert(transaction)
        AppDataStore.saveContext(context)

        RecurringPaymentManager.shared.processDueRecurringPayments(context: context)

        // 修正：用 Set 而唔係 Array
        if let pmId = resolvedPaymentMethod?.id {
            AccountBalanceManager.shared.recalculateBalances(forAccountIds: Set([pmId]), context: context)
        } else {
            AccountBalanceManager.shared.recalculateBalances(context: context)
        }
        WidgetSyncManager.shared.syncWidget(context: context)

        let methodName = resolvedPaymentMethod?.name ?? "Octopus"
        let summary = String(
            format: "Logged %@ %.2f at %@ (%@) via %@",
            currency,
            positiveAmount,
            resolvedMerchant,
            resolvedCategory?.name ?? "Octopus",
            methodName
        )
        return .result(value: summary)
    }

    // MARK: - AAVS Top-Up Handler
    @MainActor
    private func handleAAVSTopUp(
        amount: Double,
        currency: String,
        existingMethods: [PaymentMethodItem],
        in context: ModelContext
    ) -> String {
        let defaultMethodName = UserDefaults.standard.string(forKey: "default_payment_method") ?? "Credit Card"
        let creditCardAccount = Self.selectFundingCreditCard(
            from: existingMethods,
            defaultMethodName: defaultMethodName
        )
        let octopusAccount = existingMethods.first(where: {
            $0.name.localizedCaseInsensitiveContains("Octopus") || $0.name.localizedCaseInsensitiveContains("八達通")
        })

        let topUpTx = TransactionItem(
            timestamp: Date(),
            amount: amount,
            currency: currency,
            merchant: "Octopus Auto Top-Up (AAVS)",
            notes: "Auto-logged AAVS Reload",
            type: .transfer,
            category: nil,
            paymentMethod: creditCardAccount,
            toPaymentMethod: octopusAccount,
            isExcludedFromBudget: false
        )
        context.insert(topUpTx)
        AppDataStore.saveContext(context)

        RecurringPaymentManager.shared.processDueRecurringPayments(context: context)

        let affectedIds = Set([creditCardAccount?.id, octopusAccount?.id].compactMap { $0 })
        if !affectedIds.isEmpty {
            AccountBalanceManager.shared.recalculateBalances(forAccountIds: affectedIds, context: context)
        } else {
            AccountBalanceManager.shared.recalculateBalances(context: context)
        }
        WidgetSyncManager.shared.syncWidget(context: context)

        return String(
            format: "Logged Transfer %@ %.2f: %@ → Octopus",
            currency,
            amount,
            creditCardAccount?.name ?? "Credit Card"
        )
    }

    /// 4-tier priority for funding credit card
    public static func selectFundingCreditCard(
        from existingMethods: [PaymentMethodItem],
        defaultMethodName: String
    ) -> PaymentMethodItem? {
        // 1. User's default payment method if it is a liability
        if !defaultMethodName.isEmpty,
           let defaultLiability = existingMethods.first(where: {
               $0.isLiability &&
               ($0.name.localizedCaseInsensitiveCompare(defaultMethodName) == .orderedSame ||
                $0.name.localizedCaseInsensitiveContains(defaultMethodName))
           }) {
            return defaultLiability
        }

        // 2. Account whose name contains "Credit" or "Card"
        if let namedCard = existingMethods.first(where: {
            $0.name.localizedCaseInsensitiveContains("Credit") ||
            $0.name.localizedCaseInsensitiveContains("Card") ||
            $0.name.localizedCaseInsensitiveContains("信用卡")
        }) {
            return namedCard
        }

        // 3. Any liability account
        if let anyLiability = existingMethods.first(where: { $0.isLiability }) {
            return anyLiability
        }

        // 4. Fallback
        return existingMethods.first
    }

    private func resolveNotes(merchant: String, paymentMethod: PaymentMethodItem?) -> String {
        if let custom = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom
        }
        if let pm = paymentMethod {
            return "Auto-logged via \(pm.name)"
        }
        return "Auto-logged via Wallet"
    }

    // MARK: - Category Resolver
    @MainActor
    private func resolveCategory(
        for merchant: String,
        rawMerchant: String?,
        cardName: String?,
        explicitCategory: String?,
        existingCategories: [CategoryItem],
        in context: ModelContext
    ) -> CategoryItem? {
        if let explicit = explicitCategory?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            if let matched = existingCategories.first(where: { $0.name.localizedCaseInsensitiveContains(explicit) }) {
                return matched
            }
        }

        let inferredName = MerchantRuleEngine.inferCategoryName(for: merchant, rawMerchant: rawMerchant, cardName: cardName)

        if let matched = existingCategories.first(where: {
            $0.name.localizedCaseInsensitiveCompare(inferredName) == .orderedSame ||
            $0.name.localizedCaseInsensitiveContains(inferredName)
        }) {
            return matched
        }

        if inferredName == "Groceries",
           let shoppingCat = existingCategories.first(where: { $0.name.localizedCaseInsensitiveContains("Shopping") }) {
            return shoppingCat
        }

        let newCategory = CategoryItem(
            name: inferredName,
            iconName: MerchantRuleEngine.iconForCategory(inferredName),
            colorHex: MerchantRuleEngine.colorForCategory(inferredName)
        )
        context.insert(newCategory)
        return newCategory
    }

    // MARK: - Payment Method Resolver
    @MainActor
    private func resolvePaymentMethod(
        cardOrPass: String?,
        merchantHint: String?,
        existingMethods: [PaymentMethodItem],
        in context: ModelContext
    ) -> PaymentMethodItem? {
        let rawMerch = merchantHint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawCard = cardOrPass?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let lowerMerch = rawMerch.lowercased()
        let lowerCard = rawCard.lowercased()
        let isBlankMerchantOctopusTap = (rawMerch.isEmpty || lowerMerch == "wallet purchase") && (rawCard.isEmpty || lowerCard.contains("octopus") || lowerCard.contains("八達通"))
        let isExplicitOctopusMerchant = lowerCard.contains("octopus") || lowerCard.contains("八達通") ||
                                        lowerMerch.contains("train") || lowerMerch.contains("mtr") || lowerMerch.contains("kmb") ||
                                        lowerMerch.contains("citybus") || lowerMerch.contains("octopus") ||
                                        lowerMerch.contains("lung fung") || lowerMerch.contains("龍豐") ||
                                        lowerMerch.contains("港鐵") || lowerMerch.contains("九巴") || lowerMerch.contains("八達通")

        if isBlankMerchantOctopusTap || isExplicitOctopusMerchant {
            if let octopusAccount = existingMethods.first(where: {
                $0.name.localizedCaseInsensitiveContains("Octopus") || $0.name.localizedCaseInsensitiveContains("八達通")
            }) {
                return octopusAccount
            }
            let newOctopus = PaymentMethodItem(
                name: "Octopus",
                iconName: "wave.3.forward.circle.fill",
                colorHex: "#FF9500",
                accountType: .asset,
                initialBalance: 0.0
            )
            context.insert(newOctopus)
            return newOctopus
        }

        if !rawCard.isEmpty {
            let existingNames = existingMethods.map { $0.name }
            if let matchedName = MerchantRuleEngine.findMatchingAccountName(incomingCardName: rawCard, existingNames: existingNames),
               let matchedMethod = existingMethods.first(where: { $0.name == matchedName }) {
                return matchedMethod
            }

            let isTransit = lowerCard.contains("octopus") || lowerCard.contains("八達通") ||
                            lowerCard.contains("suica") || lowerCard.contains("pasmo") ||
                            lowerCard.contains("icoca") || lowerCard.contains("transit")

            let newMethod = PaymentMethodItem(
                name: rawCard,
                iconName: isTransit ? "wave.3.forward.circle.fill" : "creditcard.fill",
                colorHex: isTransit ? "#FF9500" : "#007AFF",
                accountType: isTransit ? .asset : .liability,
                initialBalance: 0.0
            )
            context.insert(newMethod)
            return newMethod
        }

        let defaultName = UserDefaults.standard.string(forKey: "default_payment_method") ?? "Credit Card"
        if let defaultMatch = existingMethods.first(where: {
            $0.name.localizedCaseInsensitiveCompare(defaultName) == .orderedSame ||
            $0.name.localizedCaseInsensitiveContains(defaultName)
        }) {
            return defaultMatch
        }

        if let cardMatch = existingMethods.first(where: { $0.isLiability || $0.name.localizedCaseInsensitiveContains("Card") }) {
            return cardMatch
        }

        return existingMethods.first
    }
}

// MARK: - App Shortcuts Provider
public struct FinancialShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AutoLogWalletPaymentIntent(),
            phrases: [
                "Auto-log payment in \(.applicationName)",
                "Auto-log card payment in \(.applicationName)",
                "Log card spend in \(.applicationName)"
            ],
            shortTitle: "Auto-Log Wallet & Travel Card",
            systemImageName: "wallet.pass.fill"
        )
    }
}
