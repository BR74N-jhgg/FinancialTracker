//
//  FinancialTrackerTests.swift
//  FinancialTrackerTests
//

import Foundation
import Testing
import SwiftData
@testable import FinancialTracker

struct IntentParsingTests {

    // MARK: - 1. testAmountExtraction_fromSubtitle
    @Test("Extracts HK$3.20 fare and Train/MTR merchant from Notification Subtitle")
    func testAmountExtraction_fromSubtitle() {
        let extracted = MerchantRuleEngine.extractAmountAndMerchant(
            subtitleOrMerchant: "HK$3.20 for Train",
            bodyOrNotificationText: nil
        )
        #expect(extracted.fareAmount == 3.20)
        #expect(MerchantRuleEngine.normalizeMerchantName(from: extracted.merchant, cardName: "Octopus") == "MTR")
    }

    // MARK: - 2. testAmountExtraction_ignoresBalanceSentence
    @Test("Ignores 'Your new balance is HK$60.90.' in Notification Body when extracting fare")
    func testAmountExtraction_ignoresBalanceSentence() {
        let extracted = MerchantRuleEngine.extractAmountAndMerchant(
            subtitleOrMerchant: "HK$3.20 for Train",
            bodyOrNotificationText: "Your new balance is HK$60.90."
        )
        #expect(extracted.fareAmount == 3.20)

        let bodyOnlyBalance = MerchantRuleEngine.extractAmountAndMerchant(
            subtitleOrMerchant: nil,
            bodyOrNotificationText: "Your current balance is HK$64.10."
        )
        #expect(bodyOnlyBalance.fareAmount == nil)
    }

    // MARK: - 3. testZeroChargeSkip
    @Test("Skips $0 transit entry notifications like 'Card Read' and 'Trip in Progress'")
    func testZeroChargeSkip() {
        #expect(MerchantRuleEngine.isZeroChargeEntryNotification("Card Read") == true)
        #expect(MerchantRuleEngine.isZeroChargeEntryNotification("Trip in Progress - No Charge") == true)
        #expect(MerchantRuleEngine.isZeroChargeEntryNotification("HK$3.20 for Train") == false)
    }

    // MARK: - 4. testMerchantNormalization
    @Test("Normalizes POS prefixes and Hong Kong merchants cleanly")
    func testMerchantNormalization() {
        #expect(MerchantRuleEngine.normalizeMerchantName(from: "KPay*Wellcome Supermarket") == "Wellcome")
        #expect(MerchantRuleEngine.normalizeMerchantName(from: "Lung Fung Dispensary") == "Lung Fung")
        #expect(MerchantRuleEngine.normalizeMerchantName(from: "Train", cardName: "Octopus") == "MTR")
        #expect(MerchantRuleEngine.normalizeMerchantName(from: nil, cardName: "Octopus") == "Octopus")
    }

    // MARK: - 5. testCategoryInference
    @Test("Infers 100% data-driven categories across Hong Kong merchants and Octopus card fallbacks")
    func testCategoryInference() {
        #expect(MerchantRuleEngine.inferCategoryName(for: "Wellcome") == "Groceries")
        #expect(MerchantRuleEngine.inferCategoryName(for: "Lung Fung") == "Groceries")
        #expect(MerchantRuleEngine.inferCategoryName(for: "Keeta") == "Dining")
        #expect(MerchantRuleEngine.inferCategoryName(for: "Fortress") == "Shopping")
        #expect(MerchantRuleEngine.inferCategoryName(for: "MTR", cardName: "Octopus") == "Octopus")
    }

    // MARK: - 6. testAAVSDetection & Credit Card Selection Priority
    @Test("Detects Octopus AAVS reloads and selects funding credit card using 4-tier priority")
    func testAAVSDetection() {
        #expect(MerchantRuleEngine.isAAVSTopUp(merchant: "Octopus Cards Limited", fullText: "Auto Add Value HK$250.00") == true)
        #expect(MerchantRuleEngine.isAAVSTopUp(merchant: "八達通自動增值", fullText: "HK$250.00") == true)
        #expect(MerchantRuleEngine.isAAVSTopUp(merchant: "7-Eleven", fullText: "HK$15.00 at 7-Eleven") == false)

        let octopus = PaymentMethodItem(name: "Octopus", accountType: .asset)
        let hsbcRed = PaymentMethodItem(name: "HSBC Red Card", accountType: .liability)
        let cuhkCard = PaymentMethodItem(name: "CUHK Credit Card", accountType: .liability)
        let methods = [octopus, hsbcRed, cuhkCard]

        // Priority 1: Respects user's default payment method when it is a liability
        let selectedDefault = AutoLogWalletPaymentIntent.selectFundingCreditCard(
            from: methods,
            defaultMethodName: "HSBC Red Card"
        )
        #expect(selectedDefault?.name == "HSBC Red Card")

        // Priority 2: If default is an asset (Octopus), picks the first Credit/Card account
        let selectedFallback = AutoLogWalletPaymentIntent.selectFundingCreditCard(
            from: methods,
            defaultMethodName: "Octopus"
        )
        #expect(selectedFallback?.name == "HSBC Red Card")
    }

    // MARK: - 7. In-Memory SwiftData Account Balance & Net Worth Recalculation
    @MainActor
    @Test("Recalculates Asset, Liability, and Net Worth accurately across Expenses and AAVS Transfers")
    func testAccountBalanceAndTransferCalculation() throws {
        let schema = Schema(versionedSchema: WorthlySchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let octopus = PaymentMethodItem(
            name: "Octopus",
            iconName: "wave.3.forward.circle.fill",
            colorHex: "#FF9500",
            accountType: .asset,
            initialBalance: 50.0
        )
        let cuhkCard = PaymentMethodItem(
            name: "CUHK Credit Card",
            iconName: "creditcard.fill",
            colorHex: "#007AFF",
            accountType: .liability,
            initialBalance: -100.0
        )
        context.insert(octopus)
        context.insert(cuhkCard)

        let mtrRide = TransactionItem(
            amount: 3.20,
            currency: "HKD",
            merchant: "MTR",
            type: .expense,
            paymentMethod: octopus
        )
        context.insert(mtrRide)

        let aavsTopUp = TransactionItem(
            amount: 250.00,
            currency: "HKD",
            merchant: "Octopus Auto Top-Up (AAVS)",
            type: .transfer,
            paymentMethod: cuhkCard,
            toPaymentMethod: octopus
        )
        context.insert(aavsTopUp)

        AccountBalanceManager.shared.recalculateBalances(context: context)

        #expect(abs(octopus.currentBalance - 296.80) < 0.001)
        #expect(abs(cuhkCard.currentBalance - (-350.00)) < 0.001)

        let netWorthSummary = AccountBalanceManager.shared.calculateNetWorth(accounts: [octopus, cuhkCard])
        #expect(abs(netWorthSummary.assets - 296.80) < 0.001)
        #expect(abs(netWorthSummary.liabilities - 350.00) < 0.001)
        #expect(abs(netWorthSummary.netWorth - (-53.20)) < 0.001)
    }

    // MARK: - 8. Phase 1: RecurringPaymentManager Catch-Up, 12-Cap, Pause & ruleId Linking
    @MainActor
    @Test("Processes due recurring rules with ruleId linking and respects isPaused and 12-item cap")
    func testRecurringPaymentsCatchUpAndPause() throws {
        let schema = Schema(versionedSchema: WorthlySchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let card = PaymentMethodItem(name: "HSBC Red Card", accountType: .liability, initialBalance: 0.0)
        context.insert(card)

        let now = Date()
        let twoMonthsAgo = Calendar.current.date(byAdding: .month, value: -2, to: now)!

        let activeRule = RecurringRuleItem(
            title: "Netflix",
            amount: 93.0,
            currency: "HKD",
            type: .expense,
            recurrenceFrequency: .monthly,
            nextDueDate: twoMonthsAgo,
            paymentMethod: card,
            isPaused: false
        )
        let pausedRule = RecurringRuleItem(
            title: "Paused Gym",
            amount: 500.0,
            currency: "HKD",
            type: .expense,
            recurrenceFrequency: .monthly,
            nextDueDate: twoMonthsAgo,
            paymentMethod: card,
            isPaused: true
        )
        context.insert(activeRule)
        context.insert(pausedRule)

        RecurringPaymentManager.shared.processDueRecurringPayments(context: context, referenceDate: now)

        let generated = try context.fetch(FetchDescriptor<TransactionItem>())
        // twoMonthsAgo (-2m), -1m, and 0m (now) => 3 transactions for activeRule, 0 for pausedRule
        #expect(generated.count == 3)
        #expect(generated.allSatisfy { $0.ruleId == activeRule.id && $0.merchant == "Netflix" })
        #expect(activeRule.nextDueDate > now)
        #expect(abs(card.currentBalance - (-279.0)) < 0.001)

        // Verify that editing an older generated transaction preserves future nextDueDate (no rewind)
        let savedFutureDue = activeRule.nextDueDate
        let oldestTx = generated.min(by: { $0.timestamp < $1.timestamp })!
        let candidateDue = Calendar.current.date(byAdding: .month, value: 1, to: oldestTx.timestamp)!
        activeRule.nextDueDate = max(activeRule.nextDueDate, candidateDue)
        RecurringPaymentManager.shared.processDueRecurringPayments(context: context, referenceDate: now)
        let afterEditCount = try context.fetch(FetchDescriptor<TransactionItem>()).count
        #expect(activeRule.nextDueDate == savedFutureDue)
        #expect(afterEditCount == 3)
    }

    // MARK: - 9. Phase 1: CSV Export & JSON Full Backup / Restore Round-Trip
    @MainActor
    @Test("Exports valid RFC 4180 CSV and performs lossless JSON backup/restore round-trip")
    func testBackupJSONRoundTripAndCSVExport() throws {
        let schema = Schema(versionedSchema: WorthlySchemaV1.self)
        let config1 = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container1 = try ModelContainer(for: schema, configurations: [config1])
        let context1 = container1.mainContext

        let dining = CategoryItem(name: "Dining", iconName: "fork.knife", colorHex: "#FF9500")
        let octopus = PaymentMethodItem(name: "Octopus", accountType: .asset, initialBalance: 100.0)
        context1.insert(dining)
        context1.insert(octopus)

        let rule = RecurringRuleItem(
            title: "iCloud+",
            amount: 23.0,
            currency: "HKD",
            type: .expense,
            recurrenceFrequency: .monthly,
            category: dining,
            paymentMethod: octopus
        )
        context1.insert(rule)

        let tx = TransactionItem(
            amount: 45.50,
            currency: "HKD",
            merchant: "TamJai, Central",
            notes: "Spicy soup",
            type: .expense,
            category: dining,
            paymentMethod: octopus,
            ruleId: rule.id
        )
        context1.insert(tx)
        AppDataStore.saveContext(context1)

        // 1. Verify CSV Export escapes commas in merchant name
        let csv = BackupManager.shared.exportTransactionsCSV(transactions: [tx])
        #expect(csv.contains("\"TamJai, Central\""))
        #expect(csv.contains("45.50"))

        // 2. Verify JSON Export & Restore into a brand-new container
        let jsonData = try BackupManager.shared.exportJSONData(context: context1)

        let config2 = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container2 = try ModelContainer(for: schema, configurations: [config2])
        let context2 = container2.mainContext

        let summary = try BackupManager.shared.importJSONData(jsonData, context: context2)
        #expect(summary.categoriesRestored == 1)
        #expect(summary.accountsRestored == 1)
        #expect(summary.rulesRestored == 1)
        #expect(summary.transactionsRestored == 1)

        let restoredAccounts = try context2.fetch(FetchDescriptor<PaymentMethodItem>())
        #expect(abs((restoredAccounts.first?.currentBalance ?? 0.0) - 54.50) < 0.001)
    }
}
