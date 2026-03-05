import XCTest

final class QuickTaskXCUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp()
        // Select a note so the quick task bar is visible
        selectFirstNote(in: app)
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Quick task elements

    func testQuickTaskFieldExists() {
        let field = app.textFields["quickTaskField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Quick task field should be visible")
    }

    func testQuickTaskButtonExists() {
        let button = app.buttons["quickTaskButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Quick task button should be visible")
    }

    func testQuickTaskPriorityPickerExists() {
        let picker = element(in: app, identifier: "quickTaskPriorityPicker")
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Quick task priority picker should be visible")
    }

    // MARK: - Quick task creation

    func testCreateQuickTask() {
        let field = app.textFields["quickTaskField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Quick XCUI Task")

        let button = app.buttons["quickTaskButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()

        // Field should clear after creation
        let result = waitForPredicate(
            "value == '' OR value == nil OR value == 'Quick task…'",
            object: field,
        )
        XCTAssertEqual(result, .completed, "Quick task field should clear after task creation")
    }

    func testQuickTaskAppearsInTasksTab() {
        // Get initial task count on Tasks tab
        navigateToTab(app, "Tasks")
        let rows = elements(in: app, prefix: "taskRow_")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        let initialCount = rows.allElementsBoundByAccessibilityElement.count

        // Switch back to Notes and create a quick task
        navigateToTab(app, "Notes")
        selectFirstNote(in: app)

        let field = app.textFields["quickTaskField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("New Quick Task XCUI")

        app.buttons["quickTaskButton"].tap()

        // Switch to Tasks tab and verify count increased
        navigateToTab(app, "Tasks")
        let updatedRows = elements(in: app, prefix: "taskRow_")
        let result = waitForPredicate("count > \(initialCount)", object: updatedRows)
        XCTAssertEqual(result, .completed, "Task count should increase after creating a quick task")
    }
}
