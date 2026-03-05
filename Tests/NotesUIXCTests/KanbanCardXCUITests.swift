import XCTest

final class KanbanCardXCUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        // Wait for app to load
        let notesList = app.outlines.firstMatch
        XCTAssertTrue(notesList.waitForExistence(timeout: 10), "App should launch and load data")
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    /// Navigate to the Board tab and open the first kanban card's detail sheet.
    private func openFirstKanbanCard() throws -> XCUIElement {
        // Tap the Board tab (rendered as a radio button on macOS)
        let boardTab = app.radioButtons["Board"]
        XCTAssertTrue(boardTab.waitForExistence(timeout: 5), "Board tab should exist")
        boardTab.tap()

        // Find and tap the first kanban card (rendered via onTapGesture, so query any element type)
        let firstCard = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'kanbanCard_'")).firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5), "At least one kanban card should exist")
        firstCard.tap()

        // Wait for the detail sheet to appear
        let detailSheet = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'kanbanCardDetailSheet'")).firstMatch
        XCTAssertTrue(detailSheet.waitForExistence(timeout: 5), "Card detail sheet should appear")
        return detailSheet
    }

    func testKanbanCardDetailAcceptsTitle() throws {
        _ = try openFirstKanbanCard()

        let titleField = app.textFields["cardDetailTitle"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "Card detail title field should exist")
        titleField.tap()

        // Clear existing text and type new title
        titleField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 50))
        let newTitle = "XCUI Card Title"
        titleField.typeText(newTitle)

        let fieldValue = titleField.value as? String ?? ""
        XCTAssertTrue(fieldValue.contains(newTitle), "Card title should contain '\(newTitle)', got: '\(fieldValue)'")
    }

    func testKanbanCardDetailAcceptsDetails() throws {
        _ = try openFirstKanbanCard()

        let detailsEditor = app.textViews["cardDetailDetails"]
        XCTAssertTrue(detailsEditor.waitForExistence(timeout: 5), "Card detail body editor should exist")
        detailsEditor.tap()

        let testText = "XCUI details entry"
        detailsEditor.typeText(testText)

        let editorValue = detailsEditor.value as? String ?? ""
        XCTAssertTrue(editorValue.contains(testText), "Details editor should contain '\(testText)', got: '\(editorValue)'")
    }
}
