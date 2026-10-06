//
//  PaymentMethodManagementView.swift
//  FinancialTracker
//

import SwiftUI
import SwiftData

public struct PaymentMethodManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PaymentMethodItem.name) private var paymentMethods: [PaymentMethodItem]
    @AppStorage("default_currency") private var defaultCurrency: String = "HKD"
    @AppStorage("app_language") private var appLanguage: String = "en"
    
    // Set to true when presented as a modal sheet, false when pushed via NavigationLink
    public let isModal: Bool
    
    @State private var showingAddMethod = false
    @State private var methodToEdit: PaymentMethodItem? = nil
    @State private var methodToAdjust: PaymentMethodItem? = nil
    
    public init(isModal: Bool = false) {
        self.isModal = isModal
    }
    
    private var activeAccounts: [PaymentMethodItem] {
        paymentMethods.filter { !$0.isDeleted }
    }
    
    private var assetAccounts: [PaymentMethodItem] {
        activeAccounts.filter { $0.isAsset }
    }
    
    private var liabilityAccounts: [PaymentMethodItem] {
        activeAccounts.filter { $0.isLiability }
    }
    
    private var totalAssets: Double {
        assetAccounts.reduce(0.0) { $0 + $1.currentBalance }
    }
    
    private var totalLiabilities: Double {
        liabilityAccounts.reduce(0.0) { $0 + abs($1.currentBalance) }
    }
    
    private var netWorth: Double {
        totalAssets - totalLiabilities
    }
    
    public var body: some View {
        if isModal {
            NavigationStack {
                accountListView
            }
        } else {
            accountListView
        }
    }
    
    @ViewBuilder
    private var accountListView: some View {
        List {
            // Net Worth Summary Banner
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.tr("Net Worth", lang: appLanguage))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    
                    Text(netWorth.formattedCurrency(defaultCurrency))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(netWorth >= 0 ? Color.primary : Color.red)
                    
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Circle().fill(Color.green).frame(width: 8, height: 8)
                            Text("\(L10n.tr("Assets", lang: appLanguage)): \(defaultCurrency) \(totalAssets.financialIntegerFormatted)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack(spacing: 4) {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                            Text("\(L10n.tr("Liabilities", lang: appLanguage)): \(defaultCurrency) \(totalLiabilities.financialIntegerFormatted)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Asset Accounts Section
            Section {
                if assetAccounts.isEmpty {
                    Text("No asset accounts added yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(assetAccounts) { method in
                        accountRow(for: method)
                    }
                    .onDelete { offsets in
                        deleteAccounts(from: assetAccounts, at: offsets)
                    }
                }
            } header: {
                HStack {
                    Text(L10n.tr("Debit", lang: appLanguage))
                    Spacer()
                    Text(totalAssets.formattedCurrency(defaultCurrency))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            } footer: {
                Text("Cash, savings, Octopus, and stored value balances.")
            }
            
            // Liability Accounts Section (Credit Cards)
            Section {
                if liabilityAccounts.isEmpty {
                    Text("No credit or loan accounts added.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(liabilityAccounts) { method in
                        accountRow(for: method)
                    }
                    .onDelete { offsets in
                        deleteAccounts(from: liabilityAccounts, at: offsets)
                    }
                }
            } header: {
                HStack {
                    Text(L10n.tr("Credit", lang: appLanguage))
                    Spacer()
                    Text("-\(totalLiabilities.formattedCurrency(defaultCurrency))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Credit cards and loans. Negative amounts represent money owed.")
            }
        }
        .navigationTitle(L10n.tr("Accounts", lang: appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isModal {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Done", lang: appLanguage)) { dismiss() }.lineLimit(1)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddMethod = true
                } label: {
                    Image(systemName: "plus")
                }
                .lineLimit(1)
            }
        }
        .sheet(isPresented: $showingAddMethod) {
            PaymentMethodEditSheet(paymentMethod: nil)
        }
        .sheet(item: $methodToEdit) { method in
            PaymentMethodEditSheet(paymentMethod: method)
        }
        .sheet(item: $methodToAdjust) { method in
            AdjustBalanceSheet(account: method, currency: defaultCurrency, lang: appLanguage)
        }
        .task {
            AccountBalanceManager.shared.recalculateBalances(context: modelContext)
        }
    }
    
    @ViewBuilder
    private func accountRow(for method: PaymentMethodItem) -> some View {
        HStack(spacing: 14) {
            Image(systemName: method.iconName)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color(hex: method.colorHex))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(method.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    if let day = method.statementDay {
                        Text("@\(day)th")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                    }
                }
                
                Text(method.isAsset ? L10n.tr("Asset (Debit/Cash)", lang: appLanguage) : L10n.tr("Liability (Credit Card)", lang: appLanguage))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(method.currentBalance.formattedCurrency(defaultCurrency))
                    .font(.callout.bold())
                    .foregroundStyle(method.isAsset ? (method.currentBalance >= 0 ? Color.primary : Color.red) : Color.red)
                
                Button {
                    methodToAdjust = method
                } label: {
                    Text(L10n.tr("Adjust Balance", lang: appLanguage))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            methodToEdit = method
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteMethod(method)
            } label: {
                Label(L10n.tr("Delete", lang: appLanguage), systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                methodToAdjust = method
            } label: {
                Label(L10n.tr("Adjust Balance", lang: appLanguage), systemImage: "pencil.and.ruler.fill")
            }
            .tint(.orange)
        }
    }
    
    // MARK: - Safe Account Deletion Logic
    private func deleteMethod(_ method: PaymentMethodItem) {
        withAnimation {
            let targetId = method.id
            
            // 1. Unlink any transactions referencing this account first to prevent dangling pointer crashes
            let descriptor = FetchDescriptor<TransactionItem>()
            if let transactions = try? modelContext.fetch(descriptor) {
                for t in transactions {
                    if t.paymentMethod?.id == targetId {
                        t.paymentMethod = nil
                    }
                    if t.toPaymentMethod?.id == targetId {
                        t.toPaymentMethod = nil
                    }
                }
            }
            
            // 2. Delete the account from SwiftData
            modelContext.delete(method)
            try? modelContext.save()
            
            // 3. Recalculate remaining balances safely
            AccountBalanceManager.shared.recalculateBalances(context: modelContext)
            WidgetSyncManager.shared.syncWidget(context: modelContext)
        }
    }
    
    private func deleteAccounts(from list: [PaymentMethodItem], at offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                deleteMethod(list[index])
            }
        }
    }
}

// MARK: - Edit / Create Account Sheet
public struct PaymentMethodEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("app_language") private var appLanguage: String = "en"
    @AppStorage("default_currency") private var defaultCurrency: String = "HKD"
    
    let paymentMethod: PaymentMethodItem?
    
    @State private var name: String = ""
    @State private var selectedIcon: String = "creditcard.fill"
    @State private var selectedColorHex: String = "#007AFF"
    @State private var accountType: AccountType = .asset
    @State private var balanceString: String = "0"
    @State private var statementDayString: String = ""
    
    public static let availableIcons = [
        "building.columns.fill", "banknote.fill", "wave.3.forward.circle.fill",
        "creditcard.fill", "apple.logo", "dollarsign.circle.fill",
        "p.circle.fill", "wallet.pass.fill", "qrcode",
        "cart.fill", "giftcard.fill", "iphone",
        "lock.shield.fill", "creditcard.and.123", "centsign.circle.fill"
    ]
    
    public static let availableColors = [
        "#5856D6", "#10B981", "#FF9500", "#34C759",
        "#FF2D55", "#E11D48", "#007AFF", "#AF52DE",
        "#000000", "#5AC8FA", "#00C7BE", "#8E8E93"
    ]
    
    public init(paymentMethod: PaymentMethodItem?) {
        self.paymentMethod = paymentMethod
        _name = State(initialValue: paymentMethod?.name ?? "")
        _selectedIcon = State(initialValue: paymentMethod?.iconName ?? "building.columns.fill")
        _selectedColorHex = State(initialValue: paymentMethod?.colorHex ?? "#5856D6")
        _accountType = State(initialValue: paymentMethod?.accountType ?? .asset)
        _balanceString = State(initialValue: String(format: "%.2f", abs(paymentMethod?.initialBalance ?? 0.0)))
        if let day = paymentMethod?.statementDay {
            _statementDayString = State(initialValue: "\(day)")
        }
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Account Details") {
                    TextField("Account Name (e.g. HSBC, BOCHK, Octopus)", text: $name)
                        .lineLimit(1)
                    
                    Picker("Account Type", selection: $accountType) {
                        Text(L10n.tr("Asset (Debit/Cash)", lang: appLanguage)).tag(AccountType.asset)
                        Text(L10n.tr("Liability (Credit Card)", lang: appLanguage)).tag(AccountType.liability)
                    }
                    
                    HStack {
                        Text(paymentMethod == nil ? L10n.tr("Starting Balance", lang: appLanguage) : L10n.tr("Initial Balance", lang: appLanguage))
                        Spacer()
                        Text(defaultCurrency).foregroundStyle(.secondary)
                        TextField("0.00", text: $balanceString)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                    }
                    
                    if accountType == .liability {
                        HStack {
                            Text(L10n.tr("Statement Day", lang: appLanguage))
                            Spacer()
                            TextField("e.g. 7 (Day of Month)", text: $statementDayString)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 140)
                        }
                    }
                }
                
                Section("Preview") {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: selectedIcon)
                                .font(.title)
                                .foregroundStyle(.white)
                                .frame(width: 60, height: 60)
                                .background(Color(hex: selectedColorHex))
                                .clipShape(Circle())
                            
                            Text(name.isEmpty ? "Account" : name)
                                .font(.headline)
                                .lineLimit(1)
                            
                            Text(accountType == .asset ? "Asset Account" : "Credit Card / Liability")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                
                Section("Choose Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                        ForEach(Self.availableIcons, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(selectedIcon == icon ? Color(hex: selectedColorHex).opacity(0.2) : Color(.tertiarySystemFill))
                                    .foregroundStyle(selectedIcon == icon ? Color(hex: selectedColorHex) : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(selectedIcon == icon ? Color(hex: selectedColorHex) : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section("Choose Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                        ForEach(Self.availableColors, id: \.self) { hex in
                            Button {
                                selectedColorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle().stroke(Color.primary, lineWidth: selectedColorHex == hex ? 3 : 0)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(paymentMethod == nil ? "New Account" : "Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Cancel", lang: appLanguage)) { dismiss() }.lineLimit(1)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("Done", lang: appLanguage)) {
                        saveMethod()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .bold()
                }
            }
        }
    }
    
    private func saveMethod() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawBalance = Double(balanceString.replacingOccurrences(of: ",", with: "")) ?? 0.0
        let safeBalance = rawBalance.isFinite ? rawBalance : 0.0
        let parsedBalance = accountType == .liability ? -abs(safeBalance) : safeBalance
        
        let parsedDay = Int(statementDayString)
        let validatedDay = (parsedDay != nil && parsedDay! >= 1 && parsedDay! <= 31) ? parsedDay : nil
        
        if let existing = paymentMethod {
            existing.name = trimmedName
            existing.iconName = selectedIcon
            existing.colorHex = selectedColorHex
            existing.accountType = accountType
            existing.initialBalance = parsedBalance
            existing.statementDay = validatedDay
        } else {
            let newMethod = PaymentMethodItem(
                name: trimmedName,
                iconName: selectedIcon,
                colorHex: selectedColorHex,
                accountType: accountType,
                initialBalance: parsedBalance,
                currentBalance: parsedBalance,
                statementDay: validatedDay
            )
            modelContext.insert(newMethod)
        }
        try? modelContext.save()
        AccountBalanceManager.shared.recalculateBalances(context: modelContext)
        WidgetSyncManager.shared.syncWidget(context: modelContext)
    }
}

// MARK: - Frictionless One-Tap Balance Adjustment Sheet
public struct AdjustBalanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let account: PaymentMethodItem
    let currency: String
    let lang: String
    
    @State private var newBalanceText: String = ""
    @State private var adjustmentNote: String = "Manual balance sync"
    
    public init(account: PaymentMethodItem, currency: String, lang: String) {
        self.account = account
        self.currency = currency
        self.lang = lang
        _newBalanceText = State(initialValue: String(format: "%.2f", account.currentBalance))
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: account.iconName)
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color(hex: account.colorHex))
                            .clipShape(Circle())
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                                .font(.headline)
                            Text("\(L10n.tr("Current Balance", lang: lang)): \(account.currentBalance.formattedCurrency(currency))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section {
                    HStack {
                        Text(currency).font(.headline)
                        TextField("0.00", text: $newBalanceText)
                            .keyboardType(.numbersAndPunctuation)
                            .font(.title3.bold())
                    }
                } header: {
                    Text(L10n.tr("New Balance", lang: lang))
                } footer: {
                    Text("Enter the actual balance shown on your bank/Octopus app. The difference will be automatically balanced.")
                }
                
                Section("Note (Optional)") {
                    TextField("e.g. Bank reconciliation", text: $adjustmentNote)
                }
            }
            .navigationTitle(L10n.tr("Adjust Balance", lang: lang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Cancel", lang: lang)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("Done", lang: lang)) {
                        applyAdjustment()
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
    
    private func applyAdjustment() {
        guard let target = Double(newBalanceText.replacingOccurrences(of: ",", with: "")) else { return }
        let diff = target - account.currentBalance
        account.initialBalance += diff
        account.currentBalance = target
        try? modelContext.save()
        AccountBalanceManager.shared.recalculateBalances(context: modelContext)
        WidgetSyncManager.shared.syncWidget(context: modelContext)
    }
}
