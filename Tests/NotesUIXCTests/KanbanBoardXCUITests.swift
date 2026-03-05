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
        let columns = elements(in: app, prefix: "kanbanColumn_")
        XCTAssertTrue(columns.firstMatch.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(
            columns.allElementsBoundByAccessibilityElement.count, 2,
            "Board should have multiple columns",
        )
    }

    func testKanbanColumnBacklogExists() {
        let column = element(in: app, identifier: "kanbanColumn_backlog")
        XCTAssertTrue(column.waitForExistence(timeout: 5), "Backlog column should exist")
    }

    func testKanbanColumnNextExists() {
        let column = element(in: app, identifier: "kanbanColumn_next")
        XCTAssertTrue(column.waitForExistence(timeout: 5), "Next column should exist")
    }

    func testKanbanColumnDoingExists() {
        let column = element(in: app, identifier: "kanbanColumn_doing")
        XCTAssertTrue(column.waitForExistence(timeout: 5), "Doing column should exist")
    }

    func testKanbanColumnWaitingExists() {
        let column = element(in: app, identifier: "kanbanColumn_waiting")
        XCTAssertTrue(column.waitForExistence(timeout: 5), "Waiting column should exist")
    }

    func testKanbanColumnDoneExists() {
        let column = element(in: app, identifier: "kanbanColumn_done")
        XCTAssertTrue(column.waitForExistence(timeout: 5), "Done column should exist")
    }

    // MARK: - Cards

    func testKanbanCardsExist() {
        let cards = elements(in: app, prefix: "kanbanCard_")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(
            cards.allElementsBoundByAccessibilityElement.count, 3,
            "Should have at least 3 seeded task cards",
        )
    }

    func testKanbanCardShowsPriorityBadge() {
        let badges = elements(in: app, prefix: "priorityBadge_")
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
        let moveRight = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'moveRight_'")).firstMatch
        XCTAssertTrue(moveRight.waitForExistence(timeout: 5))

        let taskID = String(moveRight.identifier.dropFirst("moveRight_".count))
        moveRight.tap()

        let movedCard = element(in: app, identifier: "kanbanCard_\(taskID)")
        XCTAssertTrue(movedCard.waitForExistence(timeout: 5), "Card should still exist after moving right")
    }

    func testMoveLeftMovesCard() {
        let moveLeft = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'moveLeft_'")).firstMatch
        XCTAssertTrue(moveLeft.waitForExistence(timeout: 5))

        let taskID = String(moveLeft.identifier.dropFirst("moveLeft_".count))
        moveLeft.tap()

        let movedCard = element(in: app, identifier: "kanbanCard_\(taskID)")
        XCTAssertTrue(movedCard.waitForExistence(timeout: 5), "Card should still exist after moving left")
    }

    // MARK: - Delete card

    func testDeleteKanbanTaskButton() {
        let cards = elements(in: app, prefix: "kanbanCard_")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
        let initialCount = cards.allElementsBoundByAccessibilityElement.count

        let deleteButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'deleteKanbanTask_'"),
        ).firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()

        let result = waitForPredicate("count < \(initialCount)", object: cards)
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

        let editorSheet = element(in: app, identifier: "kanbanColumnEditorSheet")
        XCTAssertTrue(editorSheet.waitForExistence(timeout: 5), "Column editor sheet should appear")
    }
}
