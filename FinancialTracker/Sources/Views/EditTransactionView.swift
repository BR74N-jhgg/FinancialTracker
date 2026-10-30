import SwiftUI
import SwiftData

public struct EditTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CategoryItem.name) private var categories: [CategoryItem]
    @Query(sort: \PaymentMethodItem.name) private var paymentMethods: [PaymentMethodItem]
    @AppStorage("default_currency") private var defaultCurrency: String = "HKD"
    @AppStorage("app_language") private var appLanguage: String = "en"
    
    @Bindable var item: TransactionItem
    
    @State private var amountString: String
    @State private var merchant: String
    @State private var selectedCategoryId: UUID?
    @State private var selectedPaymentMethodId: UUID?
    @State private var toPaymentMethodId: UUID?
    @State private var type: TransactionType
    @State private var date: Date
    @State private var notes: String
    @State private var isExcludedFromBudget: Bool
    @State private var recurrence: RecurrenceFrequency = .never
    @State private var showingDeleteConfirmation = false
    @State private var showingCategoryManager = false
    @State private var showingPaymentManager = false
    
    public init(item: TransactionItem) {
        self.item = item
        _amountString = State(initialValue: String(format: "%.2f", item.amount))
        _merchant = State(initialValue: item.merchant)
        _selectedCategoryId = State(initialValue: item.category?.id)
        _selectedPaymentMethodId = State(initialValue: item.paymentMethod?.id)
        _toPaymentMethodId = State(initialValue: item.toPaymentMethod?.id)
        _type = State(initialValue: item.type)
        _date = State(initialValue: item.timestamp)
        _notes = State(initialValue: item.notes)
        _isExcludedFromBudget = State(initialValue: item.isExcludedFromBudget)
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section(String(format: "%@ (%@)", L10n.tr("Amount", lang: appLanguage), defaultCurrency)) {
                    TextField("0.00", text: $amountString)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(typeColor)
                        .lineLimit(1)
                }
                
                Section("Type") {
                    Picker("Transaction Type", selection: $type) {
                        ForEach(TransactionType.allCases, id: \.self) { t in
                            Text(L10n.tr(t.rawValue, lang: appLanguage)).tag(t).lineLimit(1)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                if type == .transfer {
                    Section(L10n.tr("Transfer", lang: appLanguage)) {
                        Picker(L10n.tr("From Account", lang: appLanguage), selection: $selectedPaymentMethodId) {
                            Text("Select Source Account").tag(nil as UUID?)
                            ForEach(paymentMethods) { method in
                                Label(method.name, systemImage: method.iconName)
                                    .tag(method.id as UUID?)
                            }
                        }
                        
                        Picker(L10n.tr("To Account", lang: appLanguage), selection: $toPaymentMethodId) {
                            Text("Select Destination Account").tag(nil as UUID?)
                            ForEach(paymentMethods.filter { $0.id != selectedPaymentMethodId }) { method in
                                Label(method.name, systemImage: method.iconName)
                                    .tag(method.id as UUID?)
                            }
                        }
                        
                        DatePicker("Date & Time", selection: $date)
                    }
                } else {
                    Section("Details") {
                        TextField("Merchant (e.g. Keeta, MTR)", text: $merchant)
                            .lineLimit(1)
                        
                        Picker("Category", selection: $selectedCategoryId) {
                            Text("Uncategorized").tag(nil as UUID?)
                            ForEach(categories) { cat in
                                Label(cat.name, systemImage: cat.iconName)
                                    .tag(cat.id as UUID?)
                                    .lineLimit(1)
                            }
                        }
                        
                        Picker(L10n.tr("Account", lang: appLanguage), selection: $selectedPaymentMethodId) {
                            Text("Unspecified").tag(nil as UUID?)
                            ForEach(paymentMethods) { method in
                                Label(method.name, systemImage: method.iconName)
                                    .tag(method.id as UUID?)
                                    .lineLimit(1)
                            }
                        }
                        
                        DatePicker("Date & Time", selection: $date)
                            .lineLimit(1)
                    }
                    
                    if type == .expense {
                        Section {
                            Toggle(isOn: $isExcludedFromBudget) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.tr("Exclude from Budget", lang: appLanguage))
                                        .font(.body)
                                    Text("Reimbursable expenses, loans, or split dinners that friends will repay.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                
                Section {
                    Button {
                        showingCategoryManager = true
                    } label: {
                        Label("Manage Categories", systemImage: "tag.fill")
                            .lineLimit(1)
                    }
                    
                    Button {
                        showingPaymentManager = true
                    } label: {
                        Label(L10n.tr("Accounts", lang: appLanguage), systemImage: "building.columns.fill")
                            .lineLimit(1)
                    }
                }
                
                Section(appLanguage == "zh-HK" ? "定期重覆記帳" : "Repeating Payment") {
                    Picker(appLanguage == "zh-HK" ? "週期" : "Repeat", selection: $recurrence) {
                        ForEach(RecurrenceFrequency.allCases, id: \.self) { freq in
                            Text(L10n.tr(freq.rawValue, lang: appLanguage)).tag(freq)
                        }
                    }
                }
                
                Section("Notes (Optional)") {
                    TextField("Add details...", text: $notes)
                        .lineLimit(1)
                }
                
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete Log", systemImage: "trash.fill")
                                .font(.body.bold())
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Edit Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Cancel", lang: appLanguage)) { dismiss() }.lineLimit(1)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("Done", lang: appLanguage)) {
                        saveChanges()
                        dismiss()
                    }
                    .disabled(Double(amountString) == nil || (Double(amountString) ?? 0) <= 0 || (type == .transfer && (selectedPaymentMethodId == nil || toPaymentMethodId == nil)))
                    .bold()
                    .lineLimit(1)
                }
            }
            .confirmationDialog("Are you sure you want to delete this log?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Log", role: .destructive) {
                    deleteItem()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showingCategoryManager) {
                CategoryManagementView()
            }
            .sheet(isPresented: $showingPaymentManager) {
                PaymentMethodManagementView()
            }
            .onAppear {
                if selectedCategoryId == nil, let catName = item.category?.name {
                    selectedCategoryId = categories.first(where: { $0.name == catName })?.id
                }
                if selectedPaymentMethodId == nil, let pmName = item.paymentMethod?.name {
                    selectedPaymentMethodId = paymentMethods.first(where: { $0.name == pmName })?.id
                }
            }
        }
    }
    
    private var typeColor: Color {
        switch type {
        case .expense: return .blue
        case .income: return .green
        case .transfer: return .orange
        }
    }
    
    private func saveChanges() {
        guard let amount = Double(amountString) else { return }
        let previousAccountIds = Set([item.paymentMethod?.id, item.toPaymentMethod?.id].compactMap { $0 })
        
        let resolvedCategory = categories.first(where: { $0.id == selectedCategoryId })
        let resolvedPaymentMethod = paymentMethods.first(where: { $0.id == selectedPaymentMethodId })
        let resolvedToPaymentMethod = paymentMethods.first(where: { $0.id == toPaymentMethodId })
        
        item.amount = amount
        if type == .transfer {
            let fromName = resolvedPaymentMethod?.name ?? "Account"
            let toName = resolvedToPaymentMethod?.name ?? "Account"
            item.merchant = "\(fromName) → \(toName)"
            item.category = nil
            item.toPaymentMethod = resolvedToPaymentMethod
            item.isExcludedFromBudget = false
        } else {
            item.merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
            item.category = resolvedCategory
            item.toPaymentMethod = nil
            item.isExcludedFromBudget = type == .expense ? isExcludedFromBudget : false
        }
        item.paymentMethod = resolvedPaymentMethod
        item.type = type
        item.timestamp = date
        item.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if recurrence != .never {
            let calendar = Calendar.current
            let nextDue: Date = {
                switch recurrence {
                case .weekly:
                    return calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date.addingTimeInterval(7 * 86400)
                case .monthly:
                    return calendar.date(byAdding: .month, value: 1, to: date) ?? date.addingTimeInterval(30 * 86400)
                case .yearly:
                    return calendar.date(byAdding: .year, value: 1, to: date) ?? date.addingTimeInterval(365 * 86400)
                case .never:
                    return date
                }
            }()
            
            let rule = RecurringRuleItem(
                title: item.merchant,
                amount: amount,
                currency: defaultCurrency,
                type: type,
                recurrenceFrequency: recurrence,
                nextDueDate: nextDue,
                lastProcessedDate: date,
                category: resolvedCategory,
                paymentMethod: resolvedPaymentMethod,
                toPaymentMethod: type == .transfer ? resolvedToPaymentMethod : nil,
                isExcludedFromBudget: isExcludedFromBudget
            )
            modelContext.insert(rule)
        }
        
        AppDataStore.saveContext(modelContext)
        let updatedAccountIds = Set([resolvedPaymentMethod?.id, type == .transfer ? resolvedToPaymentMethod?.id : nil].compactMap { $0 })
        let affectedIds = previousAccountIds.union(updatedAccountIds)
        AccountBalanceManager.shared.recalculateBalances(
            forAccountIds: affectedIds.isEmpty ? nil : affectedIds,
            context: modelContext
        )
        WidgetSyncManager.shared.syncWidget(context: modelContext)
    }
    
    private func deleteItem() {
        let affectedIds = Set([item.paymentMethod?.id, item.toPaymentMethod?.id].compactMap { $0 })
        modelContext.delete(item)
        AppDataStore.saveContext(modelContext)
        AccountBalanceManager.shared.recalculateBalances(
            forAccountIds: affectedIds.isEmpty ? nil : affectedIds,
            context: modelContext
        )
        WidgetSyncManager.shared.syncWidget(context: modelContext)
    }
}
