import XCTest

final class NotesSearchXCUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Search

    func testSearchFieldAcceptsText() {
        let searchField = app.textFields["noteSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Launch")

        let value = searchField.value as? String ?? ""
        XCTAssertTrue(value.contains("Launch"), "Search field should contain 'Launch', got: '\(value)'")
    }

    func testSearchFiltersList() {
        // Verify initial count
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'noteRow_'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        let initialCount = rows.allElementsBoundByAccessibilityElement.count
        XCTAssertEqual(initialCount, 3, "Should start with 3 notes")

        // Search for a specific note
        let searchField = app.textFields["noteSearchField"]
        searchField.tap()
        searchField.typeText("Vendor")

        // Wait for filter to apply
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count < %d", initialCount),
            object: rows,
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: 5)
        XCTAssertEqual(result, .completed, "Search should filter the note list")
    }

    func testSearchClearRestoresList() {
        let searchField = app.textFields["noteSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Vendor")

        // Wait for filtering
        Thread.sleep(forTimeInterval: 1)

        // Clear the search
        searchField.tap()
        // Select all and delete
        searchField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))

        // Wait for list to restore
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'noteRow_'"))
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count >= 3"),
            object: rows,
        )
        let result = XCTWaiter.wait(for: [restored], timeout: 5)
        XCTAssertEqual(result, .completed, "All 3 notes should reappear after clearing search")
    }

    func testSearchShowsSnippets() {
        let searchField = app.textFields["noteSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Launch")

        // Wait for search results
        Thread.sleep(forTimeInterval: 1)

        let snippets = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'noteSnippet_'"))
        XCTAssertTrue(snippets.firstMatch.waitForExistence(timeout: 5), "Search should produce snippet elements")
    }

    func testSearchNoResultsShowsEmpty() {
        let searchField = app.textFields["noteSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("zzzzzzzzzznonexistent")

        // Wait for filter
        Thread.sleep(forTimeInterval: 1)

        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'noteRow_'"))
        let count = rows.allElementsBoundByAccessibilityElement.count
        XCTAssertEqual(count, 0, "No note rows should match nonsense search, got: \(count)")
    }
}
