import XCTest

final class QuickOpenXCUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    /// Open the Quick Open sheet.
    private func openQuickOpen() {
        let quickOpenButton = app.buttons["quickOpenButton"]
        XCTAssertTrue(quickOpenButton.waitForExistence(timeout: 5))
        quickOpenButton.tap()

        let searchField = app.textFields["quickOpenSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Quick Open search field should appear")
    }

    // MARK: - Tests

    func testQuickOpenButtonOpensSheet() {
        openQuickOpen()
        // The helper already asserts the search field exists; verify the results list too
        let resultsList = element(in: app, identifier: "quickOpenResultsList")
        XCTAssertTrue(resultsList.waitForExistence(timeout: 5), "Quick Open results list should be visible")
    }

    func testQuickOpenShowsAllNotes() {
        openQuickOpen()

        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'quickOpenRow_'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.allElementsBoundByAccessibilityElement.count, 3, "Should show all 3 seeded notes")
    }

    func testQuickOpenSearchFilters() {
        openQuickOpen()

        let searchField = app.textFields["quickOpenSearchField"]
        searchField.tap()
        searchField.typeText("Vendor")

        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'quickOpenRow_'"))
        let result = waitForPredicate("count < 3", object: rows)
        XCTAssertEqual(result, .completed, "Filtering should reduce results")
        XCTAssertGreaterThan(
            rows.allElementsBoundByAccessibilityElement.count, 0,
            "Should still have at least one matching result",
        )
    }

    func testQuickOpenSelectNavigatesToNote() {
        openQuickOpen()

        let firstRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'quickOpenRow_'")).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.tap()

        // Sheet should dismiss
        let searchField = app.textFields["quickOpenSearchField"]
        waitForDisappearance(of: searchField)

        // Note title field should be populated
        let titleField = app.textFields["noteTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "Note title field should appear after quick open selection")
    }

    func testQuickOpenCloseButtonDismisses() {
        openQuickOpen()

        let closeButton = app.buttons["quickOpenCloseButton"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        closeButton.tap()

        let searchField = app.textFields["quickOpenSearchField"]
        let result = waitForDisappearance(of: searchField)
        XCTAssertEqual(result, .completed, "Quick Open sheet should dismiss after close button tap")
    }
}
