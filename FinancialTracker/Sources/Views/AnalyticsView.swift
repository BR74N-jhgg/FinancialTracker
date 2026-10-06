//
//  AnalyticsView.swift
//  FinancialTracker
//

import SwiftUI
import SwiftData

public struct AnalyticsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var transactions: [TransactionItem]
    @AppStorage("monthly_budget") private var monthlyBudget: Double = 15000.0
    @AppStorage("default_currency") private var defaultCurrency: String = "HKD"
    @AppStorage("app_language") private var appLanguage: String = "en"
    
    // Default to Option 3: Day of Week
    @State private var selectedReport: AnalyticsReportType = .dayOfWeek
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Report Type Horizontal Selector
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(AnalyticsReportType.allCases) { report in
                                Button {
                                    selectedReport = report
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: report.icon)
                                            .font(.caption2)
                                        Text(L10n.tr(report.rawValue, lang: appLanguage))
                                            .font(.caption.bold())
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(selectedReport == report ? Color.blue : Color(.secondarySystemFill))
                                    .foregroundStyle(selectedReport == report ? .white : .primary)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 4)
                    }
                    
                    if transactions.isEmpty {
                        ContentUnavailableView(
                            L10n.tr("No Data Yet", lang: appLanguage),
                            systemImage: "chart.bar.xaxis",
                            description: Text(L10n.tr("Log your daily expenses and income to see detailed financial trends and analytics.", lang: appLanguage))
                        )
                        .padding(.top, 40)
                    } else {
                        // Render the Selected Modular Report
                        switch selectedReport {
                        case .dayOfWeek:
                            DayOfWeekReportView(transactions: transactions, currency: defaultCurrency)
                        case .monthlyPacing:
                            MonthlyPacingReportView(transactions: transactions, budget: monthlyBudget, currency: defaultCurrency)
                        case .cashFlow:
                            CashFlowReportView(transactions: transactions, currency: defaultCurrency)
                        case .paymentMethods:
                            PaymentMethodsReportView(transactions: transactions, currency: defaultCurrency)
                        case .topMerchants:
                            TopMerchantsReportView(transactions: transactions, currency: defaultCurrency)
                        case .categories:
                            CategoryBreakdownReportView(transactions: transactions, currency: defaultCurrency)
                        }
                    }
                }
                .padding(.bottom, 16)
            }
            .appPullToRefresh()
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L10n.tr("Analytics", lang: appLanguage))
            .toolbar {
            }
        }
    }
    
    private func loadSampleData() {
        var categoryMap: [String: CategoryItem] = [:]
        let catDescriptor = FetchDescriptor<CategoryItem>()
        if let existingCategories = try? modelContext.fetch(catDescriptor), !existingCategories.isEmpty {
            for cat in existingCategories {
                categoryMap[cat.name] = cat
            }
        } else {
            for def in CategoryItem.defaultCategories {
                let cat = CategoryItem(name: def.name, iconName: def.icon, colorHex: def.color)
                modelContext.insert(cat)
                categoryMap[def.name] = cat
            }
        }
        
        var methodMap: [String: PaymentMethodItem] = [:]
        let pmDescriptor = FetchDescriptor<PaymentMethodItem>()
        if let existingMethods = try? modelContext.fetch(pmDescriptor), !existingMethods.isEmpty {
            for pm in existingMethods {
                methodMap[pm.name] = pm
            }
        } else {
            for def in PaymentMethodItem.defaultMethods {
                let pm = PaymentMethodItem(name: def.name, iconName: def.icon, colorHex: def.color)
                modelContext.insert(pm)
                methodMap[def.name] = pm
            }
        }
        
        let calendar = Calendar.current
        let now = Date()
        func dateAgo(days: Int, hour: Int = 13, minute: Int = 30) -> Date {
            var date = calendar.date(byAdding: .day, value: -days, to: now) ?? now
            date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
            return date
        }
        
        struct SeedItem {
            let daysAgo: Int
            let hour: Int
            let amount: Double
            let type: TransactionType
            let categoryName: String
            let paymentMethodName: String
            let merchant: String
            let notes: String
        }
        
        let seeds: [SeedItem] = [
            SeedItem(daysAgo: 1, hour: 9, amount: 35000.0, type: .income, categoryName: "Other", paymentMethodName: "Bank Transfer / FPS", merchant: "Tech Corp Ltd", notes: "Monthly Salary"),
            SeedItem(daysAgo: 14, hour: 15, amount: 4800.0, type: .income, categoryName: "Other", paymentMethodName: "Bank Transfer / FPS", merchant: "Client Project", notes: "Freelance UI milestone"),
            SeedItem(daysAgo: 0, hour: 8, amount: 18.5, type: .expense, categoryName: "Transport", paymentMethodName: "Octopus", merchant: "MTR", notes: "Commute to Central"),
            SeedItem(daysAgo: 0, hour: 9, amount: 46.0, type: .expense, categoryName: "Dining", paymentMethodName: "Apple Pay", merchant: "Starbucks", notes: "Oat flat white"),
            SeedItem(daysAgo: 0, hour: 13, amount: 62.0, type: .expense, categoryName: "Dining", paymentMethodName: "Octopus", merchant: "Café de Coral", notes: "Pork chop rice"),
            SeedItem(daysAgo: 1, hour: 12, amount: 185.0, type: .expense, categoryName: "Groceries", paymentMethodName: "Apple Pay", merchant: "Don Don Donki", notes: "Japanese snacks"),
            SeedItem(daysAgo: 1, hour: 18, amount: 22.0, type: .expense, categoryName: "Transport", paymentMethodName: "Octopus", merchant: "MTR", notes: "Commute home"),
            SeedItem(daysAgo: 1, hour: 20, amount: 198.0, type: .expense, categoryName: "Dining", paymentMethodName: "Apple Pay", merchant: "Deliveroo", notes: "Thai green curry dinner"),
            SeedItem(daysAgo: 2, hour: 11, amount: 345.5, type: .expense, categoryName: "Groceries", paymentMethodName: "Credit Card", merchant: "Wellcome", notes: "Weekly groceries"),
            SeedItem(daysAgo: 2, hour: 16, amount: 44.0, type: .expense, categoryName: "Dining", paymentMethodName: "Octopus", merchant: "Pacific Coffee", notes: "Americano"),
            SeedItem(daysAgo: 3, hour: 10, amount: 520.0, type: .expense, categoryName: "Health & Fitness", paymentMethodName: "Credit Card", merchant: "24/7 Fitness", notes: "Gym membership"),
            SeedItem(daysAgo: 3, hour: 15, amount: 399.0, type: .expense, categoryName: "Shopping", paymentMethodName: "Apple Pay", merchant: "Uniqlo", notes: "AIRism shirts"),
            SeedItem(daysAgo: 4, hour: 8, amount: 42.0, type: .expense, categoryName: "Dining", paymentMethodName: "Octopus", merchant: "Fairwood", notes: "Breakfast satay beef"),
            SeedItem(daysAgo: 4, hour: 18, amount: 12.8, type: .expense, categoryName: "Transport", paymentMethodName: "Octopus", merchant: "KMB Bus", notes: "Bus 102"),
            SeedItem(daysAgo: 5, hour: 14, amount: 160.0, type: .expense, categoryName: "Entertainment", paymentMethodName: "Credit Card", merchant: "Broadway Cinema", notes: "IMAX movie"),
            SeedItem(daysAgo: 5, hour: 19, amount: 235.0, type: .expense, categoryName: "Dining", paymentMethodName: "Apple Pay", merchant: "Shake Shack", notes: "Dinner burger"),
            SeedItem(daysAgo: 6, hour: 15, amount: 480.0, type: .expense, categoryName: "Groceries", paymentMethodName: "Credit Card", merchant: "city'super", notes: "Steak and olive oil"),
            SeedItem(daysAgo: 6, hour: 21, amount: 140.0, type: .expense, categoryName: "Entertainment", paymentMethodName: "Apple Pay", merchant: "Netflix & Spotify", notes: "Digital subs")
        ]
        
        for s in seeds {
            let item = TransactionItem(
                timestamp: dateAgo(days: s.daysAgo, hour: s.hour),
                amount: s.amount,
                currency: defaultCurrency,
                merchant: s.merchant,
                notes: s.notes,
                type: s.type,
                category: categoryMap[s.categoryName],
                paymentMethod: methodMap[s.paymentMethodName]
            )
            modelContext.insert(item)
        }
        try? modelContext.save()
    }
}
