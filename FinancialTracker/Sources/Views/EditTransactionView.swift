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
    @State private var selectedCategory: CategoryItem?
    @State private var selectedPaymentMethod: PaymentMethodItem?
    @State private var toPaymentMethod: PaymentMethodItem?
    @State private var type: TransactionType
    @State private var date: Date
    @State private var notes: String
    @State private var isExcludedFromBudget: Bool
    @State private var showingDeleteConfirmation = false
    @State private var showingCategoryManager = false
    @State private var showingPaymentManager = false
    
    public init(item: TransactionItem) {
        self.item = item
        _amountString = State(initialValue: String(format: "%.2f", item.amount))
        _merchant = State(initialValue: item.merchant)
        _selectedCategory = State(initialValue: item.category)
        _selectedPaymentMethod = State(initialValue: item.paymentMethod)
        _toPaymentMethod = State(initialValue: item.toPaymentMethod)
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
                        Picker(L10n.tr("From Account", lang: appLanguage), selection: $selectedPaymentMethod) {
                            Text("Select Source Account").tag(nil as PaymentMethodItem?)
                            ForEach(paymentMethods) { method in
                                Label(method.name, systemImage: method.iconName)
                                    .tag(method as PaymentMethodItem?)
                            }
                        }
                        
                        Picker(L10n.tr("To Account", lang: appLanguage), selection: $toPaymentMethod) {
                            Text("Select Destination Account").tag(nil as PaymentMethodItem?)
                            ForEach(paymentMethods.filter { $0.id != selectedPaymentMethod?.id }) { method in
                                Label(method.name, systemImage: method.iconName)
                                    .tag(method as PaymentMethodItem?)
                            }
                        }
                        
                        DatePicker("Date & Time", selection: $date)
                    }
                } else {
                    Section("Details") {
                        TextField("Merchant (e.g. Keeta, MTR)", text: $merchant)
                            .lineLimit(1)
                        
                        Picker("Category", selection: $selectedCategory) {
                            Text("Uncategorized").tag(nil as CategoryItem?)
                            ForEach(categories) { cat in
                                Label(cat.name, systemImage: cat.iconName)
                                    .tag(cat as CategoryItem?)
                                    .lineLimit(1)
                            }
                        }
                        
                        Picker(L10n.tr("Account", lang: appLanguage), selection: $selectedPaymentMethod) {
                            Text("Unspecified").tag(nil as PaymentMethodItem?)
                            ForEach(paymentMethods) { method in
                                HStack {
                                    Label(method.name, systemImage: method.iconName)
                                    Spacer()
                                    Text(String(format: "%@ %.0f", defaultCurrency, method.currentBalance))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .tag(method as PaymentMethodItem?)
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
                    .disabled(Double(amountString) == nil || (Double(amountString) ?? 0) <= 0 || (type == .transfer && (selectedPaymentMethod == nil || toPaymentMethod == nil)))
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
        item.amount = amount
        if type == .transfer {
            let fromName = selectedPaymentMethod?.name ?? "Account"
            let toName = toPaymentMethod?.name ?? "Account"
            item.merchant = "\(fromName) → \(toName)"
            item.category = nil
            item.toPaymentMethod = toPaymentMethod
            item.isExcludedFromBudget = false
        } else {
            item.merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
            item.category = selectedCategory
            item.toPaymentMethod = nil
            item.isExcludedFromBudget = type == .expense ? isExcludedFromBudget : false
        }
        item.paymentMethod = selectedPaymentMethod
        item.type = type
        item.timestamp = date
        item.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        try? modelContext.save()
        AccountBalanceManager.shared.recalculateBalances(context: modelContext)
        WidgetSyncManager.shared.syncWidget(context: modelContext)
    }
    
    private func deleteItem() {
        modelContext.delete(item)
        try? modelContext.save()
        AccountBalanceManager.shared.recalculateBalances(context: modelContext)
        WidgetSyncManager.shared.syncWidget(context: modelContext)
    }
}
