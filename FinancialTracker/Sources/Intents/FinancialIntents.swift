import AppIntents
import SwiftData
import Foundation

public struct LogExpenseIntent: AppIntent {
    public static var title: LocalizedStringResource = "Log Transaction"
    public static var description = IntentDescription("Logs an expense or income transaction into your personal financial tracker.")
    
    public static var openAppWhenRun: Bool = false
    
    @Parameter(title: "Amount", description: "The transaction amount")
    public var amount: Double
    
    @Parameter(title: "Merchant / Title", description: "Merchant name or payee")
    public var merchant: String?
    
    @Parameter(title: "Category", description: "Expense category (e.g. Dining, Transport, Groceries)")
    public var category: String?
    
    @Parameter(title: "Payment Method", description: "e.g. Apple Pay, Octopus, Credit Card, Cash")
    public var paymentMethod: String?
    
    @Parameter(title: "Notes", description: "Optional notes")
    public var notes: String?
    
    public init() {}
    
    public init(amount: Double, merchant: String? = nil, category: String? = nil, paymentMethod: String? = nil, notes: String? = nil) {
        self.amount = amount
        self.merchant = merchant
        self.category = category
        self.paymentMethod = paymentMethod
        self.notes = notes
    }
    
    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = AppDataStore.sharedModelContainer
        let context = container.mainContext
        
        let catDescriptor = FetchDescriptor<CategoryItem>()
        let allCategories = (try? context.fetch(catDescriptor)) ?? []
        let matchedCategory = allCategories.first {
            guard let cat = category else { return false }
            return $0.name.localizedCaseInsensitiveContains(cat)
        } ?? allCategories.first
        
        let pmDescriptor = FetchDescriptor<PaymentMethodItem>()
        let allMethods = (try? context.fetch(pmDescriptor)) ?? []
        let matchedMethod = allMethods.first {
            guard let pm = paymentMethod else { return false }
            return $0.name.localizedCaseInsensitiveContains(pm)
        } ?? allMethods.first
        
        let item = TransactionItem(
            amount: amount,
            currency: "HKD",
            merchant: merchant ?? "General",
            notes: notes ?? "",
            type: .expense,
            category: matchedCategory,
            paymentMethod: matchedMethod,
            isExcludedFromBudget: false
        )
        
        context.insert(item)
        try? context.save()
        
        AccountBalanceManager.shared.recalculateBalances(context: context)
        WidgetSyncManager.shared.syncWidget(context: context)
        
        let categoryDisplayName = matchedCategory?.name ?? "General"
        return .result(dialog: "Logged \(String(format: "HK$%.2f", amount)) for \(merchant ?? categoryDisplayName) successfully.")
    }
}

public struct FinancialShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: [
                "Log an expense in \(.applicationName)",
                "Track spending in \(.applicationName)",
                "Add transaction to \(.applicationName)"
            ],
            shortTitle: "Log Expense",
            systemImageName: "plus.circle.fill"
        )
    }
}
