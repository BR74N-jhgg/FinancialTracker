import SwiftUI
import SwiftData

public struct TransactionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TransactionItem.timestamp, order: .reverse) private var transactions: [TransactionItem]
    @Query(sort: \CategoryItem.name) private var categories: [CategoryItem]
    
    @AppStorage("app_language") private var appLanguage: String = "en"
    @State private var searchText = ""
    @State private var selectedCategoryId: UUID? = nil
    @State private var selectedItemToEdit: TransactionItem? = nil
    @State private var showingCategoryManager = false
    
    private var filteredTransactions: [TransactionItem] {
        transactions.filter { item in
            let matchesSearch = searchText.isEmpty ||
                item.merchant.localizedCaseInsensitiveContains(searchText) ||
                item.notes.localizedCaseInsensitiveContains(searchText) ||
                (item.category?.name.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (item.paymentMethod?.name.localizedCaseInsensitiveContains(searchText) ?? false)
            
            let matchesCategory = selectedCategoryId == nil || item.category?.id == selectedCategoryId
            return matchesSearch && matchesCategory
        }
    }
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            List {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(title: "All", isSelected: selectedCategoryId == nil) {
                            selectedCategoryId = nil
                        }
                        
                        ForEach(categories) { cat in
                            FilterChip(title: cat.name, icon: cat.iconName, isSelected: selectedCategoryId == cat.id) {
                                selectedCategoryId = cat.id
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                
                ForEach(filteredTransactions) { item in
                    Button {
                        selectedItemToEdit = item
                    } label: {
                        TransactionRowView(item: item)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteSingleItem(item)
                        } label: {
                            Label(L10n.tr("Delete", lang: appLanguage), systemImage: "trash.fill")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            selectedItemToEdit = item
                        } label: {
                            Label(L10n.tr("Edit", lang: appLanguage), systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button {
                            selectedItemToEdit = item
                        } label: {
                            Label("Edit Log", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            deleteSingleItem(item)
                        } label: {
                            Label("Delete Log", systemImage: "trash")
                        }
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .appPullToRefresh()
            .searchable(text: $searchText, prompt: "Search merchant, category, notes")
            .navigationTitle(L10n.tr("Transactions", lang: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCategoryManager = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .lineLimit(1)
                }
            }
            .sheet(item: $selectedItemToEdit) { item in
                EditTransactionView(item: item)
            }
            .sheet(isPresented: $showingCategoryManager) {
                CategoryManagementView()
            }
        }
    }
    
    private func deleteSingleItem(_ item: TransactionItem) {
        withAnimation {
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
    
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            var affectedIds = Set<UUID>()
            for index in offsets {
                let target = filteredTransactions[index]
                if let pmId = target.paymentMethod?.id { affectedIds.insert(pmId) }
                if let toId = target.toPaymentMethod?.id { affectedIds.insert(toId) }
                modelContext.delete(target)
            }
            AppDataStore.saveContext(modelContext)
            AccountBalanceManager.shared.recalculateBalances(
                forAccountIds: affectedIds.isEmpty ? nil : affectedIds,
                context: modelContext
            )
            WidgetSyncManager.shared.syncWidget(context: modelContext)
        }
    }
}

struct FilterChip: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon).font(.caption2)
                }
                Text(title).font(.caption.bold()).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(.secondarySystemFill))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

public struct TransactionRowView: View {
    let item: TransactionItem
    
    public var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.category?.iconName ?? "tag.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color(hex: item.category?.colorHex ?? "#007AFF"))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.merchant.isEmpty ? (item.category?.name ?? "General") : item.merchant)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                HStack(spacing: 6) {
                    Image(systemName: item.paymentMethod?.iconName ?? "creditcard")
                    Text(item.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 2) {
                    if item.type == .transfer {
                        Text("⇄")
                            .font(.caption.bold())
                            .foregroundStyle(.blue)
                    } else {
                        Text(item.type == .expense ? "-" : "+")
                    }
                    Text(item.amount.formattedCurrency(item.currency.isEmpty ? "HKD" : item.currency))
                }
                .font(.body.bold())
                .foregroundStyle(item.type == .expense ? Color.primary : (item.type == .transfer ? Color.blue : Color.green))
                .lineLimit(1)
                
                if item.isExcludedFromBudget {
                    Text("Reimbursable")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}
