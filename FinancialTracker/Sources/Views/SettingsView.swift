/*
 SettingsView.swift
 Worthly
*/

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit
import os

// Typealias so the view works whether referenced as SettingView or SettingsView
public typealias SettingView = SettingsView

public struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var transactions: [TransactionItem]
    @Query private var categories: [CategoryItem]
    @Query(sort: \PaymentMethodItem.name) private var paymentMethods: [PaymentMethodItem]
    @Query(sort: \RecurringRuleItem.nextDueDate) private var recurringRules: [RecurringRuleItem]
    
    // Persistent user preferences stored on device
    @AppStorage("monthly_budget") private var monthlyBudget: Double = 15000.0
    @AppStorage("default_currency") private var defaultCurrency: String = "HKD"
    @AppStorage("default_payment_method") private var defaultPaymentMethod: String = "Apple Pay"
    @AppStorage("aavs_funding_card") private var aavsFundingCard: String = ""
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
    
    /// Candidate accounts that can fund Octopus AAVS top-ups (prefers liability/credit cards, falls back to non-Octopus accounts)
    private var aavsCandidateAccounts: [PaymentMethodItem] {
        let liabilities = paymentMethods.filter { !$0.isDeleted && $0.isLiability }
        if !liabilities.isEmpty {
            return liabilities
        }
        return paymentMethods.filter {
            !$0.isDeleted &&
            !$0.name.localizedCaseInsensitiveContains("Octopus") &&
            !$0.name.localizedCaseInsensitiveContains("八達通")
        }
    }
    
    @State private var budgetString: String = ""
    @State private var showingResetAlert = false
    @State private var showingSampleDataAlert = false
    @State private var showingShortcutsInfo = false
    @State private var sharedFileItem: SharedExportFile? = nil
    @State private var showingBackupImporter = false
    @State private var backupAlertTitle = ""
    @State private var backupAlertMessage = ""
    @State private var showingBackupAlert = false
    
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
            .onChange(of: defaultCurrency) { _, _ in
                WidgetSyncManager.shared.syncWidget(context: modelContext)
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
            .alert(
                backupAlertTitle,
                isPresented: $showingBackupAlert
            ) {
                Button(L10n.tr("OK", lang: appLanguage), role: .cancel) { }
            } message: {
                Text(backupAlertMessage)
            }
            .sheet(isPresented: $showingShortcutsInfo) {
                ShortcutsGuideSheet()
            }
            .sheet(item: $sharedFileItem) { item in
                ActivityShareSheet(activityItems: [item.url])
            }
            .fileImporter(
                isPresented: $showingBackupImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleBackupImport(result: result)
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
            
            Picker(appLanguage == "zh-HK" ? "八達通自動增值信用卡 (AAVS)" : "Octopus AAVS Funding Card", selection: $aavsFundingCard) {
                Text(appLanguage == "zh-HK" ? "自動偵測 (預設信用卡)" : "Auto (Default Credit Card)")
                    .tag("")
                    .lineLimit(1)
                ForEach(aavsCandidateAccounts) { method in
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
            
            NavigationLink {
                RecurringManagementView()
            } label: {
                HStack {
                    Label(L10n.tr("Recurring & Subscriptions", lang: appLanguage), systemImage: "repeat.circle.fill")
                        .lineLimit(1)
                    Spacer()
                    let activeCount = recurringRules.filter { !$0.isDeleted && !$0.isPaused }.count
                    Text("\(activeCount)")
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
            
            Button {
                if let url = BackupManager.shared.writeCSVExportFile(transactions: transactions) {
                    sharedFileItem = SharedExportFile(url: url)
                }
            } label: {
                Label(L10n.tr("Export Transactions (CSV)", lang: appLanguage), systemImage: "tablecells.badge.ellipsis")
                    .lineLimit(1)
            }
            
            Button {
                if let url = BackupManager.shared.writeJSONBackupFile(context: modelContext) {
                    sharedFileItem = SharedExportFile(url: url)
                }
            } label: {
                Label(L10n.tr("Backup Data (JSON)", lang: appLanguage), systemImage: "externaldrive.badge.timemachine")
                    .lineLimit(1)
            }
            
            Button {
                showingBackupImporter = true
            } label: {
                Label(L10n.tr("Restore from Backup (JSON)", lang: appLanguage), systemImage: "arrow.down.doc.fill")
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
                let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3"
                let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "36"
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
            do {
                try modelContext.delete(model: TransactionItem.self)
            } catch {
                AppDataStore.logger.error("Failed batch TransactionItem delete: \(error.localizedDescription, privacy: .public)")
            }
            AppDataStore.saveContext(modelContext)
            AccountBalanceManager.shared.recalculateBalances(context: modelContext)
            WidgetSyncManager.shared.syncWidget(context: modelContext)
        }
    }
    
    private func handleBackupImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let fileURL = urls.first else { return }
            let didAccess = fileURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let data = try Data(contentsOf: fileURL)
                let summary = try BackupManager.shared.importJSONData(data, context: modelContext)
                backupAlertTitle = L10n.tr("Restore Completed", lang: appLanguage)
                if appLanguage.hasPrefix("zh") {
                    backupAlertMessage = "已成功還原 \(summary.transactionsRestored) 筆交易、\(summary.accountsRestored) 個帳戶、\(summary.categoriesRestored) 個分類及 \(summary.rulesRestored) 項定期付款規則。"
                } else {
                    backupAlertMessage = "Restored \(summary.transactionsRestored) transactions, \(summary.accountsRestored) accounts, \(summary.categoriesRestored) categories, and \(summary.rulesRestored) recurring rules."
                }
                showingBackupAlert = true
            } catch {
                AppDataStore.logger.error("Backup import failed: \(error.localizedDescription, privacy: .public)")
                backupAlertTitle = L10n.tr("Backup Error", lang: appLanguage)
                backupAlertMessage = error.localizedDescription
                showingBackupAlert = true
            }
        case .failure(let error):
            AppDataStore.logger.error("File importer failed: \(error.localizedDescription, privacy: .public)")
            backupAlertTitle = L10n.tr("Backup Error", lang: appLanguage)
            backupAlertMessage = error.localizedDescription
            showingBackupAlert = true
        }
    }
    
    // MARK: - Shortcuts Guide Sheet (Option 1 + 2: 1-Tap Template + Visual 2-Tab Assistant)
    public struct ShortcutsGuideSheet: View {
        @Environment(\.dismiss) private var dismiss
        @Environment(\.openURL) private var openURL
        @AppStorage("app_language") private var appLanguage: String = "en"
        @AppStorage("octopus_shortcut_template_icloud_url") private var templateICloudUrl1: String = "https://www.icloud.com/shortcuts/26d3105cd6524e2e8d1092a1bce902be"
        @AppStorage("applepay_shortcut_template_icloud_url") private var templateICloudUrl2: String = "https://www.icloud.com/shortcuts/e7d2e52193b042d0af37cdbd677c9125"

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
                            
                            HStack(spacing: 7) {
                                Button {
                                    if let url = URL(string: templateICloudUrl1), UIApplication.shared.canOpenURL(url) {
                                        openURL(url)
                                    } else if let shortcutsUrl = URL(string: "shortcuts://") {
                                        openURL(shortcutsUrl)
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "arrow.down.circle.fill")
                                        Text(appLanguage == "zh-HK" ? "下載捷徑範本" : "Install Octopus Template")
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
                            
                            HStack(spacing: 7) {
                                Button {
                                    if let url = URL(string: templateICloudUrl2), UIApplication.shared.canOpenURL(url) {
                                        openURL(url)
                                    } else if let shortcutsUrl = URL(string: "shortcuts://") {
                                        openURL(shortcutsUrl)
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "arrow.down.circle.fill")
                                        Text(appLanguage == "zh-HK" ? "下載捷徑範本" : "Install General Template")
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
                        Section(appLanguage == "zh-HK" ? "八達通動態車資全自動記帳" : "Octopus Dynamic Fare Setup") {
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
                            if let url = URL(string: "shortcuts://") {
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

// MARK: - Share Sheet Helper for CSV & JSON Export (Phase 1: 9.1-5)
public struct SharedExportFile: Identifiable {
    public let id = UUID()
    public let url: URL
}

public struct ActivityShareSheet: UIViewControllerRepresentable {
    public let activityItems: [Any]
    
    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Recurring & Subscriptions Management Screen (Phase 1: 9.1-2)
public struct RecurringManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecurringRuleItem.nextDueDate) private var rules: [RecurringRuleItem]
    @AppStorage("default_currency") private var defaultCurrency: String = "HKD"
    @AppStorage("app_language") private var appLanguage: String = "en"
    
    @State private var showingAddRule = false
    @State private var ruleToEdit: RecurringRuleItem? = nil
    
    public init() {}
    
    private var activeRules: [RecurringRuleItem] {
        rules.filter { !$0.isDeleted && !$0.isPaused && $0.recurrenceFrequency != .never }
    }
    
    private var pausedRules: [RecurringRuleItem] {
        rules.filter { !$0.isDeleted && ($0.isPaused || $0.recurrenceFrequency == .never) }
    }
    
    /// Estimated monthly fixed expense total across active rules
    private var monthlyFixedEstimate: Double {
        activeRules.filter { $0.type == .expense }.reduce(0.0) { acc, rule in
            switch rule.recurrenceFrequency {
            case .weekly: return acc + (rule.amount * 52.0 / 12.0)
            case .monthly: return acc + rule.amount
            case .yearly: return acc + (rule.amount / 12.0)
            case .never: return acc
            }
        }
    }
    
    public var body: some View {
        List {
            // Monthly Fixed Expense Summary Card
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.tr("Monthly Fixed Estimate", lang: appLanguage))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    
                    Text(monthlyFixedEstimate.formattedCurrency(defaultCurrency))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 14) {
                        Label("\(activeRules.count) \(L10n.tr("Active", lang: appLanguage))", systemImage: "checkmark.circle.fill")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.green)
                        
                        if !pausedRules.isEmpty {
                            Label("\(pausedRules.count) \(L10n.tr("Paused", lang: appLanguage))", systemImage: "pause.circle.fill")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            
            if activeRules.isEmpty && pausedRules.isEmpty {
                Section {
                    ContentUnavailableView(
                        L10n.tr("No Recurring Rules Yet", lang: appLanguage),
                        systemImage: "repeat.circle",
                        description: Text(L10n.tr("Add a repeating payment when logging a transaction or tap '+' to create one.", lang: appLanguage))
                    )
                    .padding(.vertical, 20)
                }
            } else {
                if !activeRules.isEmpty {
                    Section(L10n.tr("Active Subscriptions", lang: appLanguage)) {
                        ForEach(activeRules) { rule in
                            ruleRow(for: rule)
                        }
                    }
                }
                
                if !pausedRules.isEmpty {
                    Section(L10n.tr("Paused", lang: appLanguage)) {
                        ForEach(pausedRules) { rule in
                            ruleRow(for: rule)
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.tr("Recurring & Subscriptions", lang: appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddRule = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddRule) {
            RecurringRuleEditSheet(rule: nil)
        }
        .sheet(item: $ruleToEdit) { rule in
            RecurringRuleEditSheet(rule: rule)
        }
    }
    
    @ViewBuilder
    private func ruleRow(for rule: RecurringRuleItem) -> some View {
        HStack(spacing: 14) {
            Image(systemName: rule.category?.iconName ?? "repeat.circle.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color(hex: rule.category?.colorHex ?? "#007AFF").opacity(rule.isPaused ? 0.45 : 1.0))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(rule.title.isEmpty ? "Recurring" : rule.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(rule.isPaused ? .secondary : .primary)
                        .lineLimit(1)
                    
                    Text(L10n.tr(rule.recurrenceFrequency.rawValue, lang: appLanguage))
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }
                
                HStack(spacing: 6) {
                    if let pm = rule.paymentMethod {
                        Text(pm.name)
                            .lineLimit(1)
                        Text("•")
                    }
                    Text("\(L10n.tr("Next Due", lang: appLanguage)): \(rule.nextDueDate, format: .dateTime.year().month(.abbreviated).day())")
                        .lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(rule.amount.formattedCurrency(rule.currency.isEmpty ? defaultCurrency : rule.currency))
                    .font(.callout.bold())
                    .foregroundStyle(rule.isPaused ? Color.secondary : (rule.type == .income ? Color.green : Color.primary))                    .lineLimit(1)
                
                Button {
                    togglePause(rule)
                } label: {
                    Text(rule.isPaused ? L10n.tr("Resume", lang: appLanguage) : L10n.tr("Pause", lang: appLanguage))
                        .font(.caption2.weight(.semibold))
                    .foregroundStyle(rule.isPaused ? Color.green : Color.orange)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            ruleToEdit = rule
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteRule(rule)
            } label: {
                Label(L10n.tr("Delete", lang: appLanguage), systemImage: "trash.fill")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                togglePause(rule)
            } label: {
                Label(
                    rule.isPaused ? L10n.tr("Resume", lang: appLanguage) : L10n.tr("Pause", lang: appLanguage),
                    systemImage: rule.isPaused ? "play.fill" : "pause.fill"
                )
            }
            .tint(rule.isPaused ? .green : .orange)
        }
    }
    
    private func togglePause(_ rule: RecurringRuleItem) {
        withAnimation {
            rule.isPaused.toggle()
            AppDataStore.saveContext(modelContext)
            if !rule.isPaused {
                RecurringPaymentManager.shared.processDueRecurringPayments(context: modelContext)
            }
        }
    }
    
    private func deleteRule(_ rule: RecurringRuleItem) {
        withAnimation {
            modelContext.delete(rule)
            AppDataStore.saveContext(modelContext)
        }
    }
}

public struct RecurringRuleEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CategoryItem.name) private var categories: [CategoryItem]
    @Query(sort: \PaymentMethodItem.name) private var paymentMethods: [PaymentMethodItem]
    @AppStorage("default_currency") private var defaultCurrency: String = "HKD"
    @AppStorage("app_language") private var appLanguage: String = "en"
    
    let rule: RecurringRuleItem?
    
    @State private var title: String = ""
    @State private var amountString: String = ""
    @State private var type: TransactionType = .expense
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var nextDueDate: Date = Date()
    @State private var selectedCategoryId: UUID? = nil
    @State private var selectedPaymentMethodId: UUID? = nil
    @State private var toPaymentMethodId: UUID? = nil
    @State private var isPaused: Bool = false
    @State private var isExcludedFromBudget: Bool = false
    
    public init(rule: RecurringRuleItem?) {
        self.rule = rule
        _title = State(initialValue: rule?.title ?? "")
        _amountString = State(initialValue: rule != nil ? String(format: "%.2f", rule!.amount) : "")
        _type = State(initialValue: rule?.type ?? .expense)
        _frequency = State(initialValue: (rule?.recurrenceFrequency == .never || rule == nil) ? .monthly : rule!.recurrenceFrequency)
        _nextDueDate = State(initialValue: rule?.nextDueDate ?? Date())
        _selectedCategoryId = State(initialValue: rule?.category?.id)
        _selectedPaymentMethodId = State(initialValue: rule?.paymentMethod?.id)
        _toPaymentMethodId = State(initialValue: rule?.toPaymentMethod?.id)
        _isPaused = State(initialValue: rule?.isPaused ?? false)
        _isExcludedFromBudget = State(initialValue: rule?.isExcludedFromBudget ?? false)
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section(L10n.tr("Rule Title", lang: appLanguage)) {
                    TextField("e.g. Netflix, iCloud+, Gym, Rent", text: $title)
                        .lineLimit(1)
                    
                    HStack {
                        Text(defaultCurrency).foregroundStyle(.secondary)
                        TextField("0.00", text: $amountString)
                            .keyboardType(.decimalPad)
                            .font(.headline)
                    }
                }
                
                Section(L10n.tr("Repeating Payment", lang: appLanguage)) {
                    Picker("Type", selection: $type) {
                        ForEach(TransactionType.allCases, id: \.self) { t in
                            Text(L10n.tr(t.rawValue, lang: appLanguage)).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Picker(L10n.tr("Repeat", lang: appLanguage), selection: $frequency) {
                        ForEach([RecurrenceFrequency.weekly, .monthly, .yearly], id: \.self) { freq in
                            Text(L10n.tr(freq.rawValue, lang: appLanguage)).tag(freq)
                        }
                    }
                    
                    DatePicker(L10n.tr("Next Due", lang: appLanguage), selection: $nextDueDate, displayedComponents: .date)
                    
                    Toggle(L10n.tr("Pause Subscription", lang: appLanguage), isOn: $isPaused)
                }
                
                Section("Classification") {
                    if type != .transfer {
                        Picker("Category", selection: $selectedCategoryId) {
                            Text("Uncategorized").tag(nil as UUID?)
                            ForEach(categories) { cat in
                                Label(cat.name, systemImage: cat.iconName)
                                    .tag(cat.id as UUID?)
                            }
                        }
                    }
                    
                    Picker(L10n.tr(type == .transfer ? "From Account" : "Account", lang: appLanguage), selection: $selectedPaymentMethodId) {
                        Text("Unspecified").tag(nil as UUID?)
                        ForEach(paymentMethods) { pm in
                            Label(pm.name, systemImage: pm.iconName)
                                .tag(pm.id as UUID?)
                        }
                    }
                    
                    if type == .transfer {
                        Picker(L10n.tr("To Account", lang: appLanguage), selection: $toPaymentMethodId) {
                            Text("Unspecified").tag(nil as UUID?)
                            ForEach(paymentMethods.filter { $0.id != selectedPaymentMethodId }) { pm in
                                Label(pm.name, systemImage: pm.iconName)
                                    .tag(pm.id as UUID?)
                            }
                        }
                    } else if type == .expense {
                        Toggle(L10n.tr("Exclude from Budget", lang: appLanguage), isOn: $isExcludedFromBudget)
                    }
                }
            }
            .navigationTitle(rule == nil ? L10n.tr("New Recurring Rule", lang: appLanguage) : L10n.tr("Edit Recurring Rule", lang: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Cancel", lang: appLanguage)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("Save", lang: appLanguage)) {
                        saveRule()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (Double(amountString) ?? 0) <= 0 || (type == .transfer && (selectedPaymentMethodId == nil || toPaymentMethodId == nil)))
                    .bold()
                }
            }
        }
    }
    
    private func saveRule() {
        guard let amount = Double(amountString), amount > 0 else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCategory = type == .transfer ? nil : categories.first(where: { $0.id == selectedCategoryId })
        let resolvedPaymentMethod = paymentMethods.first(where: { $0.id == selectedPaymentMethodId })
        let resolvedToPaymentMethod = type == .transfer ? paymentMethods.first(where: { $0.id == toPaymentMethodId }) : nil
        
        if let existing = rule {
            existing.title = trimmedTitle
            existing.amount = amount
            existing.currency = defaultCurrency
            existing.type = type
            existing.recurrenceFrequency = frequency
            existing.nextDueDate = nextDueDate
            existing.category = resolvedCategory
            existing.paymentMethod = resolvedPaymentMethod
            existing.toPaymentMethod = resolvedToPaymentMethod
            existing.isPaused = isPaused
            existing.isExcludedFromBudget = type == .expense ? isExcludedFromBudget : false
        } else {
            let newRule = RecurringRuleItem(
                title: trimmedTitle,
                amount: amount,
                currency: defaultCurrency,
                type: type,
                recurrenceFrequency: frequency,
                nextDueDate: nextDueDate,
                category: resolvedCategory,
                paymentMethod: resolvedPaymentMethod,
                toPaymentMethod: resolvedToPaymentMethod,
                isExcludedFromBudget: type == .expense ? isExcludedFromBudget : false,
                isPaused: isPaused
            )
            modelContext.insert(newRule)
        }
        
        AppDataStore.saveContext(modelContext)
        RecurringPaymentManager.shared.processDueRecurringPayments(context: modelContext)
    }
}
