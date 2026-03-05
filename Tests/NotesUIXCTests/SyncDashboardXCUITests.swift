import XCTest

final class SyncDashboardXCUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp()
        navigateToTab(app, "Sync")
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Tests

    func testSyncCalendarFieldExists() {
        let field = app.textFields["syncCalendarField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Sync calendar field should exist")
    }

    func testSyncCalendarFieldAcceptsText() {
        let field = app.textFields["syncCalendarField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("test-calendar-id")

        let value = field.value as? String ?? ""
        XCTAssertTrue(value.contains("test-calendar-id"), "Calendar field should contain typed text, got: '\(value)'")
    }

    func testRunSyncButtonExists() {
        let button = app.buttons["runSyncButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Run sync button should exist")
    }

    func testSyncStatusTextExists() {
        let status = element(in: app, identifier: "syncStatusText")
        XCTAssertTrue(status.waitForExistence(timeout: 5), "Sync status text should exist")
    }

    func testRunSyncButtonTapDoesNotCrash() {
        let button = app.buttons["runSyncButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()

        // Verify app remains responsive after sync
        let syncTab = app.radioButtons["Sync"]
        XCTAssertTrue(syncTab.waitForExistence(timeout: 5), "App should remain responsive after sync button tap")
    }
}
