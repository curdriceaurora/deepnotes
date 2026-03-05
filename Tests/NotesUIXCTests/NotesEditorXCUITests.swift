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

    /// Select the first note so the editor panel is visible.
    private func selectFirstNote() {
        let firstRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'noteRow_'")).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "At least one note row should exist")
        firstRow.tap()
    }

    // MARK: - Text entry (existing tests, expanded)

    func testNoteBodyEditorAcceptsText() {
        selectFirstNote()

        let bodyEditor = app.textViews["noteBodyEditor"]
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 5), "Note body editor should appear after selecting a note")
        bodyEditor.tap()

        let testText = "XCUI test entry"
        bodyEditor.typeText(testText)

        let editorValue = bodyEditor.value as? String ?? ""
        XCTAssertTrue(editorValue.contains(testText), "Editor should contain typed text '\(testText)', got: '\(editorValue)'")
    }

    func testNoteTitleFieldAcceptsText() {
        selectFirstNote()

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
        selectFirstNote()
        let saveButton = app.buttons["saveNoteButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Save button should be visible after selecting a note")
    }

    func testSaveButtonTapDoesNotCrash() {
        selectFirstNote()

        let bodyEditor = app.textViews["noteBodyEditor"]
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 5))
        bodyEditor.tap()
        bodyEditor.typeText("Save test")

        let saveButton = app.buttons["saveNoteButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        // Verify no error banner appeared
        let errorBanner = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'globalErrorBanner'")).firstMatch
        XCTAssertFalse(errorBanner.exists, "No error banner should appear after save")
    }

    // MARK: - Preview toggle

    func testTogglePreviewShowsPreviewPane() {
        selectFirstNote()

        let toggleButton = app.buttons["togglePreviewButton"]
        XCTAssertTrue(toggleButton.waitForExistence(timeout: 5))
        toggleButton.tap()

        let preview = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'noteBodyPreview'")).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5), "Preview pane should appear after toggle")

        let editor = app.textViews["noteBodyEditor"]
        XCTAssertFalse(editor.exists, "Editor should be hidden in preview mode")
    }

    func testTogglePreviewBackToEditMode() {
        selectFirstNote()

        let toggleButton = app.buttons["togglePreviewButton"]
        XCTAssertTrue(toggleButton.waitForExistence(timeout: 5))

        // Toggle to preview
        toggleButton.tap()
        let preview = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'noteBodyPreview'")).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5))

        // Toggle back to edit
        toggleButton.tap()
        let editor = app.textViews["noteBodyEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "Editor should reappear after toggling back")
    }

    // MARK: - Markdown toolbar

    func testMarkdownToolbarVisibleInEditMode() {
        selectFirstNote()

        for id in ["insertHeadingButton", "insertBulletButton", "insertCheckboxButton"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(id) should be visible in edit mode")
        }
    }

    func testMarkdownToolbarHiddenInPreviewMode() {
        selectFirstNote()

        let toggleButton = app.buttons["togglePreviewButton"]
        XCTAssertTrue(toggleButton.waitForExistence(timeout: 5))
        toggleButton.tap()

        // Wait for preview to appear
        let preview = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'noteBodyPreview'")).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5))

        for id in ["insertHeadingButton", "insertBulletButton", "insertCheckboxButton"] {
            let button = app.buttons[id]
            XCTAssertFalse(button.exists, "\(id) should be hidden in preview mode")
        }
    }

    func testInsertHeadingButtonAddsText() {
        selectFirstNote()

        let bodyEditor = app.textViews["noteBodyEditor"]
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 5))
        bodyEditor.tap()

        // Clear existing text
        bodyEditor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 200))

        let headingButton = app.buttons["insertHeadingButton"]
        XCTAssertTrue(headingButton.waitForExistence(timeout: 5))
        headingButton.tap()

        let value = bodyEditor.value as? String ?? ""
        XCTAssertTrue(value.contains("#"), "Body should contain '#' after heading insert, got: '\(value)'")
    }

    func testInsertBulletButtonAddsText() {
        selectFirstNote()

        let bodyEditor = app.textViews["noteBodyEditor"]
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 5))
        bodyEditor.tap()

        bodyEditor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 200))

        let bulletButton = app.buttons["insertBulletButton"]
        XCTAssertTrue(bulletButton.waitForExistence(timeout: 5))
        bulletButton.tap()

        let value = bodyEditor.value as? String ?? ""
        XCTAssertTrue(value.contains("- "), "Body should contain '- ' after bullet insert, got: '\(value)'")
    }

    func testInsertCheckboxButtonAddsText() {
        selectFirstNote()

        let bodyEditor = app.textViews["noteBodyEditor"]
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 5))
        bodyEditor.tap()

        bodyEditor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 200))

        let checkboxButton = app.buttons["insertCheckboxButton"]
        XCTAssertTrue(checkboxButton.waitForExistence(timeout: 5))
        checkboxButton.tap()

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
        newNoteButton.tap()

        // Should show template picker sheet or create a new note row
        let templatePicker = app.staticTexts["New Note"]
        let newRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'noteRow_'"))
        let initialCount = newRow.allElementsBoundByAccessibilityElement.count

        // Either a sheet appeared or a new row was added
        let appeared = templatePicker.waitForExistence(timeout: 5) || newRow.allElementsBoundByAccessibilityElement.count > initialCount
        XCTAssertTrue(appeared, "Template picker or new note should appear after tapping new note button")
    }

    func testDailyNoteButtonExists() {
        let dailyButton = app.buttons["dailyNoteButton"]
        XCTAssertTrue(dailyButton.waitForExistence(timeout: 5), "Daily note button should be visible")
    }

    func testDailyNoteButtonCreatesOrNavigates() {
        let initialCount = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'noteRow_'"))
            .allElementsBoundByAccessibilityElement.count

        let dailyButton = app.buttons["dailyNoteButton"]
        XCTAssertTrue(dailyButton.waitForExistence(timeout: 5))
        dailyButton.tap()

        // Wait for either a new note or navigation
        let titleField = app.textFields["noteTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "Title field should appear after daily note action")

        // The title should contain a date-like string or a new row was added
        let titleValue = titleField.value as? String ?? ""
        let newCount = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'noteRow_'"))
            .allElementsBoundByAccessibilityElement.count
        let dateCreatedOrNavigated = newCount > initialCount || !titleValue.isEmpty
        XCTAssertTrue(dateCreatedOrNavigated, "Daily note should create a new note or navigate to existing")
    }
}
