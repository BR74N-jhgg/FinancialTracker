//
//  AnalyticsView.swift
//  Worthly
//

import SwiftUI
import SwiftData

public struct AnalyticsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var transactions: [TransactionItem]
    @AppStorage("monthly_budget") private var monthlyBudget: Double = 15000.0
    @AppStorage("default_currency") private var defaultCurrency: String = "HKD"
    @AppStorage("app_language") private var appLanguage: String = "en"
    
    // Default to Day of Week
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
            #if DEBUG
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if transactions.isEmpty {
                        Button {
                            withAnimation {
                                loadSampleData()
                            }
                        } label: {
                            Label(L10n.tr("Add Sample Data", lang: appLanguage), systemImage: "sparkles")
                        }
                        .lineLimit(1)
                    }
                }
            }
            #endif
        }
    }
    
    #if DEBUG
    private func loadSampleData() {
        SampleDataSeeder.seedAll(context: modelContext)
        let existingCategories = (try? modelContext.fetch(FetchDescriptor<CategoryItem>())) ?? []
        let existingMethods = (try? modelContext.fetch(FetchDescriptor<PaymentMethodItem>())) ?? []
        let categoryMap = Dictionary(uniqueKeysWithValues: existingCategories.map { ($0.name, $0) })
        let methodMap = Dictionary(uniqueKeysWithValues: existingMethods.map { ($0.name, $0) })
        
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
            SeedItem(daysAgo: 0, hour: 8, amount: 18.5, type: .expense, categoryName: "Transport", paymentMethodName: "Octopus", merchant: "MTR", notes: "Commute to Central"),
            SeedItem(daysAgo: 0, hour: 9, amount: 46.0, type: .expense, categoryName: "Dining", paymentMethodName: "Apple Pay", merchant: "Starbucks", notes: "Oat flat white"),
            SeedItem(daysAgo: 1, hour: 12, amount: 185.0, type: .expense, categoryName: "Groceries", paymentMethodName: "Apple Pay", merchant: "Don Don Donki", notes: "Japanese snacks")
        ]
        
        for seed in seeds {
            let cat = categoryMap[seed.categoryName]
            let pm = methodMap[seed.paymentMethodName]
            let date = dateAgo(days: seed.daysAgo, hour: seed.hour)
            let item = TransactionItem(
                timestamp: date,
                amount: seed.amount,
                currency: "HKD",
                merchant: seed.merchant,
                notes: seed.notes,
                type: seed.type,
                category: cat,
                paymentMethod: pm
            )
            modelContext.insert(item)
        }
        AppDataStore.saveContext(modelContext)
        AccountBalanceManager.shared.recalculateBalances(context: modelContext)
        WidgetSyncManager.shared.syncWidget(context: modelContext)
    }
    #endif
}
