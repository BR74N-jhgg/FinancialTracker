/*
 SettingsView.swift
 Worthly
*/

import SwiftUI
import SwiftData

// Typealias so the view works whether referenced as SettingView or SettingsView
public typealias SettingView = SettingsView

public struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var transactions: [TransactionItem]
    @Query private var categories: [CategoryItem]
    @Query(sort: \PaymentMethodItem.name) private var paymentMethods: [PaymentMethodItem]
    
    // Persistent user preferences stored on device
    @AppStorage("monthly_budget") private var monthlyBudget: Double = 15000.0
    @AppStorage("default_currency") private var defaultCurrency: String = "HKD"
    @AppStorage("default_payment_method") private var defaultPaymentMethod: String = "Apple Pay"
    @AppStorage("enable_haptics") private var enableHaptics: Bool = true
    @AppStorage("app_language") private var appLanguage: String = "en"
    @AppStorage("app_appearance") private var appAppearance: String = "system"
    
    private var appearanceBinding: Binding<String> {
        Binding(
            get: { appAppearance },
            set: { newValue in
                appAppearance = newValue
                ThemeManager.shared.applyTheme(newValue)
            }
        )
    }
    
    @State private var budgetString: String = ""
    @State private var showingResetAlert = false
    @State private var showingSampleDataAlert = false
    @State private var showingShortcutsInfo = false
    
    @FocusState private var isBudgetFocused: Bool
    
    public static let supportedCurrencies = ["HKD", "USD", "EUR", "GBP", "JPY", "CNY", "AUD", "CAD"]
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                budgetSection
                preferencesSection
                organizationSection
                shortcutsSection
                dataSection
                aboutSection
            }
            .navigationTitle(L10n.tr("Settings", lang: appLanguage))
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L10n.tr("Done", lang: appLanguage)) {
                        isBudgetFocused = false
                        saveBudget()
                    }
                    .bold()
                    .lineLimit(1)
                }
            }
            .onAppear {
                budgetString = String(format: "%.0f", monthlyBudget)
                ThemeManager.shared.applyTheme(appAppearance)
            }
            .onChange(of: appAppearance) { _, newValue in
                ThemeManager.shared.applyTheme(newValue)
            }
            .onChange(of: budgetString) { _, newValue in
                if let val = Double(newValue), val > 0 {
                    monthlyBudget = val
                    WidgetSyncManager.shared.syncWidget(context: modelContext)
                }
            }
            .confirmationDialog(
                L10n.tr("Clear All Transactions?", lang: appLanguage),
                isPresented: $showingResetAlert,
                titleVisibility: .visible
            ) {
                Button(L10n.tr("Delete Everything", lang: appLanguage), role: .destructive) {
                    clearAllTransactions()
                }
                Button(L10n.tr("Cancel", lang: appLanguage), role: .cancel) { }
            } message: {
                Text("This permanently deletes all transaction history from your iPhone. Categories and payment methods will be preserved.")
            }
            .alert(
                L10n.tr("Sample Data Loaded", lang: appLanguage),
                isPresented: $showingSampleDataAlert
            ) {
                Button(L10n.tr("OK", lang: appLanguage), role: .cancel) { }
            } message: {
                Text("Added 38 realistic transactions across 8 categories, 5 payment methods, and 7 weekdays for testing.")
            }
            .sheet(isPresented: $showingShortcutsInfo) {
                ShortcutsGuideSheet()
            }
        }
    }
    
    // MARK: - Sub-expressions for Fast Compiler Type-Checking
    @ViewBuilder
    private var budgetSection: some View {
        Section {
            HStack {
                Text(String(format: "%@ (%@)", L10n.tr("Monthly Budget", lang: appLanguage), defaultCurrency))
                    .lineLimit(1)
                Spacer()
                TextField("Amount", text: $budgetString)
                    .keyboardType(.decimalPad)
                    .focused($isBudgetFocused)
                    .multilineTextAlignment(.trailing)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                    .onSubmit {
                        saveBudget()
                    }
            }
            
            HStack {
                Text(L10n.tr("Approx. Daily Target", lang: appLanguage))
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                let target = (Double(budgetString) ?? monthlyBudget) / 30.0
                Text(String(format: "%@ %.2f / day", defaultCurrency, target))
                    .foregroundStyle(.secondary)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
        } header: {
            Text(L10n.tr("Budget Target", lang: appLanguage)).lineLimit(1)
        } footer: {
            Text("This target is used for Dashboard and Widget progress bars.").lineLimit(1)
        }
    }
    
    @ViewBuilder
    private var preferencesSection: some View {
        Section(L10n.tr("Preferences", lang: appLanguage)) {
            // Appearance (Light / Night / System Mode)
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("Appearance", lang: appLanguage))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                Picker(L10n.tr("Appearance", lang: appLanguage), selection: appearanceBinding) {
                    Label(L10n.tr("System", lang: appLanguage), systemImage: "circle.righthalf.filled").tag("system")
                    Label(L10n.tr("Light", lang: appLanguage), systemImage: "sun.max.fill").tag("light")
                    Label(L10n.tr("Night", lang: appLanguage), systemImage: "moon.stars.fill").tag("dark")
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)
            
            // Language Picker
            Picker(L10n.tr("Language", lang: appLanguage), selection: $appLanguage) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang.rawValue).lineLimit(1)
                }
            }
            
            Picker(L10n.tr("Default Currency", lang: appLanguage), selection: $defaultCurrency) {
                ForEach(Self.supportedCurrencies, id: \.self) { curr in
                    Text(curr).tag(curr).lineLimit(1)
                }
            }
            
            Picker(L10n.tr("Default Payment Method", lang: appLanguage), selection: $defaultPaymentMethod) {
                ForEach(paymentMethods) { method in
                    Label(method.name, systemImage: method.iconName)
                        .tag(method.name)
                        .lineLimit(1)
                }
            }
            
            Toggle(L10n.tr("Haptic Feedback", lang: appLanguage), isOn: $enableHaptics)
                .lineLimit(1)
        }
    }
    
    @ViewBuilder
    private var organizationSection: some View {
        Section(L10n.tr("Organization", lang: appLanguage)) {
            NavigationLink {
                CategoryManagementView()
            } label: {
                HStack {
                    Label(L10n.tr("Manage Categories", lang: appLanguage), systemImage: "tag.fill")
                        .lineLimit(1)
                    Spacer()
                    Text("\(categories.count)")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                        .lineLimit(1)
                }
            }
            
            NavigationLink {
                PaymentMethodManagementView()
            } label: {
                HStack {
                    Label(L10n.tr("Manage Payment Methods", lang: appLanguage), systemImage: "creditcard.fill")
                        .lineLimit(1)
                    Spacer()
                    Text("\(paymentMethods.count)")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                        .lineLimit(1)
                }
            }
        }
    }
    
    @ViewBuilder
    private var shortcutsSection: some View {
        Section(L10n.tr("Apple Ecosystem", lang: appLanguage)) {
            Button {
                showingShortcutsInfo = true
            } label: {
                HStack {
                    Label(L10n.tr("Apple Pay & Shortcuts Setup", lang: appLanguage), systemImage: "bolt.badge.automatic.fill")
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "info.circle")
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
    
    @ViewBuilder
    private var dataSection: some View {
        Section(L10n.tr("Data & Storage", lang: appLanguage)) {
            HStack {
                Text(L10n.tr("Total Logged Transactions", lang: appLanguage)).lineLimit(1)
                Spacer()
                Text("\(transactions.count)")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            
            Button(role: .destructive) {
                showingResetAlert = true
            } label: {
                Label(L10n.tr("Clear All Transactions", lang: appLanguage), systemImage: "trash.fill")
                    .lineLimit(1)
            }
        }
    }
    
    @ViewBuilder
    private var aboutSection: some View {
        Section(L10n.tr("About", lang: appLanguage)) {
            HStack {
                Text(L10n.tr("App Name", lang: appLanguage)).lineLimit(1)
                Spacer()
                Text("Worthly")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack {
                Text(L10n.tr("Version", lang: appLanguage)).lineLimit(1)
                Spacer()
                let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1"
                let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                Text("\(appVersion) (\(buildNumber))")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack {
                Text(L10n.tr("Database Engine", lang: appLanguage)).lineLimit(1)
                Spacer()
                Text("Apple SwiftData (Local)").foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
    
    // MARK: - Actions & Helpers
    
    private func saveBudget() {
        if let val = Double(budgetString), val > 0 {
            monthlyBudget = val
            WidgetSyncManager.shared.syncWidget(context: modelContext)
        }
    }
    
    private func clearAllTransactions() {
        withAnimation {
            for t in transactions {
                modelContext.delete(t)
            }
            try? modelContext.delete(model: TransactionItem.self)
            try? modelContext.save()
            WidgetSyncManager.shared.syncWidget(context: modelContext)
        }
    }
    
    // MARK: - Shortcuts Guide Sheet
    public struct ShortcutsGuideSheet: View {
        @Environment(\.dismiss) private var dismiss
        @AppStorage("app_language") private var appLanguage: String = "en"
        
        public init() {}
        
        public var body: some View {
            NavigationStack {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.tr("Automate Logging with Apple Pay", lang: appLanguage))
                                .font(.headline)
                                .lineLimit(1)
                            Text(L10n.tr("iOS Shortcuts can automatically prompt or log transactions whenever you tap an Apple Pay card or use Express Transit.", lang: appLanguage))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    Section(L10n.tr("Setup Guide", lang: appLanguage)) {
                        StepRow(number: "1",
                                title: L10n.tr("Open Shortcuts App", lang: appLanguage),
                                description: L10n.tr("Navigate to the 'Automation' tab at the bottom.", lang: appLanguage))
                        StepRow(number: "2",
                                title: L10n.tr("New Automation", lang: appLanguage),
                                description: L10n.tr("Tap '+' and search for the 'Transaction' trigger.", lang: appLanguage))
                        StepRow(number: "3",
                                title: L10n.tr("Select Cards", lang: appLanguage),
                                description: L10n.tr("Select all your Apple Pay credit/debit cards and Express Transit cards (Octopus / Suica).", lang: appLanguage))
                        StepRow(number: "4",
                                title: L10n.tr("Run Automatically", lang: appLanguage),
                                description: L10n.tr("Set trigger to 'Run Immediately' without confirmation.", lang: appLanguage))
                        StepRow(number: "5",
                                title: L10n.tr("Add Worthly Action", lang: appLanguage),
                                description: L10n.tr("Select 'Auto-Log Wallet / Travel Card Payment' and map Amount, Merchant, and Card or Pass from Shortcut Input.", lang: appLanguage))
                    }
                }
                .navigationTitle(L10n.tr("Apple Pay Setup", lang: appLanguage))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.tr("Done", lang: appLanguage)) {
                            dismiss()
                        }
                        .bold()
                        .lineLimit(1)
                    }
                }
            }
        }
    }
    
    private struct StepRow: View {
        let number: String
        let title: String
        let description: String
        
        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                Text(number)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.blue)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
