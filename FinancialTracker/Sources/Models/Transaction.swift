//
//  Transaction.swift
//  Worthly
//

import Foundation
import SwiftData

public enum TransactionType: String, Codable, CaseIterable, Sendable {
    case expense = "Expense"
    case income = "Income"
    case transfer = "Transfer"
    
    public var localizedKey: String {
        rawValue
    }
}

public enum RecurrenceFrequency: String, Codable, CaseIterable, Sendable {
    case never = "Never"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case yearly = "Yearly"
}

@Model
public final class TransactionItem {
    public var id: UUID = UUID()
    public var timestamp: Date = Date()
    public var amount: Double = 0.0
    public var currency: String = "HKD"
    public var merchant: String = ""
    public var notes: String = ""
    public var typeRaw: String = TransactionType.expense.rawValue
    public var isExcludedFromBudget: Bool = false
    /// Optional link to the RecurringRuleItem that generated or is associated with this transaction (9.1-3)
    public var ruleId: UUID? = nil
    
    // MARK: - Relationships with Safe Nullify Delete Rules
    @Relationship(deleteRule: .nullify)
    public var category: CategoryItem?
    
    @Relationship(deleteRule: .nullify)
    public var paymentMethod: PaymentMethodItem?          // Source Account (or account for Expense/Income)
    
    @Relationship(deleteRule: .nullify)
    public var toPaymentMethod: PaymentMethodItem?        // Destination Account (for Transfers)
    
    public var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        amount: Double,
        currency: String = "HKD",
        merchant: String = "",
        notes: String = "",
        type: TransactionType = .expense,
        category: CategoryItem? = nil,
        paymentMethod: PaymentMethodItem? = nil,
        toPaymentMethod: PaymentMethodItem? = nil,
        isExcludedFromBudget: Bool = false,
        ruleId: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.amount = amount
        self.currency = currency
        self.merchant = merchant
        self.notes = notes
        self.typeRaw = type.rawValue
        self.category = category
        self.paymentMethod = paymentMethod
        self.toPaymentMethod = toPaymentMethod
        self.isExcludedFromBudget = isExcludedFromBudget
        self.ruleId = ruleId
    }
}

// MARK: - Recurring Fixed Bill / Subscription Model
@Model
public final class RecurringRuleItem {
    public var id: UUID = UUID()
    public var title: String = ""
    public var amount: Double = 0.0
    public var currency: String = "HKD"
    public var typeRaw: String = TransactionType.expense.rawValue
    public var recurrenceFrequencyRaw: String = RecurrenceFrequency.monthly.rawValue
    public var nextDueDate: Date = Date()
    public var lastProcessedDate: Date? = nil
    public var isExcludedFromBudget: Bool = false
    /// Allows users to pause a recurring subscription without deleting its rule history (9.1-2)
    public var isPaused: Bool = false
    
    @Relationship(deleteRule: .nullify)
    public var category: CategoryItem?
    
    @Relationship(deleteRule: .nullify)
    public var paymentMethod: PaymentMethodItem?
    
    @Relationship(deleteRule: .nullify)
    public var toPaymentMethod: PaymentMethodItem?
    
    public var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }
    
    public var recurrenceFrequency: RecurrenceFrequency {
        get { RecurrenceFrequency(rawValue: recurrenceFrequencyRaw) ?? .never }
        set { recurrenceFrequencyRaw = newValue.rawValue }
    }
    
    public init(
        id: UUID = UUID(),
        title: String,
        amount: Double,
        currency: String = "HKD",
        type: TransactionType = .expense,
        recurrenceFrequency: RecurrenceFrequency = .monthly,
        nextDueDate: Date = Date(),
        lastProcessedDate: Date? = nil,
        category: CategoryItem? = nil,
        paymentMethod: PaymentMethodItem? = nil,
        toPaymentMethod: PaymentMethodItem? = nil,
        isExcludedFromBudget: Bool = false,
        isPaused: Bool = false
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.currency = currency
        self.typeRaw = type.rawValue
        self.recurrenceFrequencyRaw = recurrenceFrequency.rawValue
        self.nextDueDate = nextDueDate
        self.lastProcessedDate = lastProcessedDate
        self.category = category
        self.paymentMethod = paymentMethod
        self.toPaymentMethod = toPaymentMethod
        self.isExcludedFromBudget = isExcludedFromBudget
        self.isPaused = isPaused
    }
}

// MARK: - SwiftData Versioned Schema & Migration Plan (Phase 1 Foundation)
public enum WorthlySchemaV1: VersionedSchema {
    public static var versionIdentifier = Schema.Version(1, 3, 0)
    
    public static var models: [any PersistentModel.Type] {
        [
            TransactionItem.self,
            CategoryItem.self,
            PaymentMethodItem.self,
            RecurringRuleItem.self
        ]
    }
}

public enum WorthlyMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [WorthlySchemaV1.self]
    }
    
    public static var stages: [MigrationStage] {
        []
    }
}
