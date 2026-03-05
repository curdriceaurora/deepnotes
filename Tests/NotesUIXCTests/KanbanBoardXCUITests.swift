import XCTest

final class KanbanBoardXCUITests: XCTestCase {
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

    // MARK: - Column existence

    func testKanbanBoardShowsColumns() {
        let columns = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'kanbanColumn_'"))
        XCTAssertTrue(columns.firstMatch.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(
            columns.allElementsBoundByAccessibilityElement.count, 2,
            "Board should have multiple columns",
        )
    }

    func testKanbanColumnBacklogExists() {
        let column = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'kanbanColumn_backlog'")).firstMatch
        XCTAssertTrue(column.waitForExistence(timeout: 5), "Backlog column should exist")
    }

    func testKanbanColumnNextExists() {
        let column = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'kanbanColumn_next'")).firstMatch
        XCTAssertTrue(column.waitForExistence(timeout: 5), "Next column should exist")
    }

    func testKanbanColumnDoingExists() {
        let column = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'kanbanColumn_doing'")).firstMatch
        XCTAssertTrue(column.waitForExistence(timeout: 5), "Doing column should exist")
    }

    func testKanbanColumnWaitingExists() {
        let column = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'kanbanColumn_waiting'")).firstMatch
        XCTAssertTrue(column.waitForExistence(timeout: 5), "Waiting column should exist")
    }

    func testKanbanColumnDoneExists() {
        let column = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'kanbanColumn_done'")).firstMatch
        XCTAssertTrue(column.waitForExistence(timeout: 5), "Done column should exist")
    }

    // MARK: - Cards

    func testKanbanCardsExist() {
        let cards = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'kanbanCard_'"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(
            cards.allElementsBoundByAccessibilityElement.count, 3,
            "Should have at least 3 seeded task cards",
        )
    }

    func testKanbanCardShowsPriorityBadge() {
        let badges = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'priorityBadge_'"))
        XCTAssertTrue(badges.firstMatch.waitForExistence(timeout: 5), "At least one priority badge should exist")
    }

    // MARK: - Move buttons

    func testMoveRightButtonExists() {
        let moveRight = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'moveRight_'")).firstMatch
        XCTAssertTrue(moveRight.waitForExistence(timeout: 5), "At least one moveRight button should exist")
    }

    func testMoveLeftButtonExists() {
        let moveLeft = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'moveLeft_'")).firstMatch
        XCTAssertTrue(moveLeft.waitForExistence(timeout: 5), "At least one moveLeft button should exist")
    }

    func testMoveRightMovesCard() {
        // Find a card in "next" column that can move right
        let moveRight = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'moveRight_'")).firstMatch
        XCTAssertTrue(moveRight.waitForExistence(timeout: 5))

        // Get the task ID from the identifier
        let identifier = moveRight.identifier
        let taskID = String(identifier.dropFirst("moveRight_".count))

        moveRight.tap()

        // Verify the card still exists (moved to next column, not deleted)
        let movedCard = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "kanbanCard_\(taskID)")).firstMatch
        XCTAssertTrue(movedCard.waitForExistence(timeout: 5), "Card should still exist after moving right")
    }

    func testMoveLeftMovesCard() {
        let moveLeft = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'moveLeft_'")).firstMatch
        XCTAssertTrue(moveLeft.waitForExistence(timeout: 5))

        let identifier = moveLeft.identifier
        let taskID = String(identifier.dropFirst("moveLeft_".count))

        moveLeft.tap()

        let movedCard = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "kanbanCard_\(taskID)")).firstMatch
        XCTAssertTrue(movedCard.waitForExistence(timeout: 5), "Card should still exist after moving left")
    }

    // MARK: - Delete card

    func testDeleteKanbanTaskButton() {
        let cards = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'kanbanCard_'"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
        let initialCount = cards.allElementsBoundByAccessibilityElement.count

        let deleteButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'deleteKanbanTask_'")).firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()

        // Wait for card count to decrease
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count < %d", initialCount),
            object: app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'kanbanCard_'")),
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: 5)
        XCTAssertEqual(result, .completed, "Card count should decrease after deletion")
    }

    // MARK: - Toolbar

    func testKanbanGroupingPickerExists() {
        let picker = app.buttons["kanbanGroupingPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Kanban grouping picker should exist")
    }

    func testAddColumnButtonOpensEditor() {
        let addButton = app.buttons["addColumnButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let editorSheet = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'kanbanColumnEditorSheet'")).firstMatch
        XCTAssertTrue(editorSheet.waitForExistence(timeout: 5), "Column editor sheet should appear")
    }
}
