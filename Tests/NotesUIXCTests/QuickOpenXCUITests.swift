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
        let searchField = app.textFields["quickOpenSearchField"]
        XCTAssertTrue(searchField.exists, "Quick Open search field should be visible")
    }

    func testQuickOpenShowsAllNotes() {
        openQuickOpen()

        let resultsList = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'quickOpenResultsList'")).firstMatch
        XCTAssertTrue(resultsList.waitForExistence(timeout: 5), "Quick Open results list should exist")

        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'quickOpenRow_'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.allElementsBoundByAccessibilityElement.count, 3, "Should show all 3 seeded notes")
    }

    func testQuickOpenSearchFilters() {
        openQuickOpen()

        let searchField = app.textFields["quickOpenSearchField"]
        searchField.tap()
        searchField.typeText("Vendor")

        // Wait for filtering
        Thread.sleep(forTimeInterval: 1)

        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'quickOpenRow_'"))
        let count = rows.allElementsBoundByAccessibilityElement.count
        XCTAssertLessThan(count, 3, "Filtering should reduce results, got: \(count)")
        XCTAssertGreaterThan(count, 0, "Should still have at least one matching result")
    }

    func testQuickOpenSelectNavigatesToNote() {
        openQuickOpen()

        let firstRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'quickOpenRow_'")).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.tap()

        // Sheet should dismiss
        let searchField = app.textFields["quickOpenSearchField"]
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: searchField,
        )
        XCTWaiter.wait(for: [dismissed], timeout: 5)

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
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: searchField,
        )
        let result = XCTWaiter.wait(for: [dismissed], timeout: 5)
        XCTAssertEqual(result, .completed, "Quick Open sheet should dismiss after close button tap")
    }
}
