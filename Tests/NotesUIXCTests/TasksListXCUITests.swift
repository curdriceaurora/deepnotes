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
        let list = element(in: app, identifier: "tasksList")
        XCTAssertTrue(list.waitForExistence(timeout: 5), "Tasks list should appear")

        let rows = elements(in: app, prefix: "taskRow_")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), "Task rows should exist")
        XCTAssertEqual(rows.allElementsBoundByAccessibilityElement.count, 3, "Should have 3 seeded tasks")
    }

    func testTaskFilterPickerExists() {
        let picker = element(in: app, identifier: "taskFilterPicker")
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Task filter picker should exist")
    }

    func testTaskFilterAllShowsAllTasks() {
        let rows = elements(in: app, prefix: "taskRow_")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.allElementsBoundByAccessibilityElement.count, 3, "All filter should show 3 tasks")
    }

    func testTaskFilterCompletedShowsEmpty() {
        // Tap the "Completed" segment in the filter picker
        let completedButton = app.buttons["Completed"]
        let completedText = app.staticTexts["Completed"]
        let tapped: Bool
        if completedButton.waitForExistence(timeout: 3) {
            completedButton.tap()
            tapped = true
        } else if completedText.waitForExistence(timeout: 3) {
            completedText.tap()
            tapped = true
        } else {
            tapped = false
        }
        XCTAssertTrue(tapped, "Should find 'Completed' filter segment to tap")

        let rows = elements(in: app, prefix: "taskRow_")
        let result = waitForPredicate("count == 0", object: rows)
        XCTAssertEqual(result, .completed, "Completed filter should show 0 tasks (none are completed)")
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

        let bulkMenu = element(in: app, identifier: "bulkMoveMenu")
        XCTAssertTrue(bulkMenu.waitForExistence(timeout: 5), "Bulk move menu should appear in multi-select mode")
    }

    func testMultiSelectToggleOff() {
        let toggleButton = app.buttons["multiSelectToggleButton"]
        XCTAssertTrue(toggleButton.waitForExistence(timeout: 5))

        // Toggle on
        toggleButton.tap()
        let bulkMenu = element(in: app, identifier: "bulkMoveMenu")
        XCTAssertTrue(bulkMenu.waitForExistence(timeout: 5))

        // Toggle off
        toggleButton.tap()
        let result = waitForDisappearance(of: bulkMenu)
        XCTAssertEqual(result, .completed, "Bulk move menu should disappear after toggling off multi-select")
    }

    // MARK: - Task interactions

    func testTaskCompletionToggle() {
        let firstRow = elements(in: app, prefix: "taskRow_").firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))

        let circleButton = firstRow.buttons.firstMatch
        XCTAssertTrue(circleButton.exists, "Completion toggle button should exist on task row")
        circleButton.tap()

        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "Task row should remain visible after completion toggle")
    }

    func testTaskDeletionRemovesRow() {
        let rows = elements(in: app, prefix: "taskRow_")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        let initialCount = rows.allElementsBoundByAccessibilityElement.count

        let deleteButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'deleteTask_'"),
        ).firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5), "Delete button should exist")
        deleteButton.tap()

        let result = waitForPredicate("count < \(initialCount)", object: rows)
        XCTAssertEqual(result, .completed, "Task count should decrease after deletion")
    }
}
