import XCTest

final class BacklinksXCUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Backlinks

    func testBacklinksSectionExists() {
        // "Vendor Call Notes" links to "Q2 Launch Plan", so Q2 should have a backlink
        selectNote(in: app, titled: "Q2 Launch Plan")

        let backlinksLabel = app.staticTexts["Backlinks"]
        XCTAssertTrue(backlinksLabel.waitForExistence(timeout: 5), "Backlinks section label should exist")
    }

    func testBacklinksShowsLinkedNote() {
        selectNote(in: app, titled: "Q2 Launch Plan")

        // Expand the Backlinks disclosure group by tapping its label
        let backlinksLabel = app.staticTexts["Backlinks"]
        XCTAssertTrue(backlinksLabel.waitForExistence(timeout: 5))
        backlinksLabel.tap()

        let backlinkRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'backlinkRow_'")).firstMatch
        XCTAssertTrue(backlinkRow.waitForExistence(timeout: 5), "A backlink row should appear for linked note")
    }

    func testBacklinkNavigatesToSourceNote() {
        selectNote(in: app, titled: "Q2 Launch Plan")

        let backlinksLabel = app.staticTexts["Backlinks"]
        XCTAssertTrue(backlinksLabel.waitForExistence(timeout: 5))
        backlinksLabel.tap()

        let backlinkRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'backlinkRow_'")).firstMatch
        XCTAssertTrue(backlinkRow.waitForExistence(timeout: 5))
        backlinkRow.tap()

        // The title field should now show a different note
        let titleField = app.textFields["noteTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        let value = titleField.value as? String ?? ""
        XCTAssertFalse(value.isEmpty, "Title should be populated after navigating via backlink")
    }

    func testUnlinkedMentionsSectionExists() {
        selectNote(in: app, titled: "Q2 Launch Plan")

        let mentionsLabel = app.staticTexts["Unlinked Mentions"]
        XCTAssertTrue(mentionsLabel.waitForExistence(timeout: 5), "Unlinked Mentions section label should exist")
    }

    func testEmptyBacklinksShowsEmptyState() {
        // "Launch review card" has no wikilinks pointing to it
        selectNote(in: app, titled: "Launch review card")

        // Expand backlinks
        let backlinksLabel = app.staticTexts["Backlinks"]
        XCTAssertTrue(backlinksLabel.waitForExistence(timeout: 5))
        backlinksLabel.tap()

        let emptyState = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'backlinksEmptyState'")).firstMatch
        XCTAssertTrue(emptyState.waitForExistence(timeout: 5), "Empty backlinks state should appear for unlinked note")
    }
}
