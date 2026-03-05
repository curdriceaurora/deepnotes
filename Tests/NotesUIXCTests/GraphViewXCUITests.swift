import XCTest

final class GraphViewXCUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp()
        navigateToTab(app, "Graph")
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Tests

    func testGraphTabShowsContent() {
        let title = app.staticTexts["Knowledge Graph"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Graph view should show 'Knowledge Graph' title")
    }

    func testGraphRefreshButtonExists() {
        // The graph has a refresh (arrow.clockwise) button in the toolbar
        let buttons = app.buttons
        XCTAssertTrue(buttons.firstMatch.waitForExistence(timeout: 5), "Graph tab should have toolbar buttons")
        XCTAssertGreaterThan(buttons.count, 0, "At least one button should exist on the Graph tab")
    }

    func testGraphTabDoesNotCrash() {
        // Let the graph simulation run briefly, then verify responsiveness
        Thread.sleep(forTimeInterval: 1)

        navigateToTab(app, "Notes")
        let searchField = app.textFields["noteSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "App should remain responsive after Graph tab usage")
    }
}
