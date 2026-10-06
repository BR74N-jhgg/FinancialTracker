//
//  CategoryBreakdownReportView.swift
//  FinancialTracker
//

import SwiftUI
import SwiftData
import Charts

// MARK: - Report 6: Category Breakdown
struct CategoryBreakdownReportView: View {
    let transactions: [TransactionItem]
    let currency: String
    @AppStorage("app_language") private var appLanguage: String = "en"
    
        
    @State private var categoryTotals: [CatTotal] = []
    @State private var grandTotal: Double = 1.0
    
    private var calculationKey: Int {
        var hasher = Hasher()
        hasher.combine(transactions.count)
        hasher.combine(appLanguage)
        if let first = transactions.first {
            hasher.combine(first.timestamp)
            hasher.combine(first.amount)
        }
        return hasher.finalize()
    }
    
    nonisolated private struct CatInput: Sendable {
        let name: String
        let icon: String
        let colorHex: String
        let amount: Double
    }
    
    private func computeMetrics() async {
        let defaultCat = L10n.tr("Uncategorized", lang: appLanguage)
        let inputs: [CatInput] = transactions.compactMap { item in
            guard item.type == .expense && !item.isExcludedFromBudget && !item.isExcludedFromBudget else { return nil }
            let name = item.category?.name ?? defaultCat
            let icon = item.category?.iconName ?? "tag.fill"
            let color = item.category?.colorHex ?? "#8E8E93"
            return CatInput(name: name, icon: icon, colorHex: color, amount: item.amount)
        }
        
        let result = await Task.detached(priority: .userInitiated) { () -> ([CatTotal], Double) in
            var groupedTotals = [String: Double]()
            var metaMap = [String: (icon: String, color: String)]()
            
            for item in inputs {
                groupedTotals[item.name, default: 0.0] += item.amount
                if metaMap[item.name] == nil {
                    metaMap[item.name] = (item.icon, item.colorHex)
                }
            }
            
            let totals = groupedTotals.map { name, total in
                let meta = metaMap[name] ?? ("tag.fill", "#8E8E93")
                return CatTotal(name: name, icon: meta.icon, colorHex: meta.color, total: total)
            }.sorted { $0.total > $1.total }
            
            let gTotal = max(1.0, totals.reduce(0.0) { $0 + $1.total })
            return (totals, gTotal)
        }.value
        
        self.categoryTotals = result.0
        self.grandTotal = result.1
    }
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.tr("Breakdown by Category", lang: appLanguage))
                    .font(.headline)
                    .lineLimit(1)
                
                Chart(categoryTotals) { item in
                    SectorMark(
                        angle: .value("Total", item.total),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .cornerRadius(5)
                    .foregroundStyle(Color(hex: item.colorHex))
                }
                .frame(height: 230)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.tr("Top Spending Categories", lang: appLanguage))
                    .font(.headline)
                    .lineLimit(1)
                
                ForEach(categoryTotals) { item in
                    VStack(spacing: 6) {
                        HStack {
                            Label(item.name, systemImage: item.icon)
                                .font(.subheadline)
                                .foregroundStyle(Color(hex: item.colorHex))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Text(item.total.formattedCurrency(currency)).font(.subheadline.bold()).lineLimit(1)
                            Text("\(Int((item.total / grandTotal) * 100))%").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        
                        ProgressView(value: item.total / grandTotal)
                            .tint(Color(hex: item.colorHex))
                    }
                    if item.id != categoryTotals.last?.id {
                        Divider()
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        }
        .task(id: calculationKey) {
            await computeMetrics()
        }
    }
}


