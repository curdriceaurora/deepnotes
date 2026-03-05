import XCTest

final class NotesNavigationXCUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Tab existence

    func testAllFiveTabsExist() {
        for name in ["Notes", "Tasks", "Board", "Graph", "Sync"] {
            XCTAssertTrue(
                app.radioButtons[name].waitForExistence(timeout: 3),
                "Tab '\(name)' should exist",
            )
        }
    }

    func testDefaultTabIsNotes() {
        let searchField = app.textFields["noteSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Note search field should be visible on launch (Notes tab)")
    }

    // MARK: - Tab switching

    func testSwitchToTasksTab() {
        navigateToTab(app, "Tasks")

        let picker = element(in: app, identifier: "taskFilterPicker")
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Task filter picker should appear on Tasks tab")

        let list = element(in: app, identifier: "tasksList")
        XCTAssertTrue(list.exists, "Tasks list should appear on Tasks tab")
    }

    func testSwitchToBoardTab() {
        navigateToTab(app, "Board")

        let column = elements(in: app, prefix: "kanbanColumn_").firstMatch
        XCTAssertTrue(column.waitForExistence(timeout: 5), "At least one kanban column should appear on Board tab")
    }

    func testSwitchToGraphTab() {
        navigateToTab(app, "Graph")

        let title = app.staticTexts["Knowledge Graph"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Graph view title should appear on Graph tab")
    }

    func testSwitchToSyncTab() {
        navigateToTab(app, "Sync")

        let calField = app.textFields["syncCalendarField"]
        XCTAssertTrue(calField.waitForExistence(timeout: 5), "Sync calendar field should appear on Sync tab")

        let syncButton = app.buttons["runSyncButton"]
        XCTAssertTrue(syncButton.exists, "Run sync button should appear on Sync tab")
    }

    // MARK: - Note list

    func testNoteListShowsThreeSeededNotes() {
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'noteRow_'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), "At least one note row should exist")
        XCTAssertEqual(rows.allElementsBoundByAccessibilityElement.count, 3, "Should have 3 seeded notes")
    }

    func testSelectNoteShowsEditor() {
        selectFirstNote(in: app)

        let titleField = app.textFields["noteTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "Note title field should appear after selecting a note")

        let bodyEditor = app.textViews["noteBodyEditor"]
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 5), "Note body editor should appear after selecting a note")
    }

    func testSelectDifferentNoteChangesEditor() {
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'noteRow_'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))

        let allRows = rows.allElementsBoundByAccessibilityElement
        guard allRows.count >= 2 else {
            XCTFail("Need at least 2 notes to test switching")
            return
        }

        allRows[0].tap()
        let titleField = app.textFields["noteTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        let firstTitle = titleField.value as? String ?? ""

        allRows[1].tap()
        let result = waitForPredicate("value != %@", firstTitle, object: titleField)
        XCTAssertEqual(result, .completed, "Title should change when selecting a different note")
    }

    func testNoteSearchFieldExists() {
        let searchField = app.textFields["noteSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Note search field should be visible")
    }
}
