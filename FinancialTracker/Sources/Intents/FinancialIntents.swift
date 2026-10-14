import AppIntents
import SwiftData
import Foundation

// MARK: - Zero-Touch Apple Pay & Travel Card Auto-Logging Intent
public struct LogExpenseIntent: AppIntent {
    public static var title: LocalizedStringResource = "Auto-Log Apple Pay & Travel Card"
    public static var description = IntentDescription("Automatically logs Apple Pay and Express Transit travel card transactions in the background with smart merchant categorization and card matching.")
    
    // Runs 100% silently in the background without opening the app
    public static var openAppWhenRun: Bool = false
    
    @Parameter(
        title: "Amount",
        description: "Pass 'Amount' from the Shortcut Transaction input (supports numbers or formatted currency like HK$45.50). Defaults to 0 if omitted by transit gate.",
        default: "0"
    )
    public var amountText: String?
    
    @Parameter(
        title: "Merchant",
        description: "Pass 'Merchant' or 'Name' from the Shortcut Transaction input (e.g. MTR, Starbucks, Wellcome)"
    )
    public var merchant: String?
    
    @Parameter(
        title: "Card or Pass",
        description: "Pass 'Card or Pass' from the Shortcut Transaction input (e.g. Octopus, HSBC Red Card, Suica, Apple Pay)"
    )
    public var paymentMethod: String?
    
    @Parameter(
        title: "Category (Optional Override)",
        description: "Leave blank to auto-categorize based on merchant history and Hong Kong merchant rules"
    )
    public var category: String?
    
    @Parameter(
        title: "Notes",
        description: "Optional notes (defaults to 'Auto-logged via Apple Pay')"
    )
    public var notes: String?
    
    // Makes the action block in iOS Shortcuts clean and 1-tap to wire up
    public static var parameterSummary: some ParameterSummary {
        Summary("Auto-log \(\.$amountText) at \(\.$merchant) with \(\.$paymentMethod)") {
            \.$category
            \.$notes
        }
    }
    
    public init() {}
    
    public init(
        amount: Double,
        merchant: String? = nil,
        category: String? = nil,
        paymentMethod: String? = nil,
        notes: String? = nil
    ) {
        self.amountText = String(format: "%.2f", amount)
        self.merchant = merchant
        self.category = category
        self.paymentMethod = paymentMethod
        self.notes = notes
    }
    
    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = AppDataStore.sharedModelContainer
        let context = container.mainContext
        
        // 1. Fault-tolerant amount parsing (handles "45.5", "HK$45.50", "$1,200.00", or nil)
        let parsedAmount = Self.parseAmount(from: amountText)
        
        // 2. Clean merchant name
        let rawMerchant = (merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rawCard = (paymentMethod ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveMerchant: String = {
            if !rawMerchant.isEmpty { return rawMerchant }
            if Self.isTravelCard(rawCard) { return "Transit / Travel Card" }
            return "Apple Pay Purchase"
        }()
        
        // 3. Fetch Categories, Accounts, and Past Transactions for Smart Learning
        let allCategories = (try? context.fetch(FetchDescriptor<CategoryItem>())) ?? []
        let allMethods = (try? context.fetch(FetchDescriptor<PaymentMethodItem>())) ?? []
        let recentTransactions = (try? context.fetch(FetchDescriptor<TransactionItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        ))) ?? []
        
        // 4. Smart Category Resolution
        let matchedCategory = Self.resolveCategory(
            explicitCategory: category,
            merchant: effectiveMerchant,
            cardOrPass: rawCard,
            allCategories: allCategories,
            recentTransactions: recentTransactions
        )
        
        // 5. Smart Payment Account / Travel Card Resolution
        let defaultMethodName = UserDefaults.standard.string(forKey: "default_payment_method") ?? "Apple Pay"
        let matchedMethod = Self.resolvePaymentMethod(
            cardOrPass: rawCard,
            merchant: effectiveMerchant,
            defaultMethodName: defaultMethodName,
            allMethods: allMethods,
            recentTransactions: recentTransactions
        )
        
        let defaultCurrency = UserDefaults.standard.string(forKey: "default_currency") ?? "HKD"
        let autoNote: String = {
            if let customNotes = notes, !customNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return customNotes
            }
            if !rawCard.isEmpty {
                return "Auto-logged via \(rawCard)"
            }
            return "Auto-logged via Apple Pay"
        }()
        
        let item = TransactionItem(
            amount: parsedAmount,
            currency: defaultCurrency,
            merchant: effectiveMerchant,
            notes: autoNote,
            type: .expense,
            category: matchedCategory,
            paymentMethod: matchedMethod,
            isExcludedFromBudget: false
        )
        
        context.insert(item)
        try? context.save()
        
        AccountBalanceManager.shared.recalculateBalances(context: context)
        WidgetSyncManager.shared.syncWidget(context: context)
        
        let catName = matchedCategory?.name ?? "General"
        let methodName = matchedMethod?.name ?? "Apple Pay"
        return .result(
            dialog: "Logged \(defaultCurrency) \(String(format: "%.2f", parsedAmount)) at \(effectiveMerchant) (\(catName) • \(methodName))."
        )
    }
    
    // MARK: - Smart Parsing & Classification Helpers
    
    private static func parseAmount(from input: String?) -> Double {
        guard let raw = input, !raw.isEmpty else { return 0.0 }
        let normalized = raw.replacingOccurrences(of: ",", with: "")
        let pattern = #"-?\d+(?:\.\d+)?"#
        if let range = normalized.range(of: pattern, options: .regularExpression),
           let val = Double(normalized[range]),
           val.isFinite {
            return abs(val)
        }
        return 0.0
    }
    
    private static func isTravelCard(_ cardName: String) -> Bool {
        let lower = cardName.lowercased()
        let travelKeywords = [
            "octopus", "八達通", "suica", "icoca", "pasmo", "t-money", "easycard", "悠遊卡",
            "transit", "travel", "mtr", "oyster", "clipper"
        ]
        return travelKeywords.contains { lower.contains($0) }
    }
    
    private static func resolveCategory(
        explicitCategory: String?,
        merchant: String,
        cardOrPass: String,
        allCategories: [CategoryItem],
        recentTransactions: [TransactionItem]
    ) -> CategoryItem? {
        if let exp = explicitCategory?.trimmingCharacters(in: .whitespacesAndNewlines), !exp.isEmpty {
            if let found = allCategories.first(where: { !$0.isDeleted && $0.name.localizedCaseInsensitiveContains(exp) }) {
                return found
            }
        }
        
        let cleanMerch = merchant.lowercased()
        if !cleanMerch.isEmpty && cleanMerch != "apple pay purchase" && cleanMerch != "general" {
            if let pastMatch = recentTransactions.first(where: {
                !$0.isDeleted && $0.merchant.lowercased() == cleanMerch && $0.category != nil
            }), let learnedCat = pastMatch.category, !learnedCat.isDeleted {
                return learnedCat
            }
        }
        
        let inferredCategoryName = inferCategoryName(fromMerchant: merchant, cardOrPass: cardOrPass)
        if let matched = allCategories.first(where: {
            !$0.isDeleted && $0.name.localizedCaseInsensitiveContains(inferredCategoryName)
        }) {
            return matched
        }
        
        return allCategories.first(where: { !$0.isDeleted && $0.name == "Other" }) ?? allCategories.first(where: { !$0.isDeleted })
    }
    
    private static func inferCategoryName(fromMerchant merchant: String, cardOrPass: String) -> String {
        let m = merchant.lowercased()
        
        let transportKeywords = [
            "mtr", "港鐵", "kmb", "九巴", "citybus", "城巴", "nwfb", "uber", "taxi", "的士",
            "tram", "電車", "star ferry", "天星小輪", "ferry", "bus", "train", "railway", "tunnel",
            "青馬", "紅隧", "西隧", "東隧", "shell", "esso", "caltex", "sinopec", "parking", "領展停車場", "wilson parking"
        ]
        if transportKeywords.contains(where: { m.contains($0) }) { return "Transport" }
        
        let diningKeywords = [
            "starbucks", "pacific coffee", "コーヒー", "coffee", "cafe", "café", "大家樂", "cafe de coral",
            "大快活", "fairwood", "美心", "maxim", "mcdonald", "麥當勞", "kfc", "肯德基", "mos burger",
            "shake shack", "five guys", "tamjai", "譚仔", "sukiya", "すき家", "吉野家", "yoshinoya",
            "genki", "元氣", "sushiro", "壽司郎", "deliveroo", "foodpanda", "keeta", "bakehouse",
            "restaurant", "dining", "bakery", "奇華", "東海堂", "arome", "chicha", "吃茶三千", "heytea", "喜茶"
        ]
        if diningKeywords.contains(where: { m.contains($0) }) { return "Dining" }
        
        let groceryKeywords = [
            "wellcome", "惠康", "parknshop", "百佳", "taste", "fusion", "international", "market place",
            "3hreesixty", "city'super", "citysuper", "don don donki", "donki", "驚安", "yata", "一田",
            "aeon", "apita", "uny", "759", "阿信屋", "大生", "優品360", "hktvmall", "錢大媽", "grocer", "supermarket",
            "7-eleven", "7-11", "circle k", "ok便利店", "familymart", "lawson"
        ]
        if groceryKeywords.contains(where: { m.contains($0) }) { return "Groceries" }
        
        let billsKeywords = [
            "clp", "中華電力", "hk electric", "港燈", "towngas", "煤氣", "water supplies", "水務署",
            "csl", "1010", "smartone", "數碼通", "cmhk", "中國移動", "3hk", "hkbn", "香港寬頻",
            "netvigator", "網上行", "hkt", "pccw", "insurance", "aia", "prudential", "manulife", "fwd", "保誠", "友邦", "宏利"
        ]
        if billsKeywords.contains(where: { m.contains($0) }) { return "Bills & Utilities" }
        
        let entertainmentKeywords = [
            "netflix", "spotify", "apple.com/bill", "itunes", "icloud", "youtube", "disney",
            "cinema", "mcl", "broadway circuit", "百老匯院線", "emperor cinemas", "英皇戲院", "golden harvest",
            "steam", "playstation", "nintendo", "xbox", "kkbox", "moov", "now tv", "disneyland", "ocean park"
        ]
        if entertainmentKeywords.contains(where: { m.contains($0) }) { return "Entertainment" }
        
        let healthKeywords = [
            "watsons", "屈臣氏", "mannings", "萬寧", "松本清", "matsumoto", "sasa", "莎莎", "bonjour",
            "24/7 fitness", "pure fitness", "anytime fitness", "efx24", "snap fitness", "gym",
            "clinic", "hospital", "medical", "dental", "pharmacy", "藥房"
        ]
        if healthKeywords.contains(where: { m.contains($0) }) { return "Health & Fitness" }
        
        let shoppingKeywords = [
            "uniqlo", "gu", "zara", "h&m", "muji", "無印良品", "ikea", "宜家", "decathlon",
            "fortress", "豐澤", "broadway", "百老匯", "sogo", "崇光", "lane crawford", "連卡佛",
            "log-on", "誠品", "eslite", "apple store", "nike", "adidas", "lululemon", "taobao", "淘寶", "amazon"
        ]
        if shoppingKeywords.contains(where: { m.contains($0) }) { return "Shopping" }
        
        if isTravelCard(cardOrPass) {
            return "Transport"
        }
        
        return "Other"
    }
    
    private static func resolvePaymentMethod(
        cardOrPass: String,
        merchant: String,
        defaultMethodName: String,
        allMethods: [PaymentMethodItem],
        recentTransactions: [TransactionItem]
    ) -> PaymentMethodItem? {
        let activeMethods = allMethods.filter { !$0.isDeleted }
        let cleanCard = cardOrPass.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !cleanCard.isEmpty {
            if let directMatch = activeMethods.first(where: {
                $0.name.localizedCaseInsensitiveContains(cleanCard) || cleanCard.localizedCaseInsensitiveContains($0.name)
            }) {
                return directMatch
            }
            
            if isTravelCard(cleanCard) {
                if let octopusMethod = activeMethods.first(where: {
                    $0.name.localizedCaseInsensitiveContains("Octopus") ||
                    $0.name.localizedCaseInsensitiveContains("八達通") ||
                    $0.name.localizedCaseInsensitiveContains("Travel")
                }) {
                    return octopusMethod
                }
            }
        }
        
        let m = merchant.lowercased()
        if ["mtr", "港鐵", "kmb", "九巴", "citybus", "城巴", "tram", "電車", "star ferry"].contains(where: { m.contains($0) }) {
            if let octopusMethod = activeMethods.first(where: {
                $0.name.localizedCaseInsensitiveContains("Octopus") || $0.name.localizedCaseInsensitiveContains("八達通")
            }) {
                return octopusMethod
            }
        }
        
        if !m.isEmpty && m != "apple pay purchase" {
            if let pastTx = recentTransactions.first(where: {
                !$0.isDeleted && $0.merchant.lowercased() == m && $0.paymentMethod != nil
            }), let learnedMethod = pastTx.paymentMethod, !learnedMethod.isDeleted {
                return learnedMethod
            }
        }
        
        if let defaultMatch = activeMethods.first(where: { $0.name.localizedCaseInsensitiveContains(defaultMethodName) }) {
            return defaultMatch
        }
        if let applePayMatch = activeMethods.first(where: {
            $0.name.localizedCaseInsensitiveContains("Apple Pay") || $0.name.localizedCaseInsensitiveContains("Credit Card") || $0.isLiability
        }) {
            return applePayMatch
        }
        
        return activeMethods.first
    }
}

public struct FinancialShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: [
                "Auto-log Apple Pay in \(.applicationName)",
                "Log an expense in \(.applicationName)",
                "Track spending in \(.applicationName)",
                "Add transaction to \(.applicationName)"
            ],
            shortTitle: "Auto-Log Apple Pay & Travel Card",
            systemImageName: "wave.3.right.circle.fill"
        )
    }
}
