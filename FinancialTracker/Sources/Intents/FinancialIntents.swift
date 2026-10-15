import Foundation
import AppIntents
import SwiftData

// MARK: - Zero-Touch Wallet & Travel Card Auto-Logging Intent
public struct AutoLogWalletPaymentIntent: AppIntent {
    public static var title: LocalizedStringResource = "Auto-Log Wallet & Travel Card"
    public static var description = IntentDescription("Automatically logs Wallet and Express Transit travel card transactions in the background with smart merchant categorization and card matching.")
    public static var openAppWhenRun: Bool = false
    public static var isDiscoverable: Bool = true

    @Parameter(
        title: "Amount",
        description: "Transaction amount passed by the iOS Shortcut Transaction trigger"
    )
    public var amount: Double

    @Parameter(
        title: "Merchant",
        description: "Merchant name from the transaction (e.g. Starbucks, 7-Eleven, MTR, KMB)"
    )
    public var merchant: String?

    @Parameter(
        title: "Card or Pass",
        description: "Pass 'Card or Pass' from the Shortcut Transaction input (e.g. Octopus, HSBC Red Card, Suica, Digital Card)"
    )
    public var cardOrPassName: String?

    @Parameter(
        title: "Category",
        description: "Optional category override. If omitted, Worthly auto-categorizes based on merchant."
    )
    public var categoryName: String?

    @Parameter(
        title: "Notes",
        description: "Optional notes (defaults to 'Auto-logged transaction')"
    )
    public var notes: String?

    public init() {}

    public init(
        amount: Double,
        merchant: String? = nil,
        cardOrPassName: String? = nil,
        categoryName: String? = nil,
        notes: String? = nil
    ) {
        self.amount = amount
        self.merchant = merchant
        self.cardOrPassName = cardOrPassName
        self.categoryName = categoryName
        self.notes = notes
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let positiveAmount = abs(amount)
        guard positiveAmount > 0 else {
            return .result(value: "Ignored: Amount must be greater than zero.")
        }

        let container = AppDataStore.sharedModelContainer
        let context = container.mainContext

        let currency = UserDefaults.standard.string(forKey: "default_currency") ?? "HKD"
        let resolvedMerchant = resolveMerchantName(from: merchant, cardName: cardOrPassName)
        let resolvedCategory = resolveCategory(for: resolvedMerchant, explicitCategory: categoryName, in: context)
        let resolvedPaymentMethod = resolvePaymentMethod(cardOrPass: cardOrPassName, in: context)
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

        if let method = resolvedPaymentMethod {
            method.currentBalance -= positiveAmount
        }

        try? context.save()

        WidgetSyncManager.shared.syncWidget(context: context)

        let methodName = resolvedPaymentMethod?.name ?? "Wallet"
        let summary = String(
            format: "Logged %@ %.2f at %@ via %@",
            currency,
            positiveAmount,
            resolvedMerchant,
            methodName
        )
        return .result(value: summary)
    }

    // MARK: - Smart Merchant Normalization
    private func resolveMerchantName(from rawMerchant: String?, cardName: String?) -> String {
        let clean = rawMerchant?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if clean.isEmpty {
            if let card = cardName?.trimmingCharacters(in: .whitespacesAndNewlines), !card.isEmpty {
                let lowerCard = card.lowercased()
                if lowerCard.contains("octopus") || lowerCard.contains("八達通") {
                    return "Octopus Transit / Retail"
                } else if lowerCard.contains("suica") || lowerCard.contains("pasmo") || lowerCard.contains("icoca") {
                    return "Japan Transit / Retail"
                }
                return "\(card) Purchase"
            }
            return "Wallet Purchase"
        }

        let lower = clean.lowercased()
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
        } else if lower.contains("don don donki") || lower.contains("donki") {
            return "Don Don Donki"
        } else if lower.contains("clp") || lower.contains("中電") {
            return "CLP Power"
        } else if lower.contains("towngas") || lower.contains("煤氣") {
            return "Towngas"
        }

        return clean
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

        let inferredName = inferCategoryName(for: merchant)

        if let matched = existingCategories.first(where: {
            $0.name.localizedCaseInsensitiveCompare(inferredName) == .orderedSame ||
            $0.name.localizedCaseInsensitiveContains(inferredName)
        }) {
            return matched
        }

        if let otherCategory = existingCategories.first(where: {
            $0.name.localizedCaseInsensitiveContains("Other") || $0.name.localizedCaseInsensitiveContains("其他")
        }) {
            return otherCategory
        }

        let newCategory = CategoryItem(
            name: inferredName,
            iconName: iconForCategory(inferredName),
            colorHex: colorForCategory(inferredName)
        )
        context.insert(newCategory)
        return newCategory
    }

    private func inferCategoryName(for merchant: String) -> String {
        let cleanMerch = merchant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let transportMerchants = [
            "mtr", "kmb", "citybus", "nwfb", "star ferry", "taxi", "uber", "tunnel", "hketoll",
            "tram", "peak tram", "light rail", "green minibus", "red minibus", "港鐵", "九巴", "城巴", "新巴", "天星小輪", "的士", "電車", "輕鐵", "小巴"
        ]
        for t in transportMerchants where cleanMerch.contains(t) {
            return "Transport"
        }

        let diningMerchants = [
            "starbucks", "mcdonald", "kfc", "pacific coffee", "fairwood", "cafe de coral", "maxim", "sushiro",
            "genki", "tamjai", "samgor", "pizza hut", "subway", "bakehouse", "shake shack", "cha chaan teng",
            "大快活", "大家樂", "美心", "壽司郎", "元氣", "譚仔", "三哥", "茶餐廳", "酒樓", "餐廳"
        ]
        for d in diningMerchants where cleanMerch.contains(d) {
            return "Dining"
        }

        let groceryMerchants = [
            "wellcome", "parknshop", "fusion", "marketplace", "city'super", "donki", "don don donki", "aeon", "yata", "759", "7-eleven", "circle k",
            "惠康", "百佳", "一田", "阿信屋", "便利店", "超市"
        ]
        for g in groceryMerchants where cleanMerch.contains(g) {
            return "Groceries"
        }

        let utilityMerchants = [
            "clp", "towngas", "hkelectric", "autotoll", "water supplies", "hkbn", "pccw", "smartone", "csl", "3hk", "cmhk", "broadband",
            "中電", "港燈", "煤氣", "水費", "香港寬頻", "電訊盈科"
        ]
        for u in utilityMerchants where cleanMerch.contains(u) {
            return "Bills & Utilities"
        }

        let entertainmentMerchants = [
            "netflix", "spotify", "apple.com/bill", "itunes", "icloud", "youtube", "disney",
            "broadway", "mcl", "golden harvest", "cinema", "steam", "playstation", "nintendo"
        ]
        for e in entertainmentMerchants where cleanMerch.contains(e) {
            return "Entertainment"
        }

        let healthMerchants = [
            "mannings", "watsons", "panadol", "clinic", "hospital", "dental", "pharmacy", "萬寧", "屈臣氏", "診所", "醫院", "藥房"
        ]
        for h in healthMerchants where cleanMerch.contains(h) {
            return "Health & Medical"
        }

        let shoppingMerchants = [
            "log-on", "誠品", "eslite", "apple store", "nike", "adidas", "lululemon", "taobao", "淘寶", "amazon"
        ]
        for s in shoppingMerchants where cleanMerch.contains(s) {
            return "Shopping"
        }

        return "Other"
    }

    private func iconForCategory(_ name: String) -> String {
        switch name {
        case "Transport": return "tram.fill"
        case "Dining": return "fork.knife"
        case "Groceries": return "cart.fill"
        case "Bills & Utilities": return "bolt.fill"
        case "Entertainment": return "film.fill"
        case "Health & Medical": return "cross.case.fill"
        case "Shopping": return "bag.fill"
        default: return "tag.fill"
        }
    }

    private func colorForCategory(_ name: String) -> String {
        switch name {
        case "Transport": return "#FF9500"
        case "Dining": return "#34C759"
        case "Groceries": return "#AF52DE"
        case "Bills & Utilities": return "#5856D6"
        case "Entertainment": return "#FF2D55"
        case "Health & Medical": return "#FF3B30"
        case "Shopping": return "#007AFF"
        default: return "#8E8E93"
        }
    }

    // MARK: - Smart Payment Method Resolver
    @MainActor
    private func resolvePaymentMethod(cardOrPass: String?, in context: ModelContext) -> PaymentMethodItem? {
        let descriptor = FetchDescriptor<PaymentMethodItem>()
        let existingMethods = (try? context.fetch(descriptor)) ?? []

        if let card = cardOrPass?.trimmingCharacters(in: .whitespacesAndNewlines), !card.isEmpty {
            if let directMatch = existingMethods.first(where: {
                $0.name.localizedCaseInsensitiveCompare(card) == .orderedSame ||
                $0.name.localizedCaseInsensitiveContains(card) ||
                card.localizedCaseInsensitiveContains($0.name)
            }) {
                return directMatch
            }

            let lowerCard = card.lowercased()
            let isTransit = lowerCard.contains("octopus") || lowerCard.contains("八達通") ||
                            lowerCard.contains("suica") || lowerCard.contains("pasmo") ||
                            lowerCard.contains("icoca") || lowerCard.contains("transit")

            let newMethod = PaymentMethodItem(
                name: card,
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
