// MARK: - Embedded Stress Test View
/* import Darwin

public struct StressTestView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allTransactions: [TransactionItem]
    
    @State private var itemCount: Int = 2500
    @State private var includeExtremeAmounts: Bool = true
    @State private var includeUnicodeAndEmojis: Bool = true
    @State private var includeEdgeDates: Bool = true
    @State private var includeOrphanedRelationships: Bool = true
    @State private var includeSpecialCharacters: Bool = true
    
    @State private var isRunning: Bool = false
    @State private var progressValue: Double = 0.0
    @State private var progressStatus: String = ""
    @State private var latestReport: StressTestReport? = nil
    @State private var showingPurgeAlert: Bool = false
    @State private var purgedCount: Int? = nil
    
    private var stressTestItemsCount: Int {
        allTransactions.filter { $0.notes.contains(StressTestEngine.markerTag) }.count
    }
    
    public init() {}
    
    public var body: some View {
        Form {
            // MARK: - Current Database Snapshot
            Section("Current Database Status") {
                HStack {
                    Text("Total Transactions")
                    Spacer()
                    Text("\(allTransactions.count)")
                        .bold()
                }
                HStack {
                    Text("Stress Test Tagged Items")
                    Spacer()
                    Text("\(stressTestItemsCount)")
                        .foregroundStyle(stressTestItemsCount > 0 ? Color.orange : Color.secondary)
                        .bold()
                }
                HStack {
                    Text("Current Memory Usage")
                    Spacer()
                    Text(String(format: "%.1f MB", StressTestEngine.shared.getMemoryUsageMB()))
                        .foregroundStyle(.secondary)
                }
            }
            
            // MARK: - Configuration
            Section("Stress Test Parameters") {
                Picker("Item Volume", selection: $itemCount) {
                    Text("500 Items (Moderate)").tag(500)
                    Text("1,500 Items (Heavy)").tag(1500)
                    Text("2,500 Items (Extreme)").tag(2500)
                    Text("5,000 Items (Stress Cap)").tag(5000)
                }
                
                Toggle("Extreme Amounts (0.01 - 10M)", isOn: $includeExtremeAmounts)
                Toggle("Unicode & Emojis (中文, 🍔, ☕️)", isOn: $includeUnicodeAndEmojis)
                Toggle("Edge Dates (Leap Day, 2-Year Spread)", isOn: $includeEdgeDates)
                Toggle("Orphaned Items (nil Category/Payment)", isOn: $includeOrphanedRelationships)
                Toggle("Special Characters & Max Strings", isOn: $includeSpecialCharacters)
            }
            
            // MARK: - Execution Action
            Section {
                if isRunning {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: progressValue)
                            .tint(.blue)
                        HStack {
                            Text(progressStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(progressValue * 100))%")
                                .font(.caption.bold())
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Button {
                        runTest()
                    } label: {
                        HStack {
                            Spacer()
                            Label(String(format: "Run Stress Test (%d Items)", itemCount), systemImage: "bolt.fill")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.blue)
                            Spacer()
                        }
                    }
                }
            }
            
            // MARK: - Diagnostic Benchmark Report
            if let report = latestReport {
                Section("Benchmark Scorecard") {
                    HStack {
                        Text("Items Inserted")
                        Spacer()
                        Text("\(report.totalItemsGenerated)").bold()
                    }
                    HStack {
                        Text("Batch Insert Duration")
                        Spacer()
                        Text(String(format: "%.2f ms", report.batchInsertTimeMs)).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("DB Fetch Latency")
                        Spacer()
                        Text(String(format: "%.2f ms", report.fetchTimeMs)).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Avg Search Filter")
                        Spacer()
                        Text(String(format: "%.2f ms", report.searchLatencyMs)).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Analytics Computation")
                        Spacer()
                        Text(String(format: "%.2f ms", report.analyticsComputationTimeMs)).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("WidgetKit Sync Duration")
                        Spacer()
                        Text(String(format: "%.2f ms", report.widgetSyncTimeMs)).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Memory Delta")
                        Spacer()
                        Text(String(format: "%+.1f MB", report.endMemoryMB - report.startMemoryMB))
                            .foregroundStyle(report.endMemoryMB >= report.startMemoryMB ? Color.orange : Color.green)
                    }
                }
            }
            
            // MARK: - Safe Purge Option
            if stressTestItemsCount > 0 {
                Section {
                    Button(role: .destructive) {
                        showingPurgeAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Label(String(format: "Purge Stress Test Data (%d Items)", stressTestItemsCount), systemImage: "trash.fill")
                                .foregroundStyle(.red)
                            Spacer()
                        }
                    }
                } footer: {
                    Text("Only removes transactions generated with [STRESS_TEST]. All your real transactions and settings remain untouched.")
                }
            }
        }
        .navigationTitle("Stress Testing")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Purge Stress Test Data?",
            isPresented: $showingPurgeAlert,
            titleVisibility: .visible
        ) {
            Button("Purge All \(stressTestItemsCount) Test Items", role: .destructive) {
                Task {
                    let count = await StressTestEngine.shared.purgeOnlyStressTestData(context: modelContext)
                    await MainActor.run {
                        purgedCount = count
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently remove the \(stressTestItemsCount) items created during stress testing. Your original data will not be affected.")
        }
    }
    
    private func runTest() {
        isRunning = true
        progressValue = 0.0
        progressStatus = "Initializing..."
        
        let config = StressTestConfig(
            itemCount: itemCount,
            includeExtremeAmounts: includeExtremeAmounts,
            includeUnicodeAndEmojis: includeUnicodeAndEmojis,
            includeEdgeDates: includeEdgeDates,
            includeOrphanedRelationships: includeOrphanedRelationships,
            includeSpecialCharacters: includeSpecialCharacters
        )
        
        Task {
            let report = await StressTestEngine.shared.runFullStressTest(
                context: modelContext,
                config: config
            ) { progress, status in
                Task { @MainActor in
                    self.progressValue = progress
                    self.progressStatus = status
                }
            }
            
            await MainActor.run {
                self.latestReport = report
                self.isRunning = false
            }
        }
    }
}

// MARK: - Stress Test Configuration
public struct StressTestConfig: Equatable {
    public var itemCount: Int = 1000
    public var includeExtremeAmounts: Bool = true
    public var includeUnicodeAndEmojis: Bool = true
    public var includeEdgeDates: Bool = true
    public var includeOrphanedRelationships: Bool = true
    public var includeSpecialCharacters: Bool = true
    
    public init(
        itemCount: Int = 1000,
        includeExtremeAmounts: Bool = true,
        includeUnicodeAndEmojis: Bool = true,
        includeEdgeDates: Bool = true,
        includeOrphanedRelationships: Bool = true,
        includeSpecialCharacters: Bool = true
    ) {
        self.itemCount = itemCount
        self.includeExtremeAmounts = includeExtremeAmounts
        self.includeUnicodeAndEmojis = includeUnicodeAndEmojis
        self.includeEdgeDates = includeEdgeDates
        self.includeOrphanedRelationships = includeOrphanedRelationships
        self.includeSpecialCharacters = includeSpecialCharacters
    }
}

// MARK: - Stress Test Benchmark Report
public struct StressTestReport: Identifiable, Equatable {
    public var id: UUID = UUID()
    public var totalItemsGenerated: Int = 0
    public var batchInsertTimeMs: Double = 0.0
    public var fetchTimeMs: Double = 0.0
    public var searchLatencyMs: Double = 0.0
    public var searchBreakdown: [String: Double] = [:]
    public var analyticsComputationTimeMs: Double = 0.0
    public var widgetSyncTimeMs: Double = 0.0
    public var startMemoryMB: Double = 0.0
    public var endMemoryMB: Double = 0.0
    
    public init() {}
}

// MARK: - Stress Test Engine
public final class StressTestEngine {
    public static let shared = StressTestEngine()
    public static let markerTag = "[STRESS_TEST]"
    
    private init() {}
    
    public func getMemoryUsageMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / (1024.0 * 1024.0)
        }
        return 0.0
    }
    
    @MainActor
    public func runFullStressTest(
        context: ModelContext,
        config: StressTestConfig,
        progress: @escaping (Double, String) -> Void
    ) async -> StressTestReport {
        var report = StressTestReport()
        report.startMemoryMB = getMemoryUsageMB()
        
        progress(0.05, "Scanning categories & payment methods...")
        let catDesc = FetchDescriptor<CategoryItem>()
        let existingCats = (try? context.fetch(catDesc)) ?? []
        
        let pmDesc = FetchDescriptor<PaymentMethodItem>()
        let existingPMs = (try? context.fetch(pmDesc)) ?? []
        
        progress(0.15, String(format: "Generating %d test items...", config.itemCount))
        let items = generateParameterCoveredItems(count: config.itemCount, categories: existingCats, paymentMethods: existingPMs, config: config)
        report.totalItemsGenerated = items.count
        
        progress(0.35, "Batch inserting into SQLite...")
        let insertStart = DispatchTime.now()
        for item in items {
            context.insert(item)
        }
        try? context.save()
        let insertEnd = DispatchTime.now()
        report.batchInsertTimeMs = Double(insertEnd.uptimeNanoseconds - insertStart.uptimeNanoseconds) / 1_000_000.0
        
        progress(0.55, "Measuring fetch latency...")
        let fetchStart = DispatchTime.now()
        let fetchDesc = FetchDescriptor<TransactionItem>()
        let allTransactions = (try? context.fetch(fetchDesc)) ?? []
        let fetchEnd = DispatchTime.now()
        report.fetchTimeMs = Double(fetchEnd.uptimeNanoseconds - fetchStart.uptimeNanoseconds) / 1_000_000.0
        
        progress(0.70, "Benchmarking search filter...")
        let testQueries = ["MTR", "Dining", "Starbucks"]
        var totalSearchMs: Double = 0
        var breakdown: [String: Double] = [:]
        
        for q in testQueries {
            let qStart = DispatchTime.now()
            let filtered = allTransactions.filter { item in
                item.merchant.localizedCaseInsensitiveContains(q) ||
                item.notes.localizedCaseInsensitiveContains(q) ||
                (item.category?.name.localizedCaseInsensitiveContains(q) ?? false)
            }
            _ = filtered.count
            let qEnd = DispatchTime.now()
            let ms = Double(qEnd.uptimeNanoseconds - qStart.uptimeNanoseconds) / 1_000_000.0
            breakdown[q] = ms
            totalSearchMs += ms
        }
        report.searchBreakdown = breakdown
        report.searchLatencyMs = totalSearchMs / Double(testQueries.count)
        
        progress(0.85, "Benchmarking analytics aggregation...")
        let analyticsStart = DispatchTime.now()
        let calendar = Calendar.current
        let now = Date()
        let expenses = allTransactions.filter { $0.type == .expense }
        let thisMonthExpenses = expenses.filter {
            calendar.isDate($0.timestamp, equalTo: now, toGranularity: .month)
        }
        var dailyTotals = [Int: Double]()
        for t in thisMonthExpenses {
            let day = calendar.component(.day, from: t.timestamp)
            dailyTotals[day, default: 0.0] += t.amount
        }
        let analyticsEnd = DispatchTime.now()
        report.analyticsComputationTimeMs = Double(analyticsEnd.uptimeNanoseconds - analyticsStart.uptimeNanoseconds) / 1_000_000.0
        
        progress(0.95, "Synchronizing WidgetKit...")
        let widgetStart = DispatchTime.now()
        WidgetSyncManager.shared.syncWidget(context: context)
        let widgetEnd = DispatchTime.now()
        report.widgetSyncTimeMs = Double(widgetEnd.uptimeNanoseconds - widgetStart.uptimeNanoseconds) / 1_000_000.0
        
        report.endMemoryMB = getMemoryUsageMB()
        progress(1.0, "Benchmark complete.")
        return report
    }
    
    private func generateParameterCoveredItems(
        count: Int,
        categories: [CategoryItem],
        paymentMethods: [PaymentMethodItem],
        config: StressTestConfig
    ) -> [TransactionItem] {
        var result: [TransactionItem] = []
        result.reserveCapacity(count)
        
        let calendar = Calendar.current
        let now = Date()
        let standardMerchants = ["Starbucks", "MTR", "Wellcome", "Café de Coral", "PARKnSHOP", "Uniqlo", "Watsons"]
        
        for i in 0..<count {
            let isIncome = (i % 7 == 0)
            let type: TransactionType = isIncome ? .income : .expense
            let amount = config.includeExtremeAmounts && (i % 25 == 0) ? (Double(i * 100) + 0.99) : (Double((i % 450) + 15) + 0.50)
            let merchant = isIncome ? "Monthly Salary" : standardMerchants[i % standardMerchants.count]
            let date = calendar.date(byAdding: .day, value: -(i % 60), to: now) ?? now
            
            let category = (!categories.isEmpty && !(config.includeOrphanedRelationships && (i % 35 == 0))) ? categories[i % categories.count] : nil
            let paymentMethod = (!paymentMethods.isEmpty && !(config.includeOrphanedRelationships && (i % 45 == 0))) ? paymentMethods[i % paymentMethods.count] : nil
            let note = "\(Self.markerTag) Batch Item \(i + 1)"
            
            let item = TransactionItem(
                id: UUID(),
                timestamp: date,
                amount: amount,
                currency: "HKD",
                merchant: merchant,
                notes: note,
                type: type,
                category: category,
                paymentMethod: paymentMethod
            )
            result.append(item)
        }
        
        return result
    }
    
    @MainActor
    public func purgeOnlyStressTestData(context: ModelContext) async -> Int {
        let descriptor = FetchDescriptor<TransactionItem>()
        guard let all = try? context.fetch(descriptor) else { return 0 }
        
        var deletedCount = 0
        for item in all {
            if item.notes.contains(Self.markerTag) {
                context.delete(item)
                deletedCount += 1
            }
        }
        
        try? context.save()
        WidgetSyncManager.shared.syncWidget(context: context)
        return deletedCount
    }
}
*/
