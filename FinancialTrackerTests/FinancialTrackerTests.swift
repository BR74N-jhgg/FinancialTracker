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
    @Test("Detects and skips $0 entry-gate notifications ('Card Read' and 'Trip in Progress')")
    func testZeroChargeSkip() {
        let cardReadText = "Card Read | There was no charge for this transaction. Your current balance is HK$64.10."
        let tripInProgressText = "Trip in Progress | Your current balance is HK$64.10."
        let chineseEntryText = "已讀取 | 無須收費，最新餘額為 HK$64.10"
        let realExitText = "HK$3.20 for Train | Your new balance is HK$60.90."

        #expect(MerchantRuleEngine.isZeroChargeEntryNotification(cardReadText) == true)
        #expect(MerchantRuleEngine.isZeroChargeEntryNotification(tripInProgressText) == true)
        #expect(MerchantRuleEngine.isZeroChargeEntryNotification(chineseEntryText) == true)
        #expect(MerchantRuleEngine.isZeroChargeEntryNotification(realExitText) == false)
    }

    // MARK: - 4. testMerchantNormalization_MTR
    @Test("Normalizes English and Traditional Chinese transit & POS merchant names")
    func testMerchantNormalization_MTR() {
        #expect(MerchantRuleEngine.normalizeMerchantName(from: "Train", cardName: "Octopus") == "MTR")
        #expect(MerchantRuleEngine.normalizeMerchantName(from: "港鐵", cardName: "八達通") == "MTR")
        #expect(MerchantRuleEngine.normalizeMerchantName(from: "BBMSL*Sushiro Shatin Ct") == "Sushiro")
        #expect(MerchantRuleEngine.normalizeMerchantName(from: "Bindo*ICHICAKE") == "ICHICAKE")
        #expect(MerchantRuleEngine.normalizeMerchantName(from: "KPay*BODYBUILDING CO") == "BODYBUILDING CO")
    }

    // MARK: - 5. testCategoryInference_Dining & Data-Driven Rules
    @Test("Infers Dining, Groceries, Shopping, and Octopus categories from data-driven categoryRules")
    func testCategoryInference_Dining() {
        #expect(MerchantRuleEngine.inferCategoryName(for: "Sushiro", rawMerchant: "BBMSL*Sushiro Shatin Ct") == "Dining")
        #expect(MerchantRuleEngine.inferCategoryName(for: "Starbucks") == "Dining")
        #expect(MerchantRuleEngine.inferCategoryName(for: "7-Eleven", cardName: "Octopus") == "Groceries")
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
}
