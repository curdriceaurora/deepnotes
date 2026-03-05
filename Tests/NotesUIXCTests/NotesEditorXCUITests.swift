import XCTest

final class NotesEditorXCUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Text entry

    func testNoteBodyEditorAcceptsText() {
        selectFirstNote(in: app)

        let bodyEditor = app.textViews["noteBodyEditor"]
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 5), "Note body editor should appear after selecting a note")
        bodyEditor.tap()

        let testText = "XCUI test entry"
        bodyEditor.typeText(testText)

        let editorValue = bodyEditor.value as? String ?? ""
        XCTAssertTrue(editorValue.contains(testText), "Editor should contain typed text '\(testText)', got: '\(editorValue)'")
    }

    func testNoteTitleFieldAcceptsText() {
        selectFirstNote(in: app)

        let titleField = app.textFields["noteTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "Note title field should appear after selecting a note")
        titleField.tap()

        titleField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 50))
        let newTitle = "XCUI Title Test"
        titleField.typeText(newTitle)

        let fieldValue = titleField.value as? String ?? ""
        XCTAssertTrue(fieldValue.contains(newTitle), "Title field should contain '\(newTitle)', got: '\(fieldValue)'")
    }

    // MARK: - Save button

    func testSaveButtonExists() {
        selectFirstNote(in: app)
        let saveButton = app.buttons["saveNoteButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Save button should be visible after selecting a note")
    }

    func testSaveButtonTapDoesNotCrash() {
        selectFirstNote(in: app)

        let bodyEditor = app.textViews["noteBodyEditor"]
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 5))
        bodyEditor.tap()
        bodyEditor.typeText("Save test")

        let saveButton = app.buttons["saveNoteButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        let errorBanner = element(in: app, identifier: "globalErrorBanner")
        XCTAssertFalse(errorBanner.waitForExistence(timeout: 2), "No error banner should appear after save")
    }

    // MARK: - Preview toggle

    func testTogglePreviewShowsPreviewPane() {
        selectFirstNote(in: app)

        let toggleButton = app.buttons["togglePreviewButton"]
        XCTAssertTrue(toggleButton.waitForExistence(timeout: 5))
        toggleButton.tap()

        let preview = element(in: app, identifier: "noteBodyPreview")
        XCTAssertTrue(preview.waitForExistence(timeout: 5), "Preview pane should appear after toggle")

        let editor = app.textViews["noteBodyEditor"]
        XCTAssertFalse(editor.exists, "Editor should be hidden in preview mode")
    }

    func testTogglePreviewBackToEditMode() {
        selectFirstNote(in: app)

        let toggleButton = app.buttons["togglePreviewButton"]
        XCTAssertTrue(toggleButton.waitForExistence(timeout: 5))

        // Toggle to preview
        toggleButton.tap()
        let preview = element(in: app, identifier: "noteBodyPreview")
        XCTAssertTrue(preview.waitForExistence(timeout: 5))

        // Toggle back to edit
        toggleButton.tap()
        let editor = app.textViews["noteBodyEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "Editor should reappear after toggling back")
    }

    // MARK: - Markdown toolbar

    func testMarkdownToolbarVisibleInEditMode() {
        selectFirstNote(in: app)

        for id in ["insertHeadingButton", "insertBulletButton", "insertCheckboxButton"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(id) should be visible in edit mode")
        }
    }

    func testMarkdownToolbarHiddenInPreviewMode() {
        selectFirstNote(in: app)

        let toggleButton = app.buttons["togglePreviewButton"]
        XCTAssertTrue(toggleButton.waitForExistence(timeout: 5))
        toggleButton.tap()

        let preview = element(in: app, identifier: "noteBodyPreview")
        XCTAssertTrue(preview.waitForExistence(timeout: 5))

        for id in ["insertHeadingButton", "insertBulletButton", "insertCheckboxButton"] {
            let button = app.buttons[id]
            XCTAssertFalse(button.exists, "\(id) should be hidden in preview mode")
        }
    }

    func testInsertHeadingButtonAddsText() {
        selectFirstNote(in: app)

        let bodyEditor = app.textViews["noteBodyEditor"]
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 5))
        bodyEditor.tap()
        bodyEditor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 200))

        app.buttons["insertHeadingButton"].tap()

        let value = bodyEditor.value as? String ?? ""
        XCTAssertTrue(value.contains("#"), "Body should contain '#' after heading insert, got: '\(value)'")
    }

    func testInsertBulletButtonAddsText() {
        selectFirstNote(in: app)

        let bodyEditor = app.textViews["noteBodyEditor"]
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 5))
        bodyEditor.tap()
        bodyEditor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 200))

        app.buttons["insertBulletButton"].tap()

        let value = bodyEditor.value as? String ?? ""
        XCTAssertTrue(value.contains("- "), "Body should contain '- ' after bullet insert, got: '\(value)'")
    }

    func testInsertCheckboxButtonAddsText() {
        selectFirstNote(in: app)

        let bodyEditor = app.textViews["noteBodyEditor"]
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 5))
        bodyEditor.tap()
        bodyEditor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 200))

        app.buttons["insertCheckboxButton"].tap()

        let value = bodyEditor.value as? String ?? ""
        XCTAssertTrue(value.contains("- [ ]"), "Body should contain '- [ ]' after checkbox insert, got: '\(value)'")
    }

    // MARK: - New note / Daily note buttons

    func testNewNoteButtonExists() {
        let newNoteButton = app.buttons["newNoteButton"]
        XCTAssertTrue(newNoteButton.waitForExistence(timeout: 5), "New note button should be visible")
    }

    func testNewNoteButtonCreatesNote() {
        let newNoteButton = app.buttons["newNoteButton"]
        XCTAssertTrue(newNoteButton.waitForExistence(timeout: 5))

        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'noteRow_'"))
        let initialCount = rows.allElementsBoundByAccessibilityElement.count

        newNoteButton.tap()

        // Should show template picker sheet or create a new note row
        let templatePicker = app.staticTexts["New Note"]
        let appeared = templatePicker.waitForExistence(timeout: 5)
            || rows.allElementsBoundByAccessibilityElement.count > initialCount
        XCTAssertTrue(appeared, "Template picker or new note should appear after tapping new note button")
    }

    func testDailyNoteButtonExists() {
        let dailyButton = app.buttons["dailyNoteButton"]
        XCTAssertTrue(dailyButton.waitForExistence(timeout: 5), "Daily note button should be visible")
    }

    func testDailyNoteButtonCreatesOrNavigates() {
        let dailyButton = app.buttons["dailyNoteButton"]
        XCTAssertTrue(dailyButton.waitForExistence(timeout: 5))
        dailyButton.tap()

        // Wait for a note to be selected (title field populated)
        let titleField = app.textFields["noteTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "Title field should appear after daily note action")

        let titleValue = titleField.value as? String ?? ""
        XCTAssertFalse(titleValue.isEmpty, "Daily note should have a non-empty title")
    }
}
