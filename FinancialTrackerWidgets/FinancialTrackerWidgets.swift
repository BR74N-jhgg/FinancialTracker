import WidgetKit
import SwiftUI

struct FinancialEntry: TimelineEntry {
    let date: Date
    let spentThisMonth: Double
    let monthlyBudget: Double
    let remainingBudget: Double
    let currency: String
}

struct FinancialTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> FinancialEntry {
        FinancialEntry(date: Date(), spentThisMonth: 4250.0, monthlyBudget: 15000.0, remainingBudget: 10750.0, currency: "HKD")
    }

    func getSnapshot(in context: Context, completion: @escaping (FinancialEntry) -> ()) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FinancialEntry>) -> ()) {
        let calendar = Calendar.current
        let now = Date()
        
        var spent: Double = 0.0
        var budget: Double = 15000.0
        var remaining: Double = 15000.0
        var currency: String = "HKD"
        
        // Fast, Standalone Path: Read from shared App Group UserDefaults
        let appGroupIdentifier = "group.com.financialtracker.app"
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            spent = sharedDefaults.double(forKey: "widget_spent_this_month")
            let storedBudget = sharedDefaults.double(forKey: "widget_monthly_budget")
            if storedBudget > 0 { budget = storedBudget }
            remaining = max(0, budget - spent)
            currency = sharedDefaults.string(forKey: "widget_currency") ?? "HKD"
        }
        
        let entry = FinancialEntry(
            date: now,
            spentThisMonth: spent,
            monthlyBudget: budget,
            remainingBudget: remaining,
            currency: currency
        )
        
        // Schedule next check every 15 minutes, or immediately on push reload
        let nextUpdate = calendar.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct FinancialWidgetEntryView : View {
    var entry: FinancialTimelineProvider.Entry
    @Environment(\.widgetFamily) var family

    private var roundedPercentage: Int {
        Int(((entry.spentThisMonth / max(1, entry.monthlyBudget)) * 100.0).rounded())
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: min(1.0, entry.spentThisMonth / max(1, entry.monthlyBudget))) {
                Image(systemName: "creditcard.fill")
            } currentValueLabel: {
                Text("\(roundedPercentage)%")
                    .font(.system(size: 10, weight: .bold))
            }
            .gaugeStyle(.accessoryCircular)
            
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Worthly Budget")
                    .font(.caption2.bold())
                Text(String(format: "%@ %.0f left", entry.currency, entry.remainingBudget))
                    .font(.subheadline.bold())
                ProgressView(value: min(1.0, entry.spentThisMonth / max(1, entry.monthlyBudget)))
            }
            
        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Worthly", systemImage: "wallet.pass.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                    Spacer()
                    Text("\(roundedPercentage)%")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%@ %.2f", entry.currency, entry.spentThisMonth))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text(String(format: "%@ %.0f remaining", entry.currency, entry.remainingBudget))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                ProgressView(value: min(1.0, entry.spentThisMonth / max(1, entry.monthlyBudget)))
                    .tint(.blue)
            }
            .padding(12)
        }
    }
}

struct FinancialTrackerWidgets: Widget {
    let kind: String = "FinancialTrackerWidgets"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FinancialTimelineProvider()) { entry in
            FinancialWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Worthly Budget")
        .description("Track your monthly budget and expenses at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
