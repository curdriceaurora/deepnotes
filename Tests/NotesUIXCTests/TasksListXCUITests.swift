import XCTest

final class TasksListXCUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp()
        navigateToTab(app, "Tasks")
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Task list basics

    func testTasksTabShowsSeededTasks() {
        let list = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'tasksList'")).firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5), "Tasks list should appear")

        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'taskRow_'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), "Task rows should exist")
        XCTAssertEqual(rows.allElementsBoundByAccessibilityElement.count, 3, "Should have 3 seeded tasks")
    }

    func testTaskFilterPickerExists() {
        let picker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'taskFilterPicker'")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Task filter picker should exist")
    }

    func testTaskFilterAllShowsAllTasks() {
        // "All" is the default filter — verify all 3 tasks show
        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'taskRow_'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.allElementsBoundByAccessibilityElement.count, 3, "All filter should show 3 tasks")
    }

    func testTaskFilterCompletedShowsEmpty() {
        // Tap the "Completed" segment
        let completedButton = app.buttons["Completed"]
        if completedButton.waitForExistence(timeout: 3) {
            completedButton.tap()
        } else {
            // Try as static text in segmented control
            let completedText = app.staticTexts["Completed"]
            if completedText.waitForExistence(timeout: 3) {
                completedText.tap()
            }
        }

        // Wait a moment for filter to apply
        Thread.sleep(forTimeInterval: 1)

        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'taskRow_'"))
        let count = rows.allElementsBoundByAccessibilityElement.count
        XCTAssertEqual(count, 0, "Completed filter should show 0 tasks (none are completed), got: \(count)")
    }

    // MARK: - Sort & multi-select

    func testTaskSortMenuExists() {
        let menu = app.buttons["taskSortMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "Task sort menu should exist")
    }

    func testMultiSelectToggleButtonExists() {
        let button = app.buttons["multiSelectToggleButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Multi-select toggle button should exist")
    }

    func testMultiSelectModeShowsBulkBar() {
        let toggleButton = app.buttons["multiSelectToggleButton"]
        XCTAssertTrue(toggleButton.waitForExistence(timeout: 5))
        toggleButton.tap()

        let bulkMenu = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'bulkMoveMenu'")).firstMatch
        XCTAssertTrue(bulkMenu.waitForExistence(timeout: 5), "Bulk move menu should appear in multi-select mode")
    }

    func testMultiSelectToggleOff() {
        let toggleButton = app.buttons["multiSelectToggleButton"]
        XCTAssertTrue(toggleButton.waitForExistence(timeout: 5))

        // Toggle on
        toggleButton.tap()
        let bulkMenu = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'bulkMoveMenu'")).firstMatch
        XCTAssertTrue(bulkMenu.waitForExistence(timeout: 5))

        // Toggle off
        toggleButton.tap()
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertFalse(bulkMenu.exists, "Bulk move menu should disappear after toggling off multi-select")
    }

    // MARK: - Task interactions

    func testTaskCompletionToggle() {
        let firstRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'taskRow_'")).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))

        // Find the completion circle button (first button inside the task row)
        let circleButton = firstRow.buttons.firstMatch
        XCTAssertTrue(circleButton.exists, "Completion toggle button should exist on task row")
        circleButton.tap()

        // The task should still exist (toggling completion doesn't remove it from All view)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "Task row should remain visible after completion toggle")
    }

    func testTaskDeletionRemovesRow() {
        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'taskRow_'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        let initialCount = rows.allElementsBoundByAccessibilityElement.count

        // Find and tap a delete button
        let deleteButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'deleteTask_'")).firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5), "Delete button should exist")
        deleteButton.tap()

        // Wait for row count to change
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count < %d", initialCount),
            object: app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'taskRow_'")),
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: 5)
        XCTAssertEqual(result, .completed, "Task count should decrease after deletion")
    }
}
