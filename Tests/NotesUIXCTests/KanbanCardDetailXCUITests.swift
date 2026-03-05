import XCTest

final class KanbanCardDetailXCUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Text entry (migrated from KanbanCardXCUITests)

    func testKanbanCardDetailAcceptsTitle() {
        openFirstKanbanCard(in: app)

        let titleField = app.textFields["cardDetailTitle"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "Card detail title field should exist")
        titleField.tap()

        titleField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 50))
        let newTitle = "XCUI Card Title"
        titleField.typeText(newTitle)

        let fieldValue = titleField.value as? String ?? ""
        XCTAssertTrue(fieldValue.contains(newTitle), "Card title should contain '\(newTitle)', got: '\(fieldValue)'")
    }

    func testKanbanCardDetailAcceptsDetails() {
        openFirstKanbanCard(in: app)

        let detailsEditor = app.textViews["cardDetailDetails"]
        XCTAssertTrue(detailsEditor.waitForExistence(timeout: 5), "Card detail body editor should exist")
        detailsEditor.tap()

        let testText = "XCUI details entry"
        detailsEditor.typeText(testText)

        let editorValue = detailsEditor.value as? String ?? ""
        XCTAssertTrue(editorValue.contains(testText), "Details editor should contain '\(testText)', got: '\(editorValue)'")
    }

    // MARK: - Sheet open/close

    func testCardDetailSheetOpensOnCardTap() {
        navigateToTab(app, "Board")

        let firstCard = elements(in: app, prefix: "kanbanCard_").firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5))
        firstCard.tap()

        let sheet = element(in: app, identifier: "kanbanCardDetailSheet")
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Card detail sheet should open on card tap")
    }

    func testCardDetailCancelDismissesSheet() {
        openFirstKanbanCard(in: app)

        let cancelButton = app.buttons["cardDetailCancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5))
        cancelButton.tap()

        let sheet = element(in: app, identifier: "kanbanCardDetailSheet")
        let result = waitForDisappearance(of: sheet)
        XCTAssertEqual(result, .completed, "Sheet should dismiss after cancel")
    }

    func testCardDetailSaveDismissesSheet() {
        openFirstKanbanCard(in: app)

        let saveButton = app.buttons["cardDetailSave"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        let sheet = element(in: app, identifier: "kanbanCardDetailSheet")
        let result = waitForDisappearance(of: sheet)
        XCTAssertEqual(result, .completed, "Sheet should dismiss after save")
    }

    // MARK: - Form fields

    func testCardDetailStatusPickerExists() {
        openFirstKanbanCard(in: app)
        let statusPicker = element(in: app, identifier: "cardDetailStatus")
        XCTAssertTrue(statusPicker.waitForExistence(timeout: 5), "Status picker should exist in card detail")
    }

    func testCardDetailPriorityPickerExists() {
        openFirstKanbanCard(in: app)
        let priorityPicker = element(in: app, identifier: "cardDetailPriority")
        XCTAssertTrue(priorityPicker.waitForExistence(timeout: 5), "Priority picker should exist in card detail")
    }

    func testCardDetailDueStartToggle() {
        openFirstKanbanCard(in: app)

        let toggle = app.switches["cardDetailDueStartToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Due start toggle should exist")
        toggle.tap()

        let datePicker = element(in: app, identifier: "cardDetailDueStart")
        XCTAssertTrue(datePicker.waitForExistence(timeout: 5), "Due start date picker should appear after toggle")
    }

    func testCardDetailDueEndToggle() {
        openFirstKanbanCard(in: app)

        let toggle = app.switches["cardDetailDueEndToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Due end toggle should exist")
        toggle.tap()

        let datePicker = element(in: app, identifier: "cardDetailDueEnd")
        XCTAssertTrue(datePicker.waitForExistence(timeout: 5), "Due end date picker should appear after toggle")
    }

    func testCardDetailLinkedNotePickerExists() {
        openFirstKanbanCard(in: app)
        let picker = element(in: app, identifier: "cardDetailLinkedNote")
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Linked note picker should exist")
    }

    func testCardDetailLabelsSection() {
        openFirstKanbanCard(in: app)
        let labels = element(in: app, identifier: "cardDetailLabels")
        XCTAssertTrue(labels.waitForExistence(timeout: 5), "Labels section should exist")
    }

    func testCardDetailSubtasksSection() {
        openFirstKanbanCard(in: app)
        let subtasks = element(in: app, identifier: "cardDetailSubtasks")
        XCTAssertTrue(subtasks.waitForExistence(timeout: 5), "Subtasks section should exist")
    }

    func testCardDetailSavePersistsTitle() {
        openFirstKanbanCard(in: app)

        let titleField = app.textFields["cardDetailTitle"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()

        titleField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 50))
        let uniqueTitle = "Persisted-\(Int.random(in: 1000 ... 9999))"
        titleField.typeText(uniqueTitle)

        let saveButton = app.buttons["cardDetailSave"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        // Wait for sheet to dismiss
        let sheet = element(in: app, identifier: "kanbanCardDetailSheet")
        waitForDisappearance(of: sheet)

        // Reopen the card by finding the one with the updated title
        let updatedCard = elements(in: app, prefix: "kanbanCard_")
            .allElementsBoundByAccessibilityElement.first { card in
                card.staticTexts[uniqueTitle].exists
            }
        XCTAssertNotNil(updatedCard, "Card with updated title '\(uniqueTitle)' should exist on the board")

        updatedCard?.tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))

        let reopenedTitle = app.textFields["cardDetailTitle"]
        XCTAssertTrue(reopenedTitle.waitForExistence(timeout: 5))
        let value = reopenedTitle.value as? String ?? ""
        XCTAssertTrue(value.contains(uniqueTitle), "Reopened card should have persisted title '\(uniqueTitle)', got: '\(value)'")
    }
}
