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
    
    // MARK: - Shortcuts Guide Sheet (Option 1 + 2: 1-Tap Template + Visual 2-Tab Assistant)
    public struct ShortcutsGuideSheet: View {
        @Environment(\.dismiss) private var dismiss
        @Environment(\.openURL) private var openURL
        @AppStorage("app_language") private var appLanguage: String = "en"
        @AppStorage("shortcut_template_icloud_url") private var templateICloudUrl: String = "https://www.icloud.com/shortcuts/worthly-autolog"

        @State private var selectedTab: Int = 0 // 0: Apple Pay Cards, 1: Octopus & Transit

        public init() {}

        public var body: some View {
            NavigationStack {
                List {
                    // MARK: - Option 1: 1-Tap Pre-Configured Template Card
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(colors: [Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "bolt.badge.automatic.fill")
                                        .font(.title3)
                                        .foregroundStyle(.white)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(appLanguage == "zh-HK" ? "一鍵安裝捷徑範本" : "One-Tap Shortcut Template")
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text(appLanguage == "zh-HK" ? "預先對應所有參數，安裝後立即可用" : "Pre-mapped with all Worthly fields")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            
                            Text(
                                appLanguage == "zh-HK"
                                ? "點擊下方按鈕即可直接在 iPhone 安裝已配置完成的「Worthly 自動記帳」捷徑，無須手動設定任何變數。"
                                : "Tap below to install the ready-to-use 'Worthly Auto-Log' shortcut directly on your iPhone without configuring any variables by hand."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            
                            HStack(spacing: 10) {
                                Button {
                                    if let url = URL(string: templateICloudUrl), UIApplication.shared.canOpenURL(url) {
                                        openURL(url)
                                    } else if let shortcutsUrl = URL(string: "shortcuts://") {
                                        openURL(shortcutsUrl)
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "arrow.down.circle.fill")
                                        Text(appLanguage == "zh-HK" ? "下載捷徑範本" : "Install Shortcut Template")
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.blue)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                                
                                Button {
                                    if let shortcutsUrl = URL(string: "shortcuts://") {
                                        openURL(shortcutsUrl)
                                    }
                                } label: {
                                    Image(systemName: "arrow.up.forward.app")
                                        .font(.body.weight(.bold))
                                        .padding(10)
                                        .background(Color(.tertiarySystemFill))
                                        .foregroundStyle(.primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // MARK: - Option 2: 2-Tab Setup Guide
                    Section {
                        Picker("Setup Type", selection: $selectedTab) {
                            Text(appLanguage == "zh-HK" ? "信用卡 / Apple Pay" : "Apple Pay Cards").tag(0)
                            Text(appLanguage == "zh-HK" ? "八達通 / 交通卡" : "Octopus Transit").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .padding(.vertical, 2)
                    } header: {
                        Text(appLanguage == "zh-HK" ? "自動化設定教學 (選定卡片類型)" : "Automation Walkthrough")
                    } footer: {
                        Text(
                            selectedTab == 0
                            ? (appLanguage == "zh-HK" ? "適用於所有 Apple Pay 信用卡及扣帳卡，感應付款即時記帳。" : "For all Apple Pay credit & debit cards. Logs instantly on NFC tap.")
                            : (appLanguage == "zh-HK" ? "利用通知觸發自動讀取港鐵、巴士動態車資，免手動輸入金額。" : "Uses Notification trigger to read exact dynamic transit fares without typing.")
                        )
                    }

                    if selectedTab == 0 {
                        // TAB 1: Apple Pay Cards
                        Section(appLanguage == "zh-HK" ? "Apple Pay 感應即時記帳" : "Apple Pay Tap Setup") {
                            StepRow(
                                number: "1",
                                title: appLanguage == "zh-HK" ? "開啟「捷徑」App" : "Open Shortcuts App",
                                description: appLanguage == "zh-HK" ? "進入底部的「自動化」標籤頁，點擊右上角「+」。" : "Tap the 'Automation' tab at the bottom, then tap '+'."
                            )
                            StepRow(
                                number: "2",
                                title: appLanguage == "zh-HK" ? "選擇「交易」觸發條件" : "Choose 'Transaction' Trigger",
                                description: appLanguage == "zh-HK" ? "搜尋並選擇「交易」，勾選你的 Apple Pay 卡片，設定為「立即執行」。" : "Select 'Transaction', pick your cards, and choose 'Run Immediately'."
                            )
                            StepRow(
                                number: "3",
                                title: appLanguage == "zh-HK" ? "加入 Worthly 動作" : "Add Worthly Action",
                                description: appLanguage == "zh-HK" ? "搜尋 Worthly 並選擇「Auto-Log Wallet & Travel Card」。" : "Select 'Auto-Log Wallet & Travel Card' under Worthly."
                            )
                            StepRow(
                                number: "4",
                                title: appLanguage == "zh-HK" ? "連結交易參數" : "Map Input Parameters",
                                description: appLanguage == "zh-HK" ? "將 Amount 設為 [捷徑輸入 -> 金額]，Merchant 設為 [商戶]，Card 設為 [卡片]。" : "Map Amount -> [Shortcut Input -> Amount], Merchant -> [Merchant], Card -> [Card]."
                            )
                        }
                    } else {
                        // TAB 2: Octopus Notification Auto-Logging
                        Section(appLanguage == "zh-HK" ? "八達通自動記帳" : "Octopus Dynamic Fare Setup") {
                            StepRow(
                                number: "1",
                                title: appLanguage == "zh-HK" ? "新增「通知」自動化操作" : "Choose 'Notification' Trigger",
                                description: appLanguage == "zh-HK" ? "在「自動化」點擊「+」，選擇「通知」（Notification），App 勾選「Wallet」及「八達通」。" : "In Shortcuts Automation tap '+', choose 'Notification', select 'Wallet' and 'Octopus'."
                            )
                            StepRow(
                                number: "2",
                                title: appLanguage == "zh-HK" ? "設定為「立即執行」" : "Set to 'Run Immediately'",
                                description: appLanguage == "zh-HK" ? "勾選「立即執行」並關閉「執行時通知」，點擊「下一步」。" : "Select 'Run Immediately' and turn off 'Notify When Run', then tap Next."
                            )
                            StepRow(
                                number: "3",
                                title: appLanguage == "zh-HK" ? "加入 Worthly 動作" : "Add Worthly Action",
                                description: appLanguage == "zh-HK" ? "加入「Auto-Log Wallet & Travel Card」，點擊「展開」顯示詳細欄位。" : "Add 'Auto-Log Wallet & Travel Card' and expand details."
                            )
                            StepRow(
                                number: "4",
                                title: appLanguage == "zh-HK" ? "連結通知文字 (免填金額)" : "Link Notification Text",
                                description: appLanguage == "zh-HK" ? "Amount 留空！將 Notification or Raw Text 設為 [通知 -> 內文]，Card 設為 [通知 -> 標題]。" : "Leave Amount blank! Map 'Notification or Raw Text' -> [Notification -> Body], Card -> [Title]."
                            )
                        }
                    }
                    
                    Section {
                        Button {
                            if let url = URL(string: "https://www.icloud.com/shortcuts/de15d734f77f43e1869d6b0309cea038") {
                                openURL(url)
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "arrow.up.forward.app.fill")
                                Text(appLanguage == "zh-HK" ? "立即開啟「捷徑」App 設定" : "Open Shortcuts App Now")
                                    .fontWeight(.bold)
                                Spacer()
                            }
                            .foregroundStyle(.blue)
                        }
                    }
                }
                .navigationTitle(appLanguage == "zh-HK" ? "自動記帳設定" : "Auto-Log Setup")
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
