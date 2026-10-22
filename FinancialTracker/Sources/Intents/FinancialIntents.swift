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
        description: "Merchant name from the transaction or Notification Subtitle"
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

        // Combine all text fields to extract amount & merchant when triggered by a Notification
        let combinedNotificationText = [notificationText, merchant, notes, cardOrPassName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")

        let extracted = extractAmountAndMerchant(from: combinedNotificationText, explicitMerchant: merchant)

        // Resolve final positive amount:
        // 1. Explicit numeric `amount` parameter if provided (> 0)
        // 2. Dynamic amount parsed from Notification text (e.g. "HK$5.10 at MTR" -> 5.10)
        let resolvedAmount: Double? = {
            if let explicitAmt = amount, abs(explicitAmt) > 0 {
                return abs(explicitAmt)
            }
            if let parsedAmt = extracted.amount, parsedAmt > 0 {
                return parsedAmt
            }
            return nil
        }()

        // If neither numeric amount nor notification amount was found (e.g. MTR $0 entry-gate tap), skip silently
        guard let positiveAmount = resolvedAmount, positiveAmount > 0 else {
            return .result(value: "Skipped: No transaction amount detected in tap or notification.")
        }

        let effectiveRawMerchant = extracted.merchant ?? merchant
        let rawMerchLower = (effectiveRawMerchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fullTextLower = combinedNotificationText.lowercased()

        // 1. Check if this is an Octopus Auto Top-Up (AAVS) or Wallet reload
        let isAAVSTopUp = rawMerchLower.contains("octopus cards") || rawMerchLower.contains("aavs") ||
                          rawMerchLower.contains("top up") || rawMerchLower.contains("top-up") ||
                          rawMerchLower.contains("自動增值") || rawMerchLower.contains("八達通增值") ||
                          rawMerchLower.contains("octopus reload") ||
                          fullTextLower.contains("auto add value") || fullTextLower.contains("自動增值")

        let allMethods = (try? context.fetch(FetchDescriptor<PaymentMethodItem>())) ?? []
        let octopusAccount = allMethods.first(where: {
            $0.name.localizedCaseInsensitiveContains("Octopus") || $0.name.localizedCaseInsensitiveContains("八達通")
        })

        if isAAVSTopUp {
            // AAVS Top-Up is a TRANSFER (Credit Card -> Octopus) so it NEVER double-counts Monthly Spending!
            let creditCardAccount = allMethods.first(where: {
                $0.name == "CUHK Credit Card" || $0.name.localizedCaseInsensitiveContains("CUHK") || $0.isLiability
            }) ?? allMethods.first

            let topUpTx = TransactionItem(
                timestamp: Date(),
                amount: positiveAmount,
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
            try? context.save()
            RecurringPaymentManager.shared.processDueRecurringPayments(context: context)
            AccountBalanceManager.shared.recalculateBalances(context: context)
            WidgetSyncManager.shared.syncWidget(context: context)

            return .result(value: String(format: "Logged Transfer %@ %.2f: %@ → Octopus", currency, positiveAmount, creditCardAccount?.name ?? "Credit Card"))
        }

        // 2. Standard Expense Flow
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
        try? context.save()

        RecurringPaymentManager.shared.processDueRecurringPayments(context: context)
        AccountBalanceManager.shared.recalculateBalances(context: context)
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

    // MARK: - Smart Notification Amount & Merchant Parser
    private func extractAmountAndMerchant(from rawText: String, explicitMerchant: String?) -> (amount: Double?, merchant: String?) {
        guard !rawText.isEmpty else { return (nil, explicitMerchant) }

        var detectedAmount: Double? = nil

        // Match currency patterns first: e.g. "HK$5.10", "HKD 12.40", "$45.00", "-$5.60", "HK$ 250.00"
        let currencyPattern = #"(?:HK\$|HKD|US\$|USD|\$|¥|£|€)\s*([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)"#
        if let regex = try? NSRegularExpression(pattern: currencyPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: rawText, range: NSRange(rawText.startIndex..., in: rawText)),
           let numRange = Range(match.range(at: 1), in: rawText) {
            let numStr = rawText[numRange].replacingOccurrences(of: ",", with: "")
            detectedAmount = Double(numStr)
        }

        // Fallback decimal pattern: e.g. "5.10", "12.40"
        if detectedAmount == nil {
            let decimalPattern = #"(?<![0-9])([0-9]+(?:\.[0-9]{1,2}))(?![0-9])"#
            if let regex = try? NSRegularExpression(pattern: decimalPattern),
               let match = regex.firstMatch(in: rawText, range: NSRange(rawText.startIndex..., in: rawText)),
               let numRange = Range(match.range(at: 1), in: rawText) {
                detectedAmount = Double(rawText[numRange])
            }
        }

        // If explicit merchant doesn't contain a currency string, keep it
        if let exp = explicitMerchant?.trimmingCharacters(in: .whitespacesAndNewlines),
           !exp.isEmpty,
           !exp.contains("$"),
           !exp.lowercased().contains("hkd") {
            return (detectedAmount, exp)
        }

        // Extract merchant from notification patterns like "HK$5.10 at MTR", "Paid HK$5.10 to KMB", "於 港鐵 消費 HK$5.10"
        let source = notificationText ?? explicitMerchant ?? rawText
        let atPatterns = [
            #"(?:at|to|in|from|•|-)\s+([A-Za-z0-9\*\s&\.'\-_]+)"#,
            #"於\s*([^\s]+)\s*(?:消費|付款|扣除)"#
        ]
        for pat in atPatterns {
            if let regex = try? NSRegularExpression(pattern: pat, options: .caseInsensitive),
               let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
               let mRange = Range(match.range(at: 1), in: source) {
                let candidate = String(source[mRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty && candidate.lowercased() != "octopus" {
                    return (detectedAmount, candidate)
                }
            }
        }

        // Otherwise strip the currency amount and common notification boilerplate words
        var cleaned = source
        if let regex = try? NSRegularExpression(pattern: currencyPattern, options: .caseInsensitive) {
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
        }
        let boilerplates = ["spent", "paid", "payment", "transaction", "octopus", "八達通", "已扣除", "扣除", "消費", "付款", "at", "via", "•", "|", "-"]
        for word in boilerplates {
            cleaned = cleaned.replacingOccurrences(of: word, with: " ", options: .caseInsensitive)
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return (detectedAmount, cleaned.isEmpty ? nil : cleaned)
    }

    // MARK: - Smart Merchant Normalization & POS Prefix Cleaner
    private func stripPOSPrefixes(_ raw: String) -> String {
        var result = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["bbmsl*", "bindo*", "kpay*", "eftpay*", "shopy*", "qf*", "sq *", "sq*", "sp *", "sp*", "paypal *", "paypal*"]
        let lower = result.lowercased()
        for prefix in prefixes {
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

        if lower.contains("mtr") || lower.contains("港鐵") {
            return "MTR"
        } else if lower.contains("kmb") || lower.contains("九巴") {
            return "KMB"
        } else if lower.contains("citybus") || lower.contains("城巴") || lower.contains("nwfb") || lower.contains("新巴") {
            return "Citybus"
        } else if lower.contains("starbucks") {
            return "Starbucks"
        } else if lower.contains("mcdonald") || lower.contains("mcd") {
            return "McDonald's"
        } else if lower.contains("7-eleven") || lower.contains("7 eleven") || lower.contains("seven eleven") {
            return "7-Eleven"
        } else if lower.contains("circle k") || lower.contains("ok便利店") {
            return "Circle K"
        } else if lower.contains("wellcome") || lower.contains("惠康") {
            return "Wellcome"
        } else if lower.contains("parknshop") || lower.contains("百佳") {
            return "PARKnSHOP"
        } else if lower.contains("mannings") || lower.contains("萬寧") {
            return "Mannings"
        } else if lower.contains("watsons") || lower.contains("屈臣氏") {
            return "Watsons"
        } else if lower.contains("lung fung") || lower.contains("龍豐") {
            return "Lung Fung Mall"
        } else if lower.contains("don don donki") || lower.contains("donki") {
            return "Don Don Donki"
        } else if lower.contains("clp") || lower.contains("中電") {
            return "CLP Power"
        } else if lower.contains("towngas") || lower.contains("煤氣") {
            return "Towngas"
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

    // MARK: - Smart Category Matcher
    @MainActor
    private func resolveCategory(
        for merchant: String,
        rawMerchant: String?,
        cardName: String?,
        explicitCategory: String?,
        in context: ModelContext
    ) -> CategoryItem? {
        let descriptor = FetchDescriptor<CategoryItem>()
        let existingCategories = (try? context.fetch(descriptor)) ?? []

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

        // 1. Dedicated "Octopus" category for all Octopus travel card taps, MTR, buses, and blank transit logs
        if cleanCard.contains("octopus") || cleanCard.contains("八達通") ||
           cleanMerch.isEmpty || cleanMerch == "wallet purchase" ||
           cleanMerch.contains("mtr") || cleanMerch.contains("kmb") || cleanMerch.contains("citybus") ||
           cleanMerch.contains("tram") || cleanMerch.contains("港鐵") || cleanMerch.contains("九巴") {
            return "Octopus"
        }

        // 2. General Transit Keywords (for non-Octopus travel cards like Suica / Transit)
        let transportMerchants = [
            "star ferry", "taxi", "uber", "tunnel", "hketoll", "peak tram", "light rail", "green minibus", "red minibus",
            "suica", "pasmo", "icoca", "transit", "天星小輪", "的士", "電車", "輕鐵", "小巴"
        ]
        for t in transportMerchants where combinedMerch.contains(t) {
            return "Transport"
        }

        // 3. Shopping / Electronics / Appliances / Apparel (Check before Groceries so Fortress/Broadway go to Shopping)
        let shoppingMerchants = [
            "fortress", "豐澤", "broadway", "百老滙", "log-on", "誠品", "eslite", "apple store",
            "nike", "adidas", "lululemon", "taobao", "淘寶", "amazon", "uniqlo", "zara", "muji"
        ]
        for s in shoppingMerchants where combinedMerch.contains(s) {
            return "Shopping"
        }

        // 4. Dining / Restaurants / Cafes
        let diningMerchants = [
            "starbucks", "mcdonald", "kfc", "pacific coffee", "fairwood", "cafe de coral", "maxim", "sushiro",
            "genki", "tamjai", "samgor", "pizza hut", "subway", "bakehouse", "shake shack", "cha chaan teng",
            "canteen", "coffee", "cafe", "restaurant",
            "大快活", "大家樂", "美心", "壽司郎", "元氣", "譚仔", "三哥", "茶餐廳", "酒樓", "餐廳"
        ]
        for d in diningMerchants where combinedMerch.contains(d) {
            return "Dining"
        }

        // 5. Groceries / Retail / Mall / Bakery / Supplements
        let groceryAndRetailMerchants = [
            "wellcome", "parknshop", "fusion", "marketplace", "city'super", "donki", "don don donki",
            "aeon", "yata", "759", "7-eleven", "circle k", "lung fung", "龍豐",
            "ichicake", "cake", "bake", "bodybuilding", "kpay*", "bindo*", "mall", "mart", "store",
            "mannings", "watsons", "惠康", "百佳", "一田", "阿信屋", "便利店", "超市", "萬寧", "屈臣氏"
        ]
        for g in groceryAndRetailMerchants where combinedMerch.contains(g) {
            return "Groceries"
        }

        let utilityMerchants = [
            "clp", "towngas", "hkelectric", "autotoll", "water supplies", "hkbn", "pccw", "smartone", "csl", "3hk", "cmhk", "broadband",
            "中電", "港燈", "煤氣", "水費", "香港寬頻", "電訊盈科"
        ]
        for u in utilityMerchants where combinedMerch.contains(u) {
            return "Bills & Utilities"
        }

        let entertainmentMerchants = [
            "netflix", "spotify", "apple.com/bill", "itunes", "icloud", "youtube", "disney",
            "mcl", "golden harvest", "cinema", "steam", "playstation", "nintendo"
        ]
        for e in entertainmentMerchants where combinedMerch.contains(e) {
            return "Entertainment"
        }

        let healthMerchants = [
            "panadol", "clinic", "hospital", "dental", "pharmacy", "gym", "fitness",
            "診所", "醫院", "藥房"
        ]
        for h in healthMerchants where combinedMerch.contains(h) {
            return "Health & Fitness"
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

    // MARK: - Smart Payment Method Resolver
    @MainActor
    private func resolvePaymentMethod(
        cardOrPass: String?,
        merchantHint: String?,
        in context: ModelContext
    ) -> PaymentMethodItem? {
        let descriptor = FetchDescriptor<PaymentMethodItem>()
        let existingMethods = (try? context.fetch(descriptor)) ?? []

        let rawMerch = merchantHint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawCard = cardOrPass?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let lowerMerch = rawMerch.lowercased()
        let lowerCard = rawCard.lowercased()
        let isBlankMerchantOctopusTap = (rawMerch.isEmpty || lowerMerch == "wallet purchase") && (rawCard.isEmpty || lowerCard.contains("octopus") || lowerCard.contains("八達通"))
        let isExplicitOctopusMerchant = lowerCard.contains("octopus") || lowerCard.contains("八達通") ||
                                        lowerMerch.contains("mtr") || lowerMerch.contains("kmb") ||
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