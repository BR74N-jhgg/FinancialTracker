//
//  DashboardRecentTransactionsView.swift
//  Worthly
//

import Foundation
import SwiftUI

// MARK: - Recent Transactions Card List on Dashboard
public struct DashboardRecentTransactionsView: View {
    public let transactions: [TransactionItem]
    public let defaultCurrency: String
    public let appLanguage: String
    public let onSelectTransaction: (TransactionItem) -> Void

    public init(
        transactions: [TransactionItem],
        defaultCurrency: String,
        appLanguage: String,
        onSelectTransaction: @escaping (TransactionItem) -> Void
    ) {
        self.transactions = transactions
        self.defaultCurrency = defaultCurrency
        self.appLanguage = appLanguage
        self.onSelectTransaction = onSelectTransaction
    }

    public var body: some View {
        let recentSlice = Array(transactions.prefix(6))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.tr("Recent Transactions", lang: appLanguage))
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            
            if recentSlice.isEmpty {
                VStack(spacing: 8) {
                    Text(L10n.tr("No transactions recorded yet.", lang: appLanguage))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 0) {
                    ForEach(recentSlice) { item in
                        Button {
                            onSelectTransaction(item)
                        } label: {
                            HStack(spacing: 12) {
                                let icon = item.type == .transfer ? "arrow.left.arrow.right" : (item.category?.iconName ?? "tag.fill")
                                let iconColor = item.type == .transfer ? Color.orange : Color(hex: item.category?.colorHex ?? "#007AFF")
                                
                                Image(systemName: icon)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(width: 38, height: 38)
                                    .background(iconColor)
                                    .clipShape(Circle())
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(item.merchant.isEmpty ? (item.category?.name ?? "Other") : item.merchant)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                        
                                        if item.isExcludedFromBudget {
                                            Text(L10n.tr("Reimbursable", lang: appLanguage))
                                                .font(.system(size: 9, weight: .bold))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Color.purple.opacity(0.15))
                                                .foregroundStyle(Color.purple)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    
                                    HStack(spacing: 5) {
                                        Image(systemName: item.paymentMethod?.iconName ?? "creditcard")
                                        Text(item.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                                            .lineLimit(1)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                if item.type == .transfer {
                                    Text(String(format: "⇄ %@ %.2f", defaultCurrency, item.amount))
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(Color.orange)
                                        .lineLimit(1)
                                } else {
                                    Text(String(format: "%@%@ %.2f", item.type == .income ? "+" : "-", defaultCurrency, item.amount))
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(item.type == .income ? .green : .primary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                        }
                        .buttonStyle(.plain)
                        
                        if item.id != recentSlice.last?.id {
                            Divider()
                                .padding(.leading, 62)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
            }
        }
    }
}
