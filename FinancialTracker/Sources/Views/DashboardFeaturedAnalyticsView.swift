//
//  DashboardFeaturedAnalyticsView.swift
//  Worthly
//

import Foundation
import SwiftUI
import Charts

// MARK: - Featured Analytics Snapshot Section on Dashboard
public struct DashboardFeaturedAnalyticsView: View {
    @Binding public var activeSnapshot: String
    public let dayOfWeek: [DashboardDayItem]
    public let cashFlow: [DashboardFlowBar]
    public let categories: [DashboardCatShare]
    public let paymentMethods: [DashboardMethodItem]
    public let topMerchants: [DashboardMerchantItem]
    public let defaultCurrency: String
    public let appLanguage: String
    public var onNavigateToAnalytics: (() -> Void)?

    public init(
        activeSnapshot: Binding<String>,
        dayOfWeek: [DashboardDayItem],
        cashFlow: [DashboardFlowBar],
        categories: [DashboardCatShare],
        paymentMethods: [DashboardMethodItem],
        topMerchants: [DashboardMerchantItem],
        defaultCurrency: String,
        appLanguage: String,
        onNavigateToAnalytics: (() -> Void)? = nil
    ) {
        self._activeSnapshot = activeSnapshot
        self.dayOfWeek = dayOfWeek
        self.cashFlow = cashFlow
        self.categories = categories
        self.paymentMethods = paymentMethods
        self.topMerchants = topMerchants
        self.defaultCurrency = defaultCurrency
        self.appLanguage = appLanguage
        self.onNavigateToAnalytics = onNavigateToAnalytics
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.tr("Financial Breakdown", lang: appLanguage))
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    snapshotPill(title: L10n.tr("Day of Week", lang: appLanguage), key: "dayOfWeek", icon: "calendar")
                    snapshotPill(title: L10n.tr("Categories", lang: appLanguage), key: "categories", icon: "chart.pie.fill")
                    snapshotPill(title: L10n.tr("Cash Flow", lang: appLanguage), key: "cashFlow", icon: "arrow.left.arrow.right")
                    snapshotPill(title: L10n.tr("Payment Share", lang: appLanguage), key: "paymentMethods", icon: "creditcard.fill")
                    snapshotPill(title: L10n.tr("Top Merchants", lang: appLanguage), key: "topMerchants", icon: "building.2.fill")
                }
                .padding(.vertical, 2)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                switch activeSnapshot {
                case "categories":
                    MiniCategorySnapshot(data: categories, currency: defaultCurrency)
                case "cashFlow":
                    MiniCashFlowSnapshot(data: cashFlow)
                case "paymentMethods":
                    MiniPaymentMethodSnapshot(data: paymentMethods)
                case "topMerchants":
                    MiniTopMerchantsSnapshot(data: topMerchants)
                default:
                    MiniDayOfWeekSnapshot(data: dayOfWeek)
                }
                
                Divider()
                    .padding(.top, 6)
                
                Button {
                    onNavigateToAnalytics?()
                } label: {
                    HStack {
                        Text(L10n.tr("View Full Analytics", lang: appLanguage))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundStyle(.blue)
                    .padding(.top, 4)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
        }
    }

    private func snapshotPill(title: String, key: String, icon: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                activeSnapshot = key
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(activeSnapshot == key ? Color.blue : Color(.tertiarySystemFill))
            .foregroundStyle(activeSnapshot == key ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
