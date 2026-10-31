//
//  FinancialTrackerUITests.swift
//  FinancialTrackerUITests
//

import XCTest

final class FinancialTrackerUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        // Ensure app is terminated between tests
        XCUIApplication().terminate()
    }

    @MainActor
    func testExample() throws {
        let app = XCUIApplication()
        app.launch()

        // Basic smoke test: app reaches a main screen
        // Adjust the query if your root UI uses a different title/label
        let dashboard = app.navigationBars["Dashboard"].firstMatch
        let settingsTab = app.tabBars.buttons.firstMatch
        XCTAssertTrue(
            dashboard.waitForExistence(timeout: 8) || settingsTab.waitForExistence(timeout: 8),
            "App failed to show main UI after launch"
        )
    }

    @MainActor
    func testLaunchPerformance() throws {
        // Skip on CI / unstable simulator environments if needed
        // throw XCTSkip("Launch performance is environment-sensitive")

        if #available(iOS 13.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                let app = XCUIApplication()
                app.launch()
                app.terminate()
            }
        }
    }
}
