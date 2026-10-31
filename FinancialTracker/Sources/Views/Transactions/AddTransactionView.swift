import SwiftUI
import SwiftData

public struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CategoryItem.name) private var categories: [CategoryItem]
    @Query(sort: \PaymentMethodItem.name) private var paymentMethods: [PaymentMethodItem]
    
    @AppStorage("default_payment_method") private var defaultPaymentMethod: String = "Apple Pay"
    @AppStorage("app_language") private var appLanguage: String = "en"
    @AppStorage("default_currency") private var defaultCurrency: String = "HKD"
    
    @State private var amountString = ""
    @State private var merchant = ""
    @State private var selectedCategory: CategoryItem?
    @State private var selectedPaymentMethod: PaymentMethodItem?
    @State private var toPaymentMethod: PaymentMethodItem?
    @State private var type: TransactionType = .expense
    @State private var date = Date()
    @State private var notes = ""
    @State private var isExcludedFromBudget = false
    @State private var recurrence: RecurrenceFrequency = .never
    @State private var showingCategoryManager = false
    @State private var showingPaymentManager = false
    @FocusState private var isFieldFocused: Bool
    
    private var presetMerchant: String = ""
    private var presetCategoryName: String? = nil
    private var presetPaymentMethodName: String? = nil
    private var presetAmount: Double? = nil
    
    public init(
        presetMerchant: String = "",
        presetCategoryName: String? = nil,
        presetPaymentMethodName: String? = nil,
        presetAmount: Double? = nil
    ) {
        self.presetMerchant = presetMerchant
        self.presetCategoryName = presetCategoryName
        self.presetPaymentMethodName = presetPaymentMethodName
        self.presetAmount = presetAmount
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section(String(format: "%@ (%@)", L10n.tr("Amount", lang: appLanguage), defaultCurrency)) {
                    TextField("0.00", text: $amountString)
                        .keyboardType(.decimalPad)
                        .focused($isFieldFocused)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(typeColor)
                        .lineLimit(1)
                }
                
                Section {
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
                        TextField("Merchant (e.g. Keeta, MTR, Wellcome)", text: $merchant)
                            .focused($isFieldFocused)
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
                
                Section(appLanguage == "zh-HK" ? "定期重覆記帳" : "Repeating Payment") {
                    Picker(appLanguage == "zh-HK" ? "週期" : "Repeat", selection: $recurrence) {
                        ForEach(RecurrenceFrequency.allCases, id: \.self) { freq in
                            Text(L10n.tr(freq.rawValue, lang: appLanguage)).tag(freq)
                        }
                    }
                }
                
                Section("Notes (Optional)") {
                    TextField("Add details...", text: $notes)
                        .focused($isFieldFocused)
                        .lineLimit(1)
                }
            }
            .navigationTitle(type == .transfer ? L10n.tr("Transfer", lang: appLanguage) : "Log Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Cancel", lang: appLanguage)) { dismiss() }.lineLimit(1)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("Done", lang: appLanguage)) {
                        saveTransaction()
                        dismiss()
                    }
                    .disabled(Double(amountString) == nil || (Double(amountString) ?? 0) <= 0 || (type == .transfer && (selectedPaymentMethod == nil || toPaymentMethod == nil)))
                    .bold()
                    .lineLimit(1)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L10n.tr("Done", lang: appLanguage)) {
                        isFieldFocused = false
                    }
                    .bold()
                    .lineLimit(1)
                }
            }
            .onAppear {
                applyPresetsIfNeeded()
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
    
    private func applyPresetsIfNeeded() {
        if !presetMerchant.isEmpty && merchant.isEmpty {
            merchant = presetMerchant
        }
        if let amt = presetAmount, amountString.isEmpty {
            amountString = String(format: "%.2f", amt)
        }
        if let catName = presetCategoryName, !catName.isEmpty {
            if let match = categories.first(where: { $0.name.localizedCaseInsensitiveContains(catName) }) {
                selectedCategory = match
            }
        } else if selectedCategory == nil, let first = categories.first {
            selectedCategory = first
        }
        
        if let pmName = presetPaymentMethodName, !pmName.isEmpty {
            if let match = paymentMethods.first(where: { $0.name.localizedCaseInsensitiveContains(pmName) }) {
                selectedPaymentMethod = match
            }
        } else if selectedPaymentMethod == nil {
            if let preferred = paymentMethods.first(where: { $0.name.localizedCaseInsensitiveContains(defaultPaymentMethod) }) {
                selectedPaymentMethod = preferred
            } else {
                selectedPaymentMethod = paymentMethods.first
            }
        }
        
        if toPaymentMethod == nil, let second = paymentMethods.first(where: { $0.id != selectedPaymentMethod?.id }) {
            toPaymentMethod = second
        }
    }
    
    private func saveTransaction() {
        guard let amount = Double(amountString) else { return }
        
        let finalMerchant: String
        if type == .transfer {
            let fromName = selectedPaymentMethod?.name ?? "Account"
            let toName = toPaymentMethod?.name ?? "Account"
            finalMerchant = "\(fromName) → \(toName)"
        } else {
            finalMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        let targetToAccount = type == .transfer ? toPaymentMethod : nil
        let newItem = TransactionItem(
            timestamp: date,
            amount: amount,
            currency: defaultCurrency,
            merchant: finalMerchant,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            type: type,
            category: type == .transfer ? nil : selectedCategory,
            paymentMethod: selectedPaymentMethod,
            toPaymentMethod: targetToAccount,
            isExcludedFromBudget: type == .expense ? isExcludedFromBudget : false
        )
        modelContext.insert(newItem)
        
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
                title: finalMerchant,
                amount: amount,
                currency: defaultCurrency,
                type: type,
                recurrenceFrequency: recurrence,
                nextDueDate: nextDue,
                lastProcessedDate: date,
                category: selectedCategory,
                paymentMethod: selectedPaymentMethod,
                toPaymentMethod: targetToAccount,
                isExcludedFromBudget: isExcludedFromBudget
            )
            modelContext.insert(rule)
        }
        
        AppDataStore.saveContext(modelContext)
        let affectedIds = Set([selectedPaymentMethod?.id, targetToAccount?.id].compactMap { $0 })
        AccountBalanceManager.shared.recalculateBalances(
            forAccountIds: affectedIds.isEmpty ? nil : affectedIds,
            context: modelContext
        )
        WidgetSyncManager.shared.syncWidget(context: modelContext)
    }
}
