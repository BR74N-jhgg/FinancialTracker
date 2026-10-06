//
//  TopMerchantsReportView.swift
//  FinancialTracker
//

import SwiftUI
import SwiftData
import Charts

// MARK: - Report 5: Top Merchants Leaderboard
struct TopMerchantsReportView: View {
    let transactions: [TransactionItem]
    let currency: String
    @AppStorage("app_language") private var appLanguage: String = "en"
    
        
    @State private var topMerchants: [MerchantRank] = []
    
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
    
    nonisolated private struct MerchantInput: Sendable {
        let merchant: String
        let amount: Double
    }
    
    private func computeMetrics() async {
        let defaultName = L10n.tr("General", lang: appLanguage)
        let inputs: [MerchantInput] = transactions.compactMap { item in
            guard item.type == .expense && !item.isExcludedFromBudget && !item.isExcludedFromBudget else { return nil }
            let name = item.merchant.isEmpty ? defaultName : item.merchant
            return MerchantInput(merchant: name, amount: item.amount)
        }
        
        let result = await Task.detached(priority: .userInitiated) { () -> [MerchantRank] in
            var groupedTotals = [String: Double]()
            var groupedCounts = [String: Int]()
            
            for item in inputs {
                groupedTotals[item.merchant, default: 0.0] += item.amount
                groupedCounts[item.merchant, default: 0] += 1
            }
            
            return groupedTotals.map { name, total in
                MerchantRank(name: name, total: total, count: groupedCounts[name] ?? 0)
            }
            .sorted { $0.total > $1.total }
            .prefix(6)
            .map { $0 }
        }.value
        
        self.topMerchants = result
    }
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.tr("Top Merchants by Spend", lang: appLanguage))
                    .font(.headline)
                    .lineLimit(1)
                
                Chart(topMerchants) { item in
                    BarMark(
                        x: .value("Amount", item.total),
                        y: .value("Merchant", item.name)
                    )
                    .foregroundStyle(Color.indigo.gradient)
                    .cornerRadius(6)
                }
                .frame(height: 230)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.tr("Merchant Rankings", lang: appLanguage))
                    .font(.subheadline.bold())
                    .lineLimit(1)
                
                ForEach(Array(topMerchants.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 12) {
                        Text("#\(index + 1)")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .frame(width: 28)
                            .lineLimit(1)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.body.weight(.medium)).lineLimit(1)
                            let avg = item.total / max(1, Double(item.count))
                            Text(String(format: "%d %@ • %@ %@ %.1f", item.count, L10n.tr("orders", lang: appLanguage), L10n.tr("Avg", lang: appLanguage), currency, avg))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Text(item.total.formattedCurrency(currency)).font(.body.bold()).lineLimit(1)
                    }
                    if index != topMerchants.count - 1 { Divider() }
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

