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

    /// Select a note and expand its Backlinks disclosure group.
    private func expandBacklinks(for noteName: String) {
        selectNote(in: app, titled: noteName)
        let backlinksLabel = app.staticTexts["Backlinks"]
        XCTAssertTrue(backlinksLabel.waitForExistence(timeout: 5), "Backlinks section label should exist")
        backlinksLabel.tap()
    }

    // MARK: - Backlinks

    func testBacklinksSectionExists() {
        selectNote(in: app, titled: "Q2 Launch Plan")
        let backlinksLabel = app.staticTexts["Backlinks"]
        XCTAssertTrue(backlinksLabel.waitForExistence(timeout: 5), "Backlinks section label should exist")
    }

    func testBacklinksShowsLinkedNote() {
        expandBacklinks(for: "Q2 Launch Plan")

        let backlinkRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'backlinkRow_'")).firstMatch
        XCTAssertTrue(backlinkRow.waitForExistence(timeout: 5), "A backlink row should appear for linked note")
    }

    func testBacklinkNavigatesToSourceNote() {
        expandBacklinks(for: "Q2 Launch Plan")

        let backlinkRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'backlinkRow_'")).firstMatch
        XCTAssertTrue(backlinkRow.waitForExistence(timeout: 5))
        backlinkRow.tap()

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
        expandBacklinks(for: "Launch review card")

        let emptyState = element(in: app, identifier: "backlinksEmptyState")
        XCTAssertTrue(emptyState.waitForExistence(timeout: 5), "Empty backlinks state should appear for unlinked note")
    }
}
