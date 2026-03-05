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

    /// Select the first note in the sidebar.
    func selectFirstNote(in app: XCUIApplication) {
        let firstRow = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'noteRow_'"),
        ).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "At least one note row should exist")
        firstRow.tap()
    }

    /// Navigate to the Board tab and open the first kanban card's detail sheet.
    @discardableResult
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

    /// Find a single element by exact accessibility identifier.
    func element(
        in app: XCUIApplication,
        identifier: String,
        type: XCUIElement.ElementType = .any,
    ) -> XCUIElement {
        app.descendants(matching: type)
            .matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
    }

    /// Query elements matching an accessibility identifier prefix.
    func elements(
        in app: XCUIApplication,
        prefix: String,
        type: XCUIElement.ElementType = .any,
    ) -> XCUIElementQuery {
        app.descendants(matching: type)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }

    /// Wait for an element to disappear, returning the waiter result.
    @discardableResult
    func waitForDisappearance(
        of element: XCUIElement,
        timeout: TimeInterval = 5,
    ) -> XCTWaiter.Result {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element,
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout)
    }

    /// Wait for an arbitrary predicate to become true on an object.
    @discardableResult
    func waitForPredicate(
        _ format: String,
        object: Any,
        timeout: TimeInterval = 5,
    ) -> XCTWaiter.Result {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: format),
            object: object,
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout)
    }
}
