//
//  DashboardQuickActionsView.swift
//  Worthly
//

import Foundation
import SwiftUI

// MARK: - Dashboard Quick Actions Bar Component
public struct DashboardQuickActionsView: View {
    public let quickActions: [QuickActionItem]
    public let defaultCurrency: String
    public let appLanguage: String
    public let instantLogBannerText: String?
    public let canUndoInstantLog: Bool
    public let onTapAction: (QuickActionItem) -> Void
    public let onInstantLogAction: (QuickActionItem, Double) -> Void
    public let onCustomAmountAction: (QuickActionItem) -> Void
    public let onEditAction: (QuickActionItem) -> Void
    public let onOpenCustomize: () -> Void
    public let onUndoInstantLog: () -> Void

    public init(
        quickActions: [QuickActionItem],
        defaultCurrency: String,
        appLanguage: String,
        instantLogBannerText: String?,
        canUndoInstantLog: Bool,
        onTapAction: @escaping (QuickActionItem) -> Void,
        onInstantLogAction: @escaping (QuickActionItem, Double) -> Void,
        onCustomAmountAction: @escaping (QuickActionItem) -> Void,
        onEditAction: @escaping (QuickActionItem) -> Void,
        onOpenCustomize: @escaping () -> Void,
        onUndoInstantLog: @escaping () -> Void
    ) {
        self.quickActions = quickActions
        self.defaultCurrency = defaultCurrency
        self.appLanguage = appLanguage
        self.instantLogBannerText = instantLogBannerText
        self.canUndoInstantLog = canUndoInstantLog
        self.onTapAction = onTapAction
        self.onInstantLogAction = onInstantLogAction
        self.onCustomAmountAction = onCustomAmountAction
        self.onEditAction = onEditAction
        self.onOpenCustomize = onOpenCustomize
        self.onUndoInstantLog = onUndoInstantLog
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.tr("Quick Actions", lang: appLanguage))
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button(action: onOpenCustomize) {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.caption2)
                        Text(L10n.tr("Customize", lang: appLanguage))
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemFill))
                    .foregroundStyle(.primary)
                    .clipShape(Capsule())
                }
            }
            
            if let bannerText = instantLogBannerText {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(bannerText)
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    if canUndoInstantLog {
                        Button(action: onUndoInstantLog) {
                            Text(appLanguage == "zh-HK" ? "撤銷" : "Undo")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.15))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(quickActions) { action in
                        Button {
                            onTapAction(action)
                        } label: {
                            VStack(spacing: 5) {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: action.icon)
                                        .font(.title3)
                                        .foregroundStyle(Color(hex: action.colorHex))
                                        .frame(width: 36, height: 28)
                                    
                                    if action.shouldInstantLog {
                                        Image(systemName: "bolt.fill")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(3)
                                            .background(action.transactionType == .income ? Color.green : Color.blue)
                                            .clipShape(Circle())
                                            .offset(x: 8, y: -3)
                                    }
                                }
                                
                                Text(action.title)
                                    .font(.caption.bold())
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                
                                if let amt = action.defaultAmount, amt > 0 {
                                    Text(
                                        String(
                                            format: "%@%@ %.1f",
                                            action.transactionType == .income ? "+" : (action.transactionType == .transfer ? "⇄ " : "-"),
                                            defaultCurrency,
                                            amt
                                        )
                                    )
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(action.transactionType == .income ? .green : .secondary)
                                    .lineLimit(1)
                                } else {
                                    Text(appLanguage == "zh-HK" ? "輸入金額" : "Tap to enter")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(width: 104, height: 84)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if let amt = action.defaultAmount, amt > 0 {
                                Button {
                                    onInstantLogAction(action, amt)
                                } label: {
                                    Label(
                                        appLanguage == "zh-HK" ? "一鍵即時記帳" : "Instant Log Now",
                                        systemImage: "bolt.fill"
                                    )
                                }
                            }
                            Button {
                                onCustomAmountAction(action)
                            } label: {
                                Label(
                                    appLanguage == "zh-HK" ? "自訂金額記帳..." : "Log with Custom Amount...",
                                    systemImage: "keyboard"
                                )
                            }
                            Button {
                                onEditAction(action)
                            } label: {
                                Label(
                                    appLanguage == "zh-HK" ? "編輯此快捷鍵..." : "Edit Shortcut...",
                                    systemImage: "pencil"
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
