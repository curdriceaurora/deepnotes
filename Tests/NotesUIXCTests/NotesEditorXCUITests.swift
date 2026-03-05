import XCTest

final class NotesEditorXCUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        // Wait for app to load and seed demo data
        let notesList = app.outlines.firstMatch
        XCTAssertTrue(notesList.waitForExistence(timeout: 10), "Notes list should appear after launch")
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testNoteBodyEditorAcceptsText() {
        // Tap the first note row to select it
        let firstNoteRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'noteRow_'")).firstMatch
        XCTAssertTrue(firstNoteRow.waitForExistence(timeout: 5), "At least one note row should exist")
        firstNoteRow.tap()

        // Tap the body editor
        let bodyEditor = app.textViews["noteBodyEditor"]
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 5), "Note body editor should appear after selecting a note")
        bodyEditor.tap()

        // Type text
        let testText = "XCUI test entry"
        bodyEditor.typeText(testText)

        // Verify the typed text appears in the editor
        let editorValue = bodyEditor.value as? String ?? ""
        XCTAssertTrue(editorValue.contains(testText), "Editor should contain typed text '\(testText)', got: '\(editorValue)'")
    }

    func testNoteTitleFieldAcceptsText() {
        // Tap the first note row
        let firstNoteRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'noteRow_'")).firstMatch
        XCTAssertTrue(firstNoteRow.waitForExistence(timeout: 5), "At least one note row should exist")
        firstNoteRow.tap()

        // Tap the title field
        let titleField = app.textFields["noteTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "Note title field should appear after selecting a note")
        titleField.tap()

        // Select all and type new title
        titleField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 50))
        let newTitle = "XCUI Title Test"
        titleField.typeText(newTitle)

        let fieldValue = titleField.value as? String ?? ""
        XCTAssertTrue(fieldValue.contains(newTitle), "Title field should contain '\(newTitle)', got: '\(fieldValue)'")
    }
}
