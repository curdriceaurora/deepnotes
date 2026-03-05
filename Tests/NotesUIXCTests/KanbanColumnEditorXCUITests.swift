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

        let sheet = element(in: app, identifier: "kanbanColumnEditorSheet")
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Column editor sheet should appear")
    }

    // MARK: - Tests

    func testColumnEditorSheetAppears() {
        openColumnEditor()
        let titleField = app.textFields["columnEditorTitle"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "Column editor should contain a title field")
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
        let columnsBefore = elements(in: app, prefix: "kanbanColumn_")
        let beforeCount = columnsBefore.allElementsBoundByAccessibilityElement.count

        openColumnEditor()

        let titleField = app.textFields["columnEditorTitle"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("XCUI Custom Column")

        let saveButton = app.buttons["columnEditorSave"]
        XCTAssertTrue(saveButton.isEnabled, "Save should be enabled after entering a title")
        saveButton.tap()

        // Wait for new column to appear
        let columnsAfter = elements(in: app, prefix: "kanbanColumn_")
        let result = waitForPredicate("count > \(beforeCount)", object: columnsAfter)
        XCTAssertEqual(result, .completed, "A new column should appear after saving")
    }

    func testColumnEditorCancelDismisses() {
        openColumnEditor()

        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5))
        cancelButton.tap()

        let sheet = element(in: app, identifier: "kanbanColumnEditorSheet")
        let result = waitForDisappearance(of: sheet)
        XCTAssertEqual(result, .completed, "Column editor sheet should dismiss after cancel")
    }
}
