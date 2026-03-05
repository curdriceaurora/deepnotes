import XCTest

final class CrossTabNavigationXCUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Cross-tab state

    func testNoteSelectionPersistsAcrossTabSwitch() {
        // Select a specific note
        selectNote(in: app, titled: "Q2 Launch Plan")

        let titleField = app.textFields["noteTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        let selectedTitle = titleField.value as? String ?? ""
        XCTAssertTrue(selectedTitle.contains("Q2 Launch Plan"), "Should select Q2 Launch Plan")

        // Switch to Tasks and back
        navigateToTab(app, "Tasks")
        Thread.sleep(forTimeInterval: 0.5)
        navigateToTab(app, "Notes")

        // Verify same note is still selected
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        let restoredTitle = titleField.value as? String ?? ""
        XCTAssertEqual(selectedTitle, restoredTitle, "Note selection should persist across tab switch")
    }

    func testCreateTaskFromNoteThenVerifyOnBoard() {
        // Select a note and create a quick task
        selectNote(in: app, titled: "Q2 Launch Plan")

        let field = app.textFields["quickTaskField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let uniqueTask = "CrossTab-\(Int.random(in: 1000 ... 9999))"
        field.typeText(uniqueTask)

        let addButton = app.buttons["quickTaskButton"]
        addButton.tap()
        Thread.sleep(forTimeInterval: 1)

        // Switch to Board and verify the new card exists
        navigateToTab(app, "Board")

        let cards = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'kanbanCard_'"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))

        // Find the card with the unique title
        let matchingCard = cards.allElementsBoundByAccessibilityElement.first { card in
            card.staticTexts[uniqueTask].exists
        }
        XCTAssertNotNil(matchingCard, "New task '\(uniqueTask)' should appear as a card on the Board")
    }

    func testKanbanMoveReflectsInTasksList() {
        navigateToTab(app, "Board")

        // Find a move-right button and move a card
        let moveRight = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'moveRight_'")).firstMatch
        XCTAssertTrue(moveRight.waitForExistence(timeout: 5))
        let taskID = String(moveRight.identifier.dropFirst("moveRight_".count))
        moveRight.tap()

        Thread.sleep(forTimeInterval: 1)

        // Switch to Tasks tab — task should still be visible
        navigateToTab(app, "Tasks")
        let taskRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "taskRow_\(taskID)")).firstMatch
        XCTAssertTrue(taskRow.waitForExistence(timeout: 5), "Moved task should still appear in Tasks list")
    }

    func testTabSwitchingRapidly() {
        let tabs = ["Notes", "Tasks", "Board", "Graph", "Sync"]
        for tab in tabs {
            navigateToTab(app, tab)
        }
        // Reverse
        for tab in tabs.reversed() {
            navigateToTab(app, tab)
        }

        // App should still be responsive
        let searchField = app.textFields["noteSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "App should remain responsive after rapid tab switching")
    }
}
