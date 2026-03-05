import XCTest

final class KanbanColumnEditorXCUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp()
        navigateToTab(app, "Board")
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    /// Open the column editor sheet.
    private func openColumnEditor() {
        let addButton = app.buttons["addColumnButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let sheet = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'kanbanColumnEditorSheet'")).firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Column editor sheet should appear")
    }

    // MARK: - Tests

    func testColumnEditorSheetAppears() {
        openColumnEditor()
        let sheet = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'kanbanColumnEditorSheet'")).firstMatch
        XCTAssertTrue(sheet.exists, "Column editor sheet should be visible")
    }

    func testColumnEditorTitleFieldExists() {
        openColumnEditor()
        let titleField = app.textFields["columnEditorTitle"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "Column editor title field should exist")
    }

    func testColumnEditorSaveDisabledWhenEmpty() {
        openColumnEditor()
        let saveButton = app.buttons["columnEditorSave"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        XCTAssertFalse(saveButton.isEnabled, "Save button should be disabled when title is empty")
    }

    func testColumnEditorSaveCreatesColumn() {
        let columnsBefore = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'kanbanColumn_'"))
            .allElementsBoundByAccessibilityElement.count

        openColumnEditor()

        let titleField = app.textFields["columnEditorTitle"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("XCUI Custom Column")

        let saveButton = app.buttons["columnEditorSave"]
        XCTAssertTrue(saveButton.isEnabled, "Save should be enabled after entering a title")
        saveButton.tap()

        // Wait for sheet to dismiss and column to appear
        Thread.sleep(forTimeInterval: 1)

        let columnsAfter = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'kanbanColumn_'"))
            .allElementsBoundByAccessibilityElement.count
        XCTAssertGreaterThan(columnsAfter, columnsBefore, "A new column should appear after saving")
    }

    func testColumnEditorCancelDismisses() {
        openColumnEditor()

        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5))
        cancelButton.tap()

        let sheet = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'kanbanColumnEditorSheet'")).firstMatch
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: sheet,
        )
        let result = XCTWaiter.wait(for: [dismissed], timeout: 5)
        XCTAssertEqual(result, .completed, "Column editor sheet should dismiss after cancel")
    }
}
