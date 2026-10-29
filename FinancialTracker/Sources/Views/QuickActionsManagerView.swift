//
//  QuickActionsManagerView.swift
//  Worthly
//

import Foundation
import SwiftUI
import SwiftData

// MARK: - Customizable Quick Action Item Model (Supports 1-Tap Instant Expense, Income & Transfer Logging)
public struct QuickActionItem: Identifiable, Codable, Equatable {
    public var id: String
    public var title: String
    public var icon: String
    public var colorHex: String
    public var defaultMerchant: String
    public var defaultCategoryName: String
    public var defaultPaymentMethodName: String
    public var defaultAmount: Double?
    public var transactionTypeRaw: String?
    public var isInstantOneTap: Bool?
    public var toPaymentMethodName: String?
    
    public var transactionType: TransactionType {
        get { TransactionType(rawValue: transactionTypeRaw ?? "Expense") ?? .expense }
        set { transactionTypeRaw = newValue.rawValue }
    }
    
    public var shouldInstantLog: Bool {
        guard let amt = defaultAmount, amt > 0 else { return false }
        return isInstantOneTap ?? true
    }
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        icon: String = "plus.circle.fill",
        colorHex: String = "#007AFF",
        defaultMerchant: String = "",
        defaultCategoryName: String = "",
        defaultPaymentMethodName: String = "",
        defaultAmount: Double? = nil,
        transactionType: TransactionType = .expense,
        isInstantOneTap: Bool? = nil,
        toPaymentMethodName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.colorHex = colorHex
        self.defaultMerchant = defaultMerchant
        self.defaultCategoryName = defaultCategoryName
        self.defaultPaymentMethodName = defaultPaymentMethodName
        self.defaultAmount = defaultAmount
        self.transactionTypeRaw = transactionType.rawValue
        self.isInstantOneTap = isInstantOneTap ?? (defaultAmount != nil && (defaultAmount ?? 0) > 0)
        self.toPaymentMethodName = toPaymentMethodName
    }
    
    public static let defaultItems: [QuickActionItem] = [
        QuickActionItem(id: "1", title: "Add Expense", icon: "plus.circle.fill", colorHex: "#007AFF", defaultMerchant: "", defaultCategoryName: "", defaultPaymentMethodName: "CUHK Credit Card", defaultAmount: nil, transactionType: .expense, isInstantOneTap: false),
        QuickActionItem(id: "2", title: "Octopus MTR", icon: "wave.3.forward.circle.fill", colorHex: "#FF9500", defaultMerchant: "MTR", defaultCategoryName: "Octopus", defaultPaymentMethodName: "Octopus", defaultAmount: 5.60, transactionType: .expense, isInstantOneTap: true),
        QuickActionItem(id: "3", title: "Tram / Bus", icon: "tram.fill", colorHex: "#007AFF", defaultMerchant: "Transit", defaultCategoryName: "Octopus", defaultPaymentMethodName: "Octopus", defaultAmount: 2.20, transactionType: .expense, isInstantOneTap: true),
        QuickActionItem(id: "4", title: "Coffee/Meal", icon: "cup.and.saucer.fill", colorHex: "#34C759", defaultMerchant: "Coffee / Meal", defaultCategoryName: "Dining", defaultPaymentMethodName: "CUHK Credit Card", defaultAmount: 45.00, transactionType: .expense, isInstantOneTap: true),
        QuickActionItem(id: "5", title: "Quick Income", icon: "arrow.down.left.circle.fill", colorHex: "#34C759", defaultMerchant: "Income", defaultCategoryName: "Salary", defaultPaymentMethodName: "Bank Transfer / FPS", defaultAmount: 500.00, transactionType: .income, isInstantOneTap: true),
        QuickActionItem(id: "6", title: "Top Up Octopus", icon: "arrow.triangle.2.circlepath.circle.fill", colorHex: "#FF9500", defaultMerchant: "Octopus Auto Top-Up", defaultCategoryName: "", defaultPaymentMethodName: "CUHK Credit Card", defaultAmount: 250.00, transactionType: .transfer, isInstantOneTap: true, toPaymentMethodName: "Octopus")
    ]
}

// MARK: - Customize Quick Actions Sheet
public struct CustomizeQuickActionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var quickActionsJson: String
    let lang: String

    @State private var items: [QuickActionItem] = []
    @State private var editingItem: QuickActionItem? = nil

    public init(quickActionsJson: Binding<String>, currentActions: [QuickActionItem], lang: String) {
        self._quickActionsJson = quickActionsJson
        self._items = State(initialValue: currentActions)
        self.lang = lang
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items) { item in
                        Button {
                            editingItem = item
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.icon)
                                    .font(.title3)
                                    .foregroundStyle(Color(hex: item.colorHex))
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    HStack(spacing: 4) {
                                        if let amt = item.defaultAmount, amt > 0 {
                                            Text(String(format: "⚡ %@%.1f", item.transactionType == .income ? "+" : "-", amt))
                                                .foregroundStyle(item.transactionType == .income ? .green : .blue)
                                                .fontWeight(.semibold)
                                        }
                                        if !item.defaultMerchant.isEmpty {
                                            Text("• \(item.defaultMerchant)")
                                        }
                                        if !item.defaultCategoryName.isEmpty {
                                            Text("• \(item.defaultCategoryName)")
                                        }
                                        if !item.defaultPaymentMethodName.isEmpty {
                                            Text("• \(item.defaultPaymentMethodName)")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                }

                                Spacer()

                                Image(systemName: "pencil")
                                    .font(.caption.bold())
                                    .foregroundStyle(.blue)
                                    .padding(6)
                                    .background(Color.blue.opacity(0.12))
                                    .clipShape(Circle())
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation {
                                    items.removeAll(where: { $0.id == item.id })
                                    saveChanges()
                                }
                            } label: {
                                Label(L10n.tr("Delete", lang: lang), systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                editingItem = item
                            } label: {
                                Label(L10n.tr("Edit", lang: lang), systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                withAnimation {
                                    items.removeAll(where: { $0.id == item.id })
                                    saveChanges()
                                }
                            } label: {
                                Label(L10n.tr("Delete", lang: lang), systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { indexSet in
                        items.remove(atOffsets: indexSet)
                        saveChanges()
                    }
                    .onMove { indices, newOffset in
                        items.move(fromOffsets: indices, toOffset: newOffset)
                        saveChanges()
                    }
                } header: {
                    Text(L10n.tr("Quick Actions", lang: lang)).lineLimit(1)
                } footer: {
                    Text(lang == "zh-HK" ? "點擊任何快捷鍵即可編輯詳情。向左滑動或在編輯頁面可直接刪除，點擊右上角「排序」可調整先後順序。" : "Tap any shortcut to edit its details. Swipe left or open edit sheet to delete. Use Edit above to reorder.").lineLimit(2)
                }

                Section {
                    Button {
                        let newItem = QuickActionItem(
                            title: "New Action",
                            icon: "tag.fill",
                            colorHex: "#007AFF"
                        )
                        items.append(newItem)
                        editingItem = newItem
                        saveChanges()
                    } label: {
                        Label(L10n.tr("New Shortcut", lang: lang), systemImage: "plus.circle.fill")
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                    }

                    Button(role: .destructive) {
                        items = QuickActionItem.defaultItems
                        saveChanges()
                    } label: {
                        Label(L10n.tr("Reset Defaults", lang: lang), systemImage: "arrow.counterclockwise")
                            .lineLimit(1)
                    }
                }
            }
            .navigationTitle(L10n.tr("Quick Actions", lang: lang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("Done", lang: lang)) {
                        saveChanges()
                        dismiss()
                    }
                    .bold()
                }
            }
            .sheet(item: $editingItem) { item in
                EditQuickActionSheet(
                    item: item,
                    lang: lang,
                    onSave: { updated in
                        if let index = items.firstIndex(where: { $0.id == updated.id }) {
                            items[index] = updated
                            saveChanges()
                        }
                    },
                    onDelete: { toDelete in
                        items.removeAll(where: { $0.id == toDelete.id })
                        saveChanges()
                    }
                )
            }
        }
    }

    private func saveChanges() {
        if let data = try? AppSerializationManager.shared.jsonEncoder.encode(items),
           let str = String(data: data, encoding: .utf8) {
            quickActionsJson = str
        }
    }
}

// MARK: - Edit Quick Action Sheet (With 1-Tap Expense / Income / Transfer & Fixed Amount)
public struct EditQuickActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryItem.name) private var categories: [CategoryItem]
    @Query(sort: \PaymentMethodItem.name) private var paymentMethods: [PaymentMethodItem]
    @AppStorage("default_currency") private var defaultCurrency: String = "HKD"

    @State private var item: QuickActionItem
    let lang: String
    let onSave: (QuickActionItem) -> Void
    var onDelete: ((QuickActionItem) -> Void)? = nil

    @State private var title: String
    @State private var selectedIcon: String
    @State private var selectedColor: String
    @State private var transactionType: TransactionType
    @State private var amountString: String
    @State private var isInstantOneTap: Bool
    @State private var merchant: String
    @State private var categoryName: String
    @State private var paymentMethodName: String

    let availableIcons = [
        "plus.circle.fill", "wave.3.forward.circle.fill", "cup.and.saucer.fill",
        "cart.fill", "fork.knife", "tram.fill", "bag.fill", "fuelpump.fill",
        "film.fill", "heart.fill", "bolt.fill", "banknote.fill",
        "arrow.down.left.circle.fill", "arrow.triangle.2.circlepath.circle.fill"
    ]

    let availableColors = [
        "#007AFF", "#FF9500", "#34C759", "#AF52DE",
        "#FF2D55", "#5856D6", "#FF3B30", "#8E8E93"
    ]

    public init(
        item: QuickActionItem,
        lang: String,
        onSave: @escaping (QuickActionItem) -> Void,
        onDelete: ((QuickActionItem) -> Void)? = nil
    ) {
        self._item = State(initialValue: item)
        self.lang = lang
        self.onSave = onSave
        self.onDelete = onDelete
        self._title = State(initialValue: item.title)
        self._selectedIcon = State(initialValue: item.icon)
        self._selectedColor = State(initialValue: item.colorHex)
        self._transactionType = State(initialValue: item.transactionType)
        if let amt = item.defaultAmount, amt > 0 {
            self._amountString = State(initialValue: String(format: "%.2f", amt))
        } else {
            self._amountString = State(initialValue: "")
        }
        self._isInstantOneTap = State(initialValue: item.isInstantOneTap ?? (item.defaultAmount != nil && (item.defaultAmount ?? 0) > 0))
        self._merchant = State(initialValue: item.defaultMerchant)
        self._categoryName = State(initialValue: item.defaultCategoryName)
        self._paymentMethodName = State(initialValue: item.defaultPaymentMethodName)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(lang == "zh-HK" ? "一鍵記帳設定 (1-Tap Instant Log)" : "1-Tap Instant Logging") {
                    Picker(lang == "zh-HK" ? "類型" : "Type", selection: $transactionType) {
                        Text(L10n.tr("Expense", lang: lang)).tag(TransactionType.expense)
                        Text(L10n.tr("Income", lang: lang)).tag(TransactionType.income)
                        Text(L10n.tr("Transfer", lang: lang)).tag(TransactionType.transfer)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text(lang == "zh-HK" ? "固定金額 (\(defaultCurrency))" : "Fixed Amount (\(defaultCurrency))")
                        Spacer()
                        TextField(lang == "zh-HK" ? "留空則每次輸入" : "Leave blank to ask", text: $amountString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.body.bold())
                            .foregroundStyle(transactionType == .income ? .green : .blue)
                            .onChange(of: amountString) { _, newValue in
                                if let val = Double(newValue), val > 0 {
                                    isInstantOneTap = true
                                }
                            }
                    }

                    if let val = Double(amountString), val > 0 {
                        Toggle(
                            lang == "zh-HK" ? "點擊即直接記帳 (免開表單)" : "1-Tap Instant Log (Skip Form)",
                            isOn: $isInstantOneTap
                        )
                    }
                }

                Section(L10n.tr("Shortcut Title", lang: lang)) {
                    TextField("Title", text: $title)
                        .lineLimit(1)
                }

                Section(L10n.tr("Icon & Color", lang: lang)) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(availableIcons, id: \.self) { icon in
                                Button {
                                    selectedIcon = icon
                                } label: {
                                    Image(systemName: icon)
                                        .font(.title2)
                                        .frame(width: 42, height: 42)
                                        .background(selectedIcon == icon ? Color(hex: selectedColor).opacity(0.2) : Color(.tertiarySystemFill))
                                        .foregroundStyle(selectedIcon == icon ? Color(hex: selectedColor) : .primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(selectedIcon == icon ? Color(hex: selectedColor) : Color.clear, lineWidth: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    HStack(spacing: 12) {
                        ForEach(availableColors, id: \.self) { colorHex in
                            Button {
                                selectedColor = colorHex
                            } label: {
                                Circle()
                                    .fill(Color(hex: colorHex))
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: selectedColor == colorHex ? 2.5 : 0)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(lang == "zh-HK" ? "預設商戶、分類及帳戶" : "Preset Details") {
                    TextField(L10n.tr("Preset Merchant", lang: lang), text: $merchant)
                        .lineLimit(1)

                    Picker(L10n.tr("Preset Category", lang: lang), selection: $categoryName) {
                        Text(lang == "zh-HK" ? "預設" : "Default").tag("")
                        ForEach(categories) { cat in
                            Text(cat.name).tag(cat.name)
                        }
                    }

                    Picker(L10n.tr("Preset Payment", lang: lang), selection: $paymentMethodName) {
                        Text(lang == "zh-HK" ? "預設" : "Default").tag("")
                        ForEach(paymentMethods) { pm in
                            Text(pm.name).tag(pm.name)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        onDelete?(item)
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Label(L10n.tr("Delete", lang: lang), systemImage: "trash.fill")
                                .foregroundStyle(.red)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(L10n.tr("Edit Shortcut", lang: lang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Cancel", lang: lang)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("Done", lang: lang)) {
                        var updated = item
                        updated.title = title
                        updated.icon = selectedIcon
                        updated.colorHex = selectedColor
                        updated.transactionType = transactionType
                        if let val = Double(amountString), val > 0 {
                            updated.defaultAmount = val
                            updated.isInstantOneTap = isInstantOneTap
                        } else {
                            updated.defaultAmount = nil
                            updated.isInstantOneTap = false
                        }
                        updated.defaultMerchant = merchant
                        updated.defaultCategoryName = categoryName
                        updated.defaultPaymentMethodName = paymentMethodName
                        onSave(updated)
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}
