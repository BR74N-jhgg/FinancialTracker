//
//  Transaction.swift
//  Worthly
//

import Foundation
import SwiftData

public enum TransactionType: String, Codable, CaseIterable {
    case expense = "Expense"
    case income = "Income"
    case transfer = "Transfer"
    
    public var localizedKey: String {
        rawValue
    }
}

public enum RecurrenceFrequency: String, Codable, CaseIterable {
    case never = "Never"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case yearly = "Yearly"
}

@Model
public final class TransactionItem {
    public var id: UUID
    public var timestamp: Date
    public var amount: Double
    public var currency: String
    public var merchant: String
    public var notes: String
    public var typeRaw: String
    public var isExcludedFromBudget: Bool
    
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
        isExcludedFromBudget: Bool = false
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
    }
}

// MARK: - Recurring Fixed Bill / Subscription Model
@Model
public final class RecurringRuleItem {
    public var id: UUID
    public var title: String
    public var amount: Double
    public var currency: String
    public var typeRaw: String
    public var recurrenceFrequencyRaw: String
    public var nextDueDate: Date
    public var lastProcessedDate: Date?
    public var isExcludedFromBudget: Bool
    
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
        isExcludedFromBudget: Bool = false
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
    }
}
