//
//  FinancialTrackerTests.swift
//  FinancialTrackerTests
//

import Foundation
import Testing
import SwiftData
@testable import FinancialTracker

struct FinancialTrackerTests {

    // MARK: - 1. Octopus Exit-Gate Notification Parsing (Fixes the HK$60.90 Balance Bug)
    @Test("Extracts HK$3.20 fare and MTR merchant while ignoring 'Your new balance is HK$60.90.'")
    func testOctopusExitGateNotificationParsing() {
        let subtitle = "HK$3.20 for Train"
        let body = "Your new balance is HK$60.90."

        let extracted = MerchantRuleEngine.extractAmountAndMerchant(
            subtitleOrMerchant: subtitle,
            bodyOrNotificationText: body
        )

        #expect(extracted.fareAmount == 3.20)
        let normalizedMerchant = MerchantRuleEngine.normalizeMerchantName(from: extracted.merchant, cardName: "Octopus")
        #expect(normalizedMerchant == "MTR")

        let category = MerchantRuleEngine.inferCategoryName(
            for: normalizedMerchant,
            rawMerchant: extracted.merchant,
            cardName: "Octopus"
        )
        #expect(category == "Octopus")
    }

    // MARK: - 2. Zero-Charge Entry-Gate / Card Read Filtering
    @Test("Detects and skips $0 entry-gate notifications ('Card Read' and 'Trip in Progress')")
    func testZeroChargeEntryGateDetection() {
        let cardReadText = "Card Read | There was no charge for this transaction. Your current balance is HK$64.10."
        let tripInProgressText = "Trip in Progress | Your current balance is HK$64.10."
        let chineseEntryText = "已讀取 | 無須收費，最新餘額為 HK$64.10"
        let realExitText = "HK$3.20 for Train | Your new balance is HK$60.90."

        #expect(MerchantRuleEngine.isZeroChargeEntryNotification(cardReadText) == true)
        #expect(MerchantRuleEngine.isZeroChargeEntryNotification(tripInProgressText) == true)
        #expect(MerchantRuleEngine.isZeroChargeEntryNotification(chineseEntryText) == true)
        #expect(MerchantRuleEngine.isZeroChargeEntryNotification(realExitText) == false)
    }

    // MARK: - 3. Traditional Chinese Octopus Notification Parsing
    @Test("Extracts fare and merchant from Traditional Chinese Octopus notifications")
    func testTraditionalChineseNotificationParsing() {
        let body = "於 港鐵 消費 HK$5.10。最新餘額為 HK$88.40。"
        let extracted = MerchantRuleEngine.extractAmountAndMerchant(
            subtitleOrMerchant: nil,
            bodyOrNotificationText: body
        )

        #expect(extracted.fareAmount == 5.10)
        let normalized = MerchantRuleEngine.normalizeMerchantName(from: extracted.merchant, cardName: "八達通")
        #expect(normalized == "MTR")
    }

    // MARK: - 4. POS Gateway Prefix Stripping & HK Merchant Categorization
    @Test("Strips POS prefixes (Bindo*, KPay*, BBMSL*) and infers accurate HK categories")
    func testPOSPrefixesAndCategoryInference() {
        // 1. Bindo*ICHICAKE -> Groceries
        let ichicake = MerchantRuleEngine.normalizeMerchantName(from: "Bindo*ICHICAKE")
        #expect(ichicake == "ICHICAKE")
        #expect(MerchantRuleEngine.inferCategoryName(for: ichicake, rawMerchant: "Bindo*ICHICAKE") == "Groceries")

        // 2. KPay*BODYBUILDING CO -> Groceries
        let bodybuilding = MerchantRuleEngine.normalizeMerchantName(from: "KPay*BODYBUILDING CO")
        #expect(bodybuilding == "BODYBUILDING CO")
        #expect(MerchantRuleEngine.inferCategoryName(for: bodybuilding, rawMerchant: "KPay*BODYBUILDING CO") == "Groceries")

        // 3. BBMSL*Sushiro Shatin Ct -> Sushiro (Dining)
        let sushiro = MerchantRuleEngine.normalizeMerchantName(from: "BBMSL*Sushiro Shatin Ct")
        #expect(sushiro == "Sushiro")
        #expect(MerchantRuleEngine.inferCategoryName(for: sushiro, rawMerchant: "BBMSL*Sushiro Shatin Ct") == "Dining")

        // 4. Fortress -> Shopping (NOT Groceries)
        let fortress = MerchantRuleEngine.normalizeMerchantName(from: "Fortress")
        #expect(fortress == "Fortress")
        #expect(MerchantRuleEngine.inferCategoryName(for: fortress) == "Shopping")

        // 5. Lung Fung Mall -> Groceries
        let lungFung = MerchantRuleEngine.normalizeMerchantName(from: "Lung Fung Mall")
        #expect(lungFung == "Lung Fung Mall")
        #expect(MerchantRuleEngine.inferCategoryName(for: lungFung) == "Groceries")
    }

    // MARK: - 5. Octopus Auto Top-Up (AAVS) Transfer Detection
    @Test("Detects Octopus AAVS reloads so they are logged as Transfers rather than Expenses")
    func testAAVSTopUpDetection() {
        #expect(MerchantRuleEngine.isAAVSTopUp(merchant: "Octopus Cards Limited", fullText: "Auto Add Value HK$250.00") == true)
        #expect(MerchantRuleEngine.isAAVSTopUp(merchant: "八達通自動增值", fullText: "HK$250.00") == true)
        #expect(MerchantRuleEngine.isAAVSTopUp(merchant: "7-Eleven", fullText: "HK$15.00 at 7-Eleven") == false)
    }

    // MARK: - 6. Fuzzy Credit Card Account Deduplication
    @Test("Matches 'Hang Seng CUHK Plat Visa' to existing 'CUHK Credit Card' via shared keyword token")
    func testFuzzyCardAccountMatching() {
        let existingAccounts = ["Octopus", "CUHK Credit Card", "Bank Transfer / FPS", "Cash"]
        let matched = MerchantRuleEngine.findMatchingAccountName(
            incomingCardName: "Hang Seng CUHK Plat Visa",
            existingNames: existingAccounts
        )
        #expect(matched == "CUHK Credit Card")
    }

    // MARK: - 7. In-Memory SwiftData Account Balance & Net Worth Recalculation
    @MainActor
    @Test("Recalculates Asset, Liability, and Net Worth accurately across Expenses and AAVS Transfers")
    func testAccountBalanceAndTransferCalculation() throws {
        let schema = Schema([
            TransactionItem.self,
            CategoryItem.self,
            PaymentMethodItem.self,
            RecurringRuleItem.self
        ])
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

        // 1. Log HKD 3.20 MTR Expense on Octopus
        let mtrRide = TransactionItem(
            amount: 3.20,
            currency: "HKD",
            merchant: "MTR",
            type: .expense,
            paymentMethod: octopus
        )
        context.insert(mtrRide)

        // 2. Log HKD 250.00 AAVS Transfer (CUHK Credit Card -> Octopus)
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

        // Octopus: 50.00 - 3.20 + 250.00 = 296.80
        #expect(abs(octopus.currentBalance - 296.80) < 0.001)
        // CUHK Credit Card: -100.00 - 250.00 = -350.00
        #expect(abs(cuhkCard.currentBalance - (-350.00)) < 0.001)

        let netWorthSummary = AccountBalanceManager.shared.calculateNetWorth(accounts: [octopus, cuhkCard])
        #expect(abs(netWorthSummary.assets - 296.80) < 0.001)
        #expect(abs(netWorthSummary.liabilities - 350.00) < 0.001)
        #expect(abs(netWorthSummary.netWorth - (-53.20)) < 0.001)
    }
}
