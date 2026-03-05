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
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'noteRow_'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        let initialCount = rows.allElementsBoundByAccessibilityElement.count
        XCTAssertEqual(initialCount, 3, "Should start with 3 notes")

        let searchField = app.textFields["noteSearchField"]
        searchField.tap()
        searchField.typeText("Vendor")

        let result = waitForPredicate("count < \(initialCount)", object: rows)
        XCTAssertEqual(result, .completed, "Search should filter the note list")
    }

    func testSearchClearRestoresList() {
        let searchField = app.textFields["noteSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Vendor")

        // Wait for filtering to take effect
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'noteRow_'"))
        waitForPredicate("count < 3", object: rows)

        // Clear the search
        searchField.tap()
        searchField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))

        let result = waitForPredicate("count >= 3", object: rows)
        XCTAssertEqual(result, .completed, "All 3 notes should reappear after clearing search")
    }

    func testSearchShowsSnippets() {
        let searchField = app.textFields["noteSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Launch")

        let snippets = elements(in: app, prefix: "noteSnippet_")
        XCTAssertTrue(snippets.firstMatch.waitForExistence(timeout: 5), "Search should produce snippet elements")
    }

    func testSearchNoResultsShowsEmpty() {
        let searchField = app.textFields["noteSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("zzzzzzzzzznonexistent")

        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'noteRow_'"))
        let result = waitForPredicate("count == 0", object: rows)
        XCTAssertEqual(result, .completed, "No note rows should match nonsense search")
    }
}
