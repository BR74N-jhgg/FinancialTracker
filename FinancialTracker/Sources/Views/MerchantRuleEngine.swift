//
//  MerchantRuleEngine.swift
//  Worthly
//

import Foundation

// MARK: - Centralized Hong Kong Merchant, Octopus & Notification Rule Engine
public struct MerchantRuleEngine: Sendable {

    // MARK: 1. POS Gateway Prefixes
    public static let posPrefixes: [String] = [
        "bbmsl*", "bindo*", "kpay*", "eftpay*", "shopy*",
        "qf*", "sq *", "sq*", "sp *", "sp*", "paypal *", "paypal*"
    ]

    // MARK: 2. Canonical Merchant Normalization Rules
    public static let canonicalMerchantRules: [(keywords: [String], canonicalName: String)] = [
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
        (["sushiro", "壽司郎"], "Sushiro"),
        (["fortress", "豐澤"], "Fortress"),
        (["broadway", "百老滙"], "Broadway"),
        (["clp", "中電"], "CLP Power"),
        (["towngas", "煤氣"], "Towngas")
    ]

    // MARK: 3. Fully Data-Driven Category Rules (Specific Merchants First -> Transit -> Fallback)
    public static let categoryRules: [(category: String, keywords: [String])] = [
        ("Shopping", [
            "fortress", "豐澤", "broadway", "百老滙", "log-on", "誠品", "eslite", "apple store",
            "nike", "adidas", "lululemon", "taobao", "淘寶", "amazon", "uniqlo", "zara", "muji"
        ]),
        ("Dining", [
            "starbucks", "mcdonald", "kfc", "pacific coffee", "fairwood", "cafe de coral", "maxim", "sushiro",
            "genki", "tamjai", "samgor", "pizza hut", "subway", "bakehouse", "shake shack", "cha chaan teng",
            "canteen", "coffee", "cafe", "restaurant",
            "大快活", "大家樂", "美心", "壽司郎", "元氣", "譚仔", "三哥", "茶餐廳", "酒樓", "餐廳"
        ]),
        ("Groceries", [
            "wellcome", "parknshop", "fusion", "marketplace", "city'super", "donki", "don don donki",
            "aeon", "yata", "759", "7-eleven", "7 eleven", "circle k", "lung fung", "龍豐",
            "ichicake", "cake", "bake", "bodybuilding", "kpay*", "bindo*", "mall", "mart", "store",
            "mannings", "watsons", "惠康", "百佳", "一田", "阿信屋", "便利店", "超市", "萬寧", "屈臣氏"
        ]),
        ("Bills & Utilities", [
            "clp", "towngas", "hkelectric", "autotoll", "water supplies", "hkbn", "pccw", "smartone", "csl", "3hk", "cmhk", "broadband",
            "中電", "港燈", "煤氣", "水費", "香港寬頻", "電訊盈科"
        ]),
        ("Entertainment", [
            "netflix", "spotify", "apple.com/bill", "itunes", "icloud", "youtube", "disney",
            "mcl", "golden harvest", "cinema", "steam", "playstation", "nintendo"
        ]),
        ("Health & Fitness", [
            "panadol", "clinic", "hospital", "dental", "pharmacy", "gym", "fitness",
            "診所", "醫院", "藥房"
        ]),
        ("Octopus", [
            "wallet purchase", "train", "mtr", "bus", "kmb", "citybus", "nwfb", "tram", "ferry",
            "octopus", "港鐵", "九巴", "城巴", "新巴", "八達通"
        ]),
        ("Transport", [
            "star ferry", "taxi", "uber", "tunnel", "hketoll", "peak tram", "light rail", "green minibus", "red minibus",
            "suica", "pasmo", "icoca", "transit", "天星小輪", "的士", "電車", "輕鐵", "小巴"
        ])
    ]

    // MARK: 4. Zero-Charge Entry Gate / Card Read Detector
    public static func isZeroChargeEntryNotification(_ text: String) -> Bool {
        let lower = text.lowercased()
        let ignorePhrases = [
            "card read",
            "trip in progress",
            "no charge for this transaction",
            "there was no charge",
            "無須收費",
            "行程進行中",
            "已讀取"
        ]
        return ignorePhrases.contains { lower.contains($0) }
    }

    // MARK: 5. Octopus Auto Top-Up (AAVS) Detector
    public static func isAAVSTopUp(merchant: String?, fullText: String?) -> Bool {
        let m = (merchant ?? "").lowercased()
        let f = (fullText ?? "").lowercased()
        let combined = "\(m) \(f)"
        let aavsKeywords = [
            "octopus cards", "aavs", "top up", "top-up",
            "auto add value", "octopus reload", "自動增值", "八達通增值"
        ]
        return aavsKeywords.contains { combined.contains($0) }
    }

    // MARK: 6. Strip Remaining Card Balance Sentences
    public static func stripBalanceSentences(_ text: String) -> String {
        var result = text
        let balancePatterns = [
            #"your\s+(?:new|current|remaining)?\s*balance\s+is\s*(?:HK\$|HKD|US\$|USD|\$|¥|£|€)?\s*[0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?\.?"#,
            #"balance\s*(?:is|:)\s*(?:HK\$|HKD|US\$|USD|\$|¥|£|€)?\s*[0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?\.?"#,
            #"(?:最新|當前|剩餘)?餘額(?:為|是|:|：)?\s*(?:HK\$|HKD|\$)?\s*[0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?\.?"#,
            #"there\s+was\s+no\s+charge\s+for\s+this\s+transaction\.?"#
        ]
        for pat in balancePatterns {
            if let regex = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: 7. Extract Dynamic Fare & Merchant from Notification Subtitle / Body
    public static func extractAmountAndMerchant(
        subtitleOrMerchant: String?,
        bodyOrNotificationText: String?,
        notesText: String? = nil
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
        let currencyPattern = #"(?:HK\$|HKD|US\$|USD|\$|¥|£|€)\s*([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)"#

        if let regex = try? NSRegularExpression(pattern: currencyPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: combinedCleaned, range: NSRange(combinedCleaned.startIndex..., in: combinedCleaned)),
           let numRange = Range(match.range(at: 1), in: combinedCleaned) {
            let numStr = combinedCleaned[numRange].replacingOccurrences(of: ",", with: "")
            detectedAmount = Double(numStr)
        }

        if detectedAmount == nil {
            let decimalPattern = #"(?<![0-9])([0-9]+(?:\.[0-9]{1,2}))(?![0-9])"#
            if let regex = try? NSRegularExpression(pattern: decimalPattern),
               let match = regex.firstMatch(in: combinedCleaned, range: NSRange(combinedCleaned.startIndex..., in: combinedCleaned)),
               let numRange = Range(match.range(at: 1), in: combinedCleaned) {
                detectedAmount = Double(combinedCleaned[numRange])
            }
        }

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
        let merchantPatterns = [
            #"(?:for|at|to|in|from|•)\s+([A-Za-z0-9\*\s&\.'\-_]+)"#,
            #"於\s*([^\s]+)\s*(?:消費|付款|扣除)"#
        ]
        for pat in merchantPatterns {
            if let regex = try? NSRegularExpression(pattern: pat, options: .caseInsensitive),
               let match = regex.firstMatch(in: primarySource, range: NSRange(primarySource.startIndex..., in: primarySource)),
               let mRange = Range(match.range(at: 1), in: primarySource) {
                let candidate = String(primarySource[mRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty && candidate.lowercased() != "octopus" {
                    return (detectedAmount, candidate)
                }
            }
        }

        var cleaned = primarySource
        if let regex = try? NSRegularExpression(pattern: currencyPattern, options: .caseInsensitive) {
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
        }
        let boilerplates = ["for", "spent", "paid", "payment", "transaction", "octopus", "八達通", "已扣除", "扣除", "消費", "付款", "at", "via", "•", "|", "-", "."]
        for word in boilerplates {
            cleaned = cleaned.replacingOccurrences(of: word, with: " ", options: .caseInsensitive)
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return (detectedAmount, cleaned.isEmpty ? nil : cleaned)
    }

    // MARK: 8. POS Prefix Stripper & Merchant Normalizer
    public static func stripPOSPrefixes(_ raw: String) -> String {
        var result = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = result.lowercased()
        for prefix in posPrefixes {
            if lower.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return result
    }

    public static func normalizeMerchantName(from rawMerchant: String?, cardName: String? = nil) -> String {
        let rawClean = rawMerchant?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if rawClean.isEmpty || rawClean.lowercased() == "wallet purchase" {
            return "Wallet Purchase"
        }

        let cleaned = stripPOSPrefixes(rawClean)
        let lower = cleaned.lowercased()

        for rule in canonicalMerchantRules {
            if rule.keywords.contains(where: { lower == $0 || lower.contains($0) }) {
                return rule.canonicalName
            }
        }
        return cleaned.isEmpty ? rawClean : cleaned
    }

    // MARK: 9. 100% Data-Driven Category Inference
    public static func inferCategoryName(for merchant: String, rawMerchant: String? = nil, cardName: String? = nil) -> String {
        let cleanMerch = merchant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rawLower = (rawMerchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanCard = (cardName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if cleanMerch.isEmpty {
            return "Octopus"
        }

        let searchTarget = "\(cleanMerch) \(rawLower) \(cleanCard)"
        for rule in categoryRules {
            if rule.keywords.contains(where: { searchTarget.contains($0) }) {
                return rule.category
            }
        }

        return "Groceries"
    }

    public static func iconForCategory(_ name: String) -> String {
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

    public static func colorForCategory(_ name: String) -> String {
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

    // MARK: 10. Fuzzy Card Token Matcher
    public static func findMatchingAccountName(incomingCardName: String, existingNames: [String]) -> String? {
        let rawCard = incomingCardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawCard.isEmpty else { return nil }

        if let direct = existingNames.first(where: {
            $0.localizedCaseInsensitiveCompare(rawCard) == .orderedSame ||
            $0.localizedCaseInsensitiveContains(rawCard) ||
            rawCard.localizedCaseInsensitiveContains($0)
        }) {
            return direct
        }

        let stopWords: Set<String> = ["card", "credit", "debit", "bank", "the", "of", "hk", "visa", "mastercard", "pay", "apple", "wallet", "plat", "platinum"]
        let incomingTokens = Set(
            rawCard.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 && !stopWords.contains($0) }
        )
        guard !incomingTokens.isEmpty else { return nil }

        return existingNames.first { candidate in
            let candidateTokens = Set(
                candidate.lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { $0.count >= 3 && !stopWords.contains($0) }
            )
            return !incomingTokens.isDisjoint(with: candidateTokens)
        }
    }
}
