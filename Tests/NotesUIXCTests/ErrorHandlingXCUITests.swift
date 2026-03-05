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
        let errorBanner = element(in: app, identifier: "globalErrorBanner")
        XCTAssertFalse(errorBanner.waitForExistence(timeout: 2), "No error banner should be present on normal launch")
    }

    func testAppRemainsStableAfterRepeatedActions() {
        // 1. Select a note
        selectFirstNote(in: app)

        // 2. Type into the body
        let bodyEditor = app.textViews["noteBodyEditor"]
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 5))
        bodyEditor.tap()
        bodyEditor.typeText("Stability test")

        // 3. Save
        app.buttons["saveNoteButton"].tap()

        // 4. Switch through all tabs
        for tab in ["Tasks", "Board", "Graph", "Sync", "Notes"] {
            navigateToTab(app, tab)
        }

        // 5. Create a quick task
        selectFirstNote(in: app)
        let taskField = app.textFields["quickTaskField"]
        XCTAssertTrue(taskField.waitForExistence(timeout: 5))
        taskField.tap()
        taskField.typeText("Stability task")
        app.buttons["quickTaskButton"].tap()

        // 6. Verify no error banner
        let errorBanner = element(in: app, identifier: "globalErrorBanner")
        XCTAssertFalse(errorBanner.waitForExistence(timeout: 2), "No error banner should appear after repeated actions")

        // 7. Verify app is responsive
        let searchField = app.textFields["noteSearchField"]
        XCTAssertTrue(searchField.exists, "App should remain responsive")
    }
}
