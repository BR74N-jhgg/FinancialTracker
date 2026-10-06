//
//  PaymentMethodsReportView.swift
//  FinancialTracker
//

import SwiftUI
import SwiftData
import Charts

// MARK: - Report 4: Payment Method Distribution
struct PaymentMethodsReportView: View {
    let transactions: [TransactionItem]
    let currency: String
    @AppStorage("app_language") private var appLanguage: String = "en"
    
    @State private var methodShares: [MethodShare] = []
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
    
    nonisolated private struct PMInput: Sendable {
        let name: String
        let icon: String
        let colorHex: String
        let amount: Double
    }
    
    private func computeMetrics() async {
        let defaultName = L10n.tr("Other", lang: appLanguage)
        let inputs: [PMInput] = transactions.compactMap { item in
            guard item.type == .expense && !item.isExcludedFromBudget else { return nil }
            let name = item.paymentMethod?.name ?? defaultName
            let icon = item.paymentMethod?.iconName ?? "creditcard"
            let color = item.paymentMethod?.colorHex ?? "#007AFF"
            return PMInput(name: name, icon: icon, colorHex: color, amount: item.amount)
        }
        
        let result = await Task.detached(priority: .userInitiated) { () -> ([MethodShare], Double) in
            var groupedTotals = [String: Double]()
            var groupedCounts = [String: Int]()
            var metaMap = [String: (icon: String, color: String)]()
            
            for item in inputs {
                groupedTotals[item.name, default: 0.0] += item.amount
                groupedCounts[item.name, default: 0] += 1
                if metaMap[item.name] == nil {
                    metaMap[item.name] = (item.icon, item.colorHex)
                }
            }
            
            let shares = groupedTotals.map { name, total in
                let meta = metaMap[name] ?? ("creditcard", "#007AFF")
                return MethodShare(
                    name: name,
                    icon: meta.icon,
                    colorHex: meta.color,
                    total: total,
                    count: groupedCounts[name] ?? 0
                )
            }.sorted { $0.total > $1.total }
            
            let total = max(1.0, shares.reduce(0.0) { $0 + $1.total })
            return (shares, total)
        }.value
        
        self.methodShares = result.0
        self.grandTotal = result.1
    }
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.tr("Spending by Payment Method", lang: appLanguage))
                    .font(.headline)
                    .lineLimit(1)
                
                Chart(methodShares) { item in
                    SectorMark(
                        angle: .value("Amount", item.total),
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
            
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.tr("Payment Channel Breakdown", lang: appLanguage))
                    .font(.subheadline.bold())
                    .lineLimit(1)
                
                ForEach(methodShares) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.icon)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color(hex: item.colorHex))
                            .clipShape(Circle())
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.body.weight(.medium)).lineLimit(1)
                            Text("\(item.count) \(L10n.tr("transactions", lang: appLanguage))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            // ✅ Uses AppFormatters directly (no extension dependency)
                            Text(AppFormatters.formatCurrency(item.total, currency: currency)).font(.body.bold()).lineLimit(1)
                            Text("\(Int((item.total / grandTotal) * 100))%").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    if item.id != methodShares.last?.id { Divider() }
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
