import XCTest

extension XCTestCase {
    /// Launch the XCUIHost app with `--ui-testing` and wait for seeded data to load.
    func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let notesList = app.outlines.firstMatch
        XCTAssertTrue(notesList.waitForExistence(timeout: 10), "Notes list should appear after launch")
        return app
    }

    /// Tap a top-level tab by name. macOS TabView items are `radioButtons`.
    func navigateToTab(_ app: XCUIApplication, _ name: String) {
        let tab = app.radioButtons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Tab '\(name)' should exist")
        tab.tap()
    }

    /// Select a note in the sidebar by matching its title text inside `noteRow_` buttons.
    func selectNote(in app: XCUIApplication, titled: String) {
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'noteRow_'"))
        let matchingRow = rows.allElementsBoundByAccessibilityElement.first { row in
            row.staticTexts[titled].exists
        }
        XCTAssertNotNil(matchingRow, "Note titled '\(titled)' should exist in the list")
        matchingRow?.tap()
    }

    /// Navigate to the Board tab and open the first kanban card's detail sheet.
    func openFirstKanbanCard(in app: XCUIApplication) -> XCUIElement {
        navigateToTab(app, "Board")

        let firstCard = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'kanbanCard_'")).firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5), "At least one kanban card should exist")
        firstCard.tap()

        let detailSheet = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'kanbanCardDetailSheet'")).firstMatch
        XCTAssertTrue(detailSheet.waitForExistence(timeout: 5), "Card detail sheet should appear")
        return detailSheet
    }

    /// Count elements matching a predicate-based identifier prefix.
    func elementCount(_ app: XCUIApplication, matching type: XCUIElement.ElementType = .any, prefix: String) -> Int {
        app.descendants(matching: type)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            .allElementsBoundByAccessibilityElement.count
    }
}
