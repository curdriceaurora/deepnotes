import XCTest

final class QuickTaskXCUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp()
        // Select a note so the quick task bar is visible
        let firstRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'noteRow_'")).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.tap()
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
        let picker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'quickTaskPriorityPicker'")).firstMatch
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
        let cleared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == '' OR value == nil OR value == 'Quick task…'"),
            object: field,
        )
        let result = XCTWaiter.wait(for: [cleared], timeout: 5)
        XCTAssertEqual(result, .completed, "Quick task field should clear after task creation")
    }

    func testQuickTaskAppearsInTasksTab() {
        // Get initial task count on Tasks tab
        navigateToTab(app, "Tasks")
        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'taskRow_'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        let initialCount = rows.allElementsBoundByAccessibilityElement.count

        // Switch back to Notes and create a quick task
        navigateToTab(app, "Notes")
        let firstRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'noteRow_'")).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.tap()

        let field = app.textFields["quickTaskField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("New Quick Task XCUI")

        let button = app.buttons["quickTaskButton"]
        button.tap()

        // Wait for task creation
        Thread.sleep(forTimeInterval: 1)

        // Switch to Tasks tab and verify count increased
        navigateToTab(app, "Tasks")
        let updatedRows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'taskRow_'"))
        let increased = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count > %d", initialCount),
            object: updatedRows,
        )
        let result = XCTWaiter.wait(for: [increased], timeout: 5)
        XCTAssertEqual(result, .completed, "Task count should increase after creating a quick task")
    }
}
