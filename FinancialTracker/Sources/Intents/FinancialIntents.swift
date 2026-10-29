import Foundation
import AppIntents
import SwiftData

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

    // MARK: - Static Regex (compile once)
    private static let currencyRegex = try! NSRegularExpression(
        pattern: #"(?:HK\$|HKD|US\$|USD|\$|¥|£|€)\s*([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)"#,
        options: .caseInsensitive
    )

    private static let decimalRegex = try! NSRegularExpression(
        pattern: #"(?<![0-9])([0-9]+(?:\.[0-9]{1,2}))(?![0-9])"#
    )

    private static let balancePatterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"your\s+(?:new|current|remaining)?\s*balance\s+is\s*(?:HK\$|HKD|US\$|USD|\$|¥|£|€)?\s*[0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?\.?"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"balance\s*(?:is|:)\s*(?:HK\$|HKD|US\$|USD|\$|¥|£|€)?\s*[0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?\.?"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"(?:最新|當前|剩餘)?餘額(?:為|是|:|：)?\s*(?:HK\$|HKD|\$)?\s*[0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?\.?"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"there\s+was\s+no\s+charge\s+for\s+this\s+transaction\.?"#, options: .caseInsensitive)
    ]

    private static let merchantExtractionPatterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"(?:for|at|to|in|from|•)\s+([A-Za-z0-9\*\s&\.'\-_]+)"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"於\s*([^\s]+)\s*(?:消費|付款|扣除)"#, options: .caseInsensitive)
    ]

    // MARK: - Data-driven Mappings
    private static let merchantNormalizations: [(keywords: [String], name: String)] = [
        (["train", "mtr", "港鐵"], "MTR"),
        (["bus", "kmb", "九巴"], "KMB"),
        (["citybus", "城巴", "nwfb", "新巴"], "Citybus"),
        (["starbucks"], "Starbucks"),
        (["mcdonald", "mcd"], "McDonald's"),
        (["7-eleven", "7 eleven", "seven eleven"], "7-Eleven"),
        (["circle k", "ok便利店"], "Circle K"),
        (["wellcome", "惠康"], "Wellcome"),
        (["parknshop", "百佳"], "PARKnSHOP"),
        (["mannings", "萬寧"], "Mannings"),
        (["watsons", "屈臣氏"], "Watsons"),
        (["lung fung", "龍豐"], "Lung Fung Mall"),
        (["don don donki", "donki"], "Don Don Donki"),
        (["clp", "中電"], "CLP Power"),
        (["towngas", "煤氣"], "Towngas")
    ]

    private static let categoryRules: [(keywords: [String], category: String)] = [
        (["fortress", "豐澤", "broadway", "百老滙", "log-on", "誠品", "eslite", "apple store",
          "nike", "adidas", "lululemon", "taobao", "淘寶", "amazon", "uniqlo", "zara", "muji"], "Shopping"),
        (["starbucks", "mcdonald", "kfc", "pacific coffee", "fairwood", "cafe de coral", "maxim", "sushiro",
          "genki", "tamjai", "samgor", "pizza hut", "subway", "bakehouse", "shake shack", "cha chaan teng",
          "canteen", "coffee", "cafe", "restaurant",
          "大快活", "大家樂", "美心", "壽司郎", "元氣", "譚仔", "三哥", "茶餐廳", "酒樓", "餐廳"], "Dining"),
        (["wellcome", "parknshop", "fusion", "marketplace", "city'super", "donki", "don don donki",
          "aeon", "yata", "759", "7-eleven", "7 eleven", "circle k", "lung fung", "龍豐",
          "ichicake", "cake", "bake", "bodybuilding", "kpay*", "bindo*", "mall", "mart", "store",
          "mannings", "watsons", "惠康", "百佳", "一田", "阿信屋", "便利店", "超市", "萬寧", "屈臣氏"], "Groceries"),
        (["clp", "towngas", "hkelectric", "autotoll", "water supplies", "hkbn", "pccw", "smartone", "csl", "3hk", "cmhk", "broadband",
          "中電", "港燈", "煤氣", "水費", "香港寬頻", "電訊盈科"], "Bills & Utilities"),
        (["netflix", "spotify", "apple.com/bill", "itunes", "icloud", "youtube", "disney",
          "mcl", "golden harvest", "cinema", "steam", "playstation", "nintendo"], "Entertainment"),
        (["panadol", "clinic", "hospital", "dental", "pharmacy", "gym", "fitness",
          "診所", "醫院", "藥房"], "Health & Fitness"),
        (["star ferry", "taxi", "uber", "tunnel", "hketoll", "peak tram", "light rail", "green minibus", "red minibus",
          "suica", "pasmo", "icoca", "transit", "天星小輪", "的士", "電車", "輕鐵", "小巴"], "Transport")
    ]

    private static let posPrefixes = ["bbmsl*", "bindo*", "kpay*", "eftpay*", "shopy*", "qf*", "sq *", "sq*", "sp *", "sp*", "paypal *", "paypal*"]
    private static let zeroChargeKeywords = ["card read", "trip in progress", "no charge for this transaction", "there was no charge", "無須收費", "行程進行中", "已讀取"]
    private static let aavsKeywords = ["octopus cards", "aavs", "top up", "top-up", "自動增值", "八達通增值", "octopus reload", "auto add value"]

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let container = AppDataStore.sharedModelContainer
        let context = container.mainContext
        let currency = UserDefaults.standard.string(forKey: "default_currency") ?? "HKD"

        let combinedAllText = [merchant, notificationText, notes, cardOrPassName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
        let lowerAll = combinedAllText.lowercased()

        // 0. Skip zero-charge / entry-gate notifications
        if shouldSkipZeroCharge(amount: amount, lowerText: lowerAll) {
            return .result(value: "Skipped: Entry gate / Card Read notification with no charge.")
        }

        let extracted = extractAmountAndMerchant(
            subtitleOrMerchant: merchant,
            bodyOrNotificationText: notificationText,
            notesText: notes
        )

        let positiveAmount = resolveFinalAmount(explicit: amount, parsed: extracted.fareAmount)
        guard let amount = positiveAmount, amount > 0 else {
            return .result(value: "Skipped: No transaction fare detected in tap or notification.")
        }

        let effectiveRawMerchant = extracted.merchant ?? merchant
        let rawMerchLower = (effectiveRawMerchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // 1. AAVS / Auto Top-Up
        if isAAVSTopUp(rawMerchLower: rawMerchLower, lowerAll: lowerAll) {
            let summary = try handleAAVSTopUp(
                amount: amount,
                currency: currency,
                context: context
            )
            return .result(value: summary)
        }

        // 2. Standard Expense
        let resolvedPaymentMethod = resolvePaymentMethod(
            cardOrPass: cardOrPassName ?? notificationText,
            merchantHint: effectiveRawMerchant,
            in: context
        )

        let effectiveCardName: String? = {
            if let rawCard = cardOrPassName?.trimmingCharacters(in: .whitespacesAndNewlines), !rawCard.isEmpty {
                return rawCard
            }
            return resolvedPaymentMethod?.name
        }()

        let resolvedMerchant = resolveMerchantName(from: effectiveRawMerchant, cardName: effectiveCardName)
        let resolvedCategory = resolveCategory(
            for: resolvedMerchant,
            rawMerchant: effectiveRawMerchant,
            cardName: effectiveCardName,
            explicitCategory: categoryName,
            in: context
        )
        let finalNotes = resolveNotes(merchant: resolvedMerchant, paymentMethod: resolvedPaymentMethod)

        let transaction = TransactionItem(
            timestamp: Date(),
            amount: amount,
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

        var affectedIds = Set<UUID>()
        if let id = resolvedPaymentMethod?.id {
            affectedIds.insert(id)
        }
        postSaveHooks(context: context, affectedAccountIds: affectedIds)

        let methodName = resolvedPaymentMethod?.name ?? "Octopus"
        let summary = String(
            format: "Logged %@ %.2f at %@ (%@) via %@",
            currency,
            amount,
            resolvedMerchant,
            resolvedCategory?.name ?? "Octopus",
            methodName
        )
        return .result(value: summary)
    }

    // MARK: - Skip Zero Charge
    private func shouldSkipZeroCharge(amount: Double?, lowerText: String) -> Bool {
        let isZero = amount == nil || amount == 0
        guard isZero else { return false }
        return Self.zeroChargeKeywords.contains { lowerText.contains($0) }
    }

    // MARK: - Final Amount Resolution
    private func resolveFinalAmount(explicit: Double?, parsed: Double?) -> Double? {
        if let explicitAmt = explicit, abs(explicitAmt) > 0 {
            return abs(explicitAmt)
        }
        if let parsedAmt = parsed, parsedAmt > 0 {
            return parsedAmt
        }
        return nil
    }

    // MARK: - AAVS Detection & Handling
    private func isAAVSTopUp(rawMerchLower: String, lowerAll: String) -> Bool {
        Self.aavsKeywords.contains { rawMerchLower.contains($0) || lowerAll.contains($0) }
    }

    @MainActor
    private func handleAAVSTopUp(
        amount: Double,
        currency: String,
        context: ModelContext
    ) throws -> String {
        let allMethods = (try? context.fetch(FetchDescriptor<PaymentMethodItem>())) ?? []
        let octopusAccount = allMethods.first {
            $0.name.localizedCaseInsensitiveContains("Octopus") || $0.name.localizedCaseInsensitiveContains("八達通")
        }
        let creditCardAccount = allMethods.first {
            $0.name == "CUHK Credit Card" || $0.name.localizedCaseInsensitiveContains("CUHK") || $0.isLiability
        } ?? allMethods.first

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

        // 只重算受影響的帳戶
        var affectedIds = Set<UUID>()
        if let id = creditCardAccount?.id { affectedIds.insert(id) }
        if let id = octopusAccount?.id { affectedIds.insert(id) }

        postSaveHooks(context: context, affectedAccountIds: affectedIds)

        return String(
            format: "Logged Transfer %@ %.2f: %@ → Octopus",
            currency,
            amount,
            creditCardAccount?.name ?? "Credit Card"
        )
    }

    // MARK: - Post-Save Hooks
    @MainActor
    private func postSaveHooks(
        context: ModelContext,
        affectedAccountIds: Set<UUID> = []
    ) {
        RecurringPaymentManager.shared.processDueRecurringPayments(context: context)

        if affectedAccountIds.isEmpty {
            AccountBalanceManager.shared.recalculateBalances(context: context)
        } else {
            AccountBalanceManager.shared.recalculateBalances(
                forAccountIds: affectedAccountIds,
                context: context
            )
        }

        WidgetSyncManager.shared.syncWidget(context: context)
    }

    // MARK: - Smart Notification Fare & Merchant Parser
    private func stripBalanceSentences(_ text: String) -> String {
        var result = text
        for regex in Self.balancePatterns {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractAmountAndMerchant(
        subtitleOrMerchant: String?,
        bodyOrNotificationText: String?,
        notesText: String?
    ) -> (fareAmount: Double?, merchant: String?) {
        let rawSources = [subtitleOrMerchant, bodyOrNotificationText, notesText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let cleanedSources = rawSources
            .map { stripBalanceSentences($0) }
            .filter { !$0.isEmpty }

        let combinedCleaned = cleanedSources.joined(separator: " | ")
        guard !combinedCleaned.isEmpty else { return (nil, nil) }

        var detectedAmount: Double? = nil

        if let match = Self.currencyRegex.firstMatch(
            in: combinedCleaned,
            range: NSRange(combinedCleaned.startIndex..., in: combinedCleaned)
        ),
           let numRange = Range(match.range(at: 1), in: combinedCleaned) {
            let numStr = combinedCleaned[numRange].replacingOccurrences(of: ",", with: "")
            detectedAmount = Double(numStr)
        }

        if detectedAmount == nil,
           let match = Self.decimalRegex.firstMatch(
            in: combinedCleaned,
            range: NSRange(combinedCleaned.startIndex..., in: combinedCleaned)
           ),
           let numRange = Range(match.range(at: 1), in: combinedCleaned) {
            detectedAmount = Double(combinedCleaned[numRange])
        }

        // Prefer clean subtitle as merchant when it has no currency
        if let exp = subtitleOrMerchant?.trimmingCharacters(in: .whitespacesAndNewlines),
           !exp.isEmpty {
            let cleanedExp = stripBalanceSentences(exp)
            if !cleanedExp.isEmpty,
               !cleanedExp.contains("$"),
               !cleanedExp.lowercased().contains("hkd") {
                return (detectedAmount, cleanedExp)
            }
        }

        let primarySource = cleanedSources.first ?? combinedCleaned
        for regex in Self.merchantExtractionPatterns {
            if let match = regex.firstMatch(
                in: primarySource,
                range: NSRange(primarySource.startIndex..., in: primarySource)
            ),
               let mRange = Range(match.range(at: 1), in: primarySource) {
                let candidate = String(primarySource[mRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty && candidate.lowercased() != "octopus" {
                    return (detectedAmount, candidate)
                }
            }
        }

        // Fallback cleanup
        var cleaned = primarySource
        cleaned = Self.currencyRegex.stringByReplacingMatches(
            in: cleaned,
            range: NSRange(cleaned.startIndex..., in: cleaned),
            withTemplate: ""
        )
        let boilerplates = ["for", "spent", "paid", "payment", "transaction", "octopus", "八達通",
                            "已扣除", "扣除", "消費", "付款", "at", "via", "•", "|", "-", "."]
        for word in boilerplates {
            cleaned = cleaned.replacingOccurrences(of: word, with: " ", options: .caseInsensitive)
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return (detectedAmount, cleaned.isEmpty ? nil : cleaned)
    }

    // MARK: - Merchant Normalization
    private func stripPOSPrefixes(_ raw: String) -> String {
        var result = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = result.lowercased()
        for prefix in Self.posPrefixes {
            if lower.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return result
    }

    private func resolveMerchantName(from rawMerchant: String?, cardName: String?) -> String {
        let rawClean = rawMerchant?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if rawClean.isEmpty || rawClean.lowercased() == "wallet purchase" {
            return "Wallet Purchase"
        }

        let cleaned = stripPOSPrefixes(rawClean)
        let lower = cleaned.lowercased()

        for rule in Self.merchantNormalizations {
            if rule.keywords.contains(where: { lower.contains($0) }) {
                return rule.name
            }
        }
        return rawClean
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

    // MARK: - Category Resolution
    @MainActor
    private func resolveCategory(
        for merchant: String,
        rawMerchant: String?,
        cardName: String?,
        explicitCategory: String?,
        in context: ModelContext
    ) -> CategoryItem? {
        let existingCategories = (try? context.fetch(FetchDescriptor<CategoryItem>())) ?? []

        if let explicit = explicitCategory?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            if let matched = existingCategories.first(where: { $0.name.localizedCaseInsensitiveContains(explicit) }) {
                return matched
            }
        }

        let inferredName = inferCategoryName(for: merchant, rawMerchant: rawMerchant, cardName: cardName)

        if let matched = existingCategories.first(where: {
            $0.name.localizedCaseInsensitiveCompare(inferredName) == .orderedSame ||
            $0.name.localizedCaseInsensitiveContains(inferredName)
        }) {
            return matched
        }

        if inferredName == "Octopus" {
            let octopusCat = CategoryItem(
                name: "Octopus",
                iconName: "wave.3.forward.circle.fill",
                colorHex: "#FF9500"
            )
            context.insert(octopusCat)
            return octopusCat
        }

        if inferredName == "Groceries",
           let shoppingCat = existingCategories.first(where: { $0.name.localizedCaseInsensitiveContains("Shopping") }) {
            return shoppingCat
        }

        let newCategory = CategoryItem(
            name: inferredName,
            iconName: iconForCategory(inferredName),
            colorHex: colorForCategory(inferredName)
        )
        context.insert(newCategory)
        return newCategory
    }

    private func inferCategoryName(for merchant: String, rawMerchant: String?, cardName: String?) -> String {
        let cleanMerch = merchant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rawLower = (rawMerchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let combinedMerch = "\(cleanMerch) \(rawLower)"
        let cleanCard = (cardName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Specific merchant rules first
        for rule in Self.categoryRules {
            if rule.keywords.contains(where: { combinedMerch.contains($0) }) {
                return rule.category
            }
        }

        // Octopus / transit fallback
        if cleanCard.contains("octopus") || cleanCard.contains("八達通") ||
           cleanMerch.isEmpty || cleanMerch == "wallet purchase" ||
           cleanMerch.contains("train") || cleanMerch.contains("mtr") || cleanMerch.contains("bus") ||
           cleanMerch.contains("kmb") || cleanMerch.contains("citybus") ||
           cleanMerch.contains("tram") || cleanMerch.contains("ferry") ||
           cleanMerch.contains("港鐵") || cleanMerch.contains("九巴") {
            return "Octopus"
        }

        return "Groceries"
    }

    private func iconForCategory(_ name: String) -> String {
        switch name {
        case "Octopus": return "wave.3.forward.circle.fill"
        case "Transport": return "tram.fill"
        case "Dining": return "fork.knife"
        case "Groceries": return "cart.fill"
        case "Bills & Utilities": return "bolt.fill"
        case "Entertainment": return "tv.fill"
        case "Health & Fitness": return "heart.fill"
        case "Shopping": return "bag.fill"
        default: return "cart.fill"
        }
    }

    private func colorForCategory(_ name: String) -> String {
        switch name {
        case "Octopus": return "#FF9500"
        case "Transport": return "#007AFF"
        case "Dining": return "#FF9500"
        case "Groceries": return "#34C759"
        case "Bills & Utilities": return "#5856D6"
        case "Entertainment": return "#FF2D55"
        case "Health & Fitness": return "#FF3B30"
        case "Shopping": return "#AF52DE"
        default: return "#FF9500"
        }
    }

    // MARK: - Payment Method Resolver
    @MainActor
    private func resolvePaymentMethod(
        cardOrPass: String?,
        merchantHint: String?,
        in context: ModelContext
    ) -> PaymentMethodItem? {
        let existingMethods = (try? context.fetch(FetchDescriptor<PaymentMethodItem>())) ?? []

        let rawMerch = merchantHint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawCard = cardOrPass?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lowerMerch = rawMerch.lowercased()
        let lowerCard = rawCard.lowercased()

        let isBlankMerchantOctopusTap = (rawMerch.isEmpty || lowerMerch == "wallet purchase") &&
            (rawCard.isEmpty || lowerCard.contains("octopus") || lowerCard.contains("八達通"))

        let isExplicitOctopusMerchant =
            lowerCard.contains("octopus") || lowerCard.contains("八達通") ||
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
            if let directMatch = existingMethods.first(where: {
                $0.name.localizedCaseInsensitiveCompare(rawCard) == .orderedSame ||
                $0.name.localizedCaseInsensitiveContains(rawCard) ||
                rawCard.localizedCaseInsensitiveContains($0.name)
            }) {
                return directMatch
            }

            let stopWords: Set<String> = ["card", "credit", "debit", "bank", "the", "of", "hk", "visa", "mastercard", "pay", "apple", "wallet"]
            let incomingTokens = Set(
                rawCard.lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { $0.count >= 3 && !stopWords.contains($0) }
            )

            if !incomingTokens.isEmpty {
                if let tokenMatch = existingMethods.first(where: { method in
                    let methodTokens = Set(
                        method.name.lowercased()
                            .components(separatedBy: CharacterSet.alphanumerics.inverted)
                            .filter { $0.count >= 3 && !stopWords.contains($0) }
                    )
                    return !incomingTokens.isDisjoint(with: methodTokens)
                }) {
                    return tokenMatch
                }
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

// MARK: - App Shortcuts Provider for Siri & Shortcuts Discovery
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
