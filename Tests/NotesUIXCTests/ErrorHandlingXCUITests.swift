import XCTest

final class ErrorHandlingXCUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Tests

    func testNoErrorBannerOnNormalLaunch() {
        let errorBanner = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'globalErrorBanner'")).firstMatch
        XCTAssertFalse(errorBanner.exists, "No error banner should be present on normal launch")
    }

    func testAppRemainsStableAfterRepeatedActions() {
        // 1. Select a note
        let firstRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'noteRow_'")).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.tap()

        // 2. Type into the body
        let bodyEditor = app.textViews["noteBodyEditor"]
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 5))
        bodyEditor.tap()
        bodyEditor.typeText("Stability test")

        // 3. Save
        let saveButton = app.buttons["saveNoteButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        // 4. Switch through all tabs
        for tab in ["Tasks", "Board", "Graph", "Sync", "Notes"] {
            navigateToTab(app, tab)
        }

        // 5. Create a quick task
        firstRow.tap()
        let taskField = app.textFields["quickTaskField"]
        XCTAssertTrue(taskField.waitForExistence(timeout: 5))
        taskField.tap()
        taskField.typeText("Stability task")

        let taskButton = app.buttons["quickTaskButton"]
        taskButton.tap()

        // 6. Verify no error banner
        Thread.sleep(forTimeInterval: 1)
        let errorBanner = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'globalErrorBanner'")).firstMatch
        XCTAssertFalse(errorBanner.exists, "No error banner should appear after repeated actions")

        // 7. Verify app is responsive
        let searchField = app.textFields["noteSearchField"]
        XCTAssertTrue(searchField.exists, "App should remain responsive")
    }
}
