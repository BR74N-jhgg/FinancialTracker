//
//  CashFlowReportView.swift
//  FinancialTracker
//

import SwiftUI
import SwiftData
import Charts

// MARK: - Report 2: Cash Flow (Income vs Expense)
struct CashFlowReportView: View {
    let transactions: [TransactionItem]
    let currency: String
    @AppStorage("app_language") private var appLanguage: String = "en"
    
        
    @State private var flowData: [FlowItem] = []
    @State private var netSavings: Double = 0.0
    @State private var savingsRate: Int = 0
    
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
    
    nonisolated private struct FlowInput: Sendable {
        let isIncome: Bool
        let amount: Double
    }
    
    private func computeMetrics() async {
        let inputs: [FlowInput] = transactions.map { item in
            FlowInput(isIncome: item.type == .income, amount: item.amount)
        }
        let incomeLabel = L10n.tr("Income", lang: appLanguage)
        let expenseLabel = L10n.tr("Expense", lang: appLanguage)
        
        let result = await Task.detached(priority: .userInitiated) { () -> ([FlowItem], Double, Int) in
            var totalIncome: Double = 0
            var totalExpense: Double = 0
            for item in inputs {
                if item.isIncome {
                    totalIncome += item.amount
                } else {
                    totalExpense += item.amount
                }
            }
            let flows = [
                FlowItem(type: "Income", localizedType: incomeLabel, amount: totalIncome, isIncome: true),
                FlowItem(type: "Expense", localizedType: expenseLabel, amount: totalExpense, isIncome: false)
            ]
            let net = totalIncome - totalExpense
            let rate = totalIncome > 0 ? Int((net / totalIncome) * 100) : 0
            return (flows, net, rate)
        }.value
        
        self.flowData = result.0
        self.netSavings = result.1
        self.savingsRate = result.2
    }
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.tr("Income vs. Expense Flow", lang: appLanguage))
                    .font(.headline)
                    .lineLimit(1)
                
                Chart(flowData) { item in
                    BarMark(
                        x: .value("Type", item.localizedType),
                        y: .value("Amount", item.amount)
                    )
                    .foregroundStyle(item.color)
                    .cornerRadius(8)
                }
                .frame(height: 230)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            
            HStack(spacing: 12) {
                InsightCard(
                    title: L10n.tr("Net Savings", lang: appLanguage),
                    value: netSavings.formattedCurrency(currency),
                    subtitle: netSavings >= 0 ? L10n.tr("Surplus", lang: appLanguage) : L10n.tr("Deficit", lang: appLanguage),
                    icon: netSavings >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill",
                    color: netSavings >= 0 ? .green : .red
                )
                
                InsightCard(
                    title: L10n.tr("Savings Rate", lang: appLanguage),
                    value: "\(max(0, savingsRate))%",
                    subtitle: L10n.tr("Of total income", lang: appLanguage),
                    icon: "percent",
                    color: .blue
                )
            }
            .padding(.horizontal)
        }
        .task(id: calculationKey) {
            await computeMetrics()
        }
    }
}

