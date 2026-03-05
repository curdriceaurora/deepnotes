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
        _ = openFirstKanbanCard(in: app)

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
        _ = openFirstKanbanCard(in: app)

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

        let firstCard = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'kanbanCard_'")).firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5))
        firstCard.tap()

        let sheet = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'kanbanCardDetailSheet'")).firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Card detail sheet should open on card tap")
    }

    func testCardDetailCancelDismissesSheet() {
        _ = openFirstKanbanCard(in: app)

        let cancelButton = app.buttons["cardDetailCancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5))
        cancelButton.tap()

        let sheet = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'kanbanCardDetailSheet'")).firstMatch
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: sheet,
        )
        XCTWaiter.wait(for: [dismissed], timeout: 5)
        XCTAssertFalse(sheet.exists, "Sheet should dismiss after cancel")
    }

    func testCardDetailSaveDismissesSheet() {
        _ = openFirstKanbanCard(in: app)

        let saveButton = app.buttons["cardDetailSave"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        let sheet = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'kanbanCardDetailSheet'")).firstMatch
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: sheet,
        )
        XCTWaiter.wait(for: [dismissed], timeout: 5)
        XCTAssertFalse(sheet.exists, "Sheet should dismiss after save")
    }

    // MARK: - Form fields

    func testCardDetailStatusPickerExists() {
        _ = openFirstKanbanCard(in: app)

        let statusPicker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'cardDetailStatus'")).firstMatch
        XCTAssertTrue(statusPicker.waitForExistence(timeout: 5), "Status picker should exist in card detail")
    }

    func testCardDetailPriorityPickerExists() {
        _ = openFirstKanbanCard(in: app)

        let priorityPicker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'cardDetailPriority'")).firstMatch
        XCTAssertTrue(priorityPicker.waitForExistence(timeout: 5), "Priority picker should exist in card detail")
    }

    func testCardDetailDueStartToggle() {
        _ = openFirstKanbanCard(in: app)

        let toggle = app.switches["cardDetailDueStartToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Due start toggle should exist")
        toggle.tap()

        let datePicker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'cardDetailDueStart'")).firstMatch
        XCTAssertTrue(datePicker.waitForExistence(timeout: 5), "Due start date picker should appear after toggle")
    }

    func testCardDetailDueEndToggle() {
        _ = openFirstKanbanCard(in: app)

        let toggle = app.switches["cardDetailDueEndToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Due end toggle should exist")
        toggle.tap()

        let datePicker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'cardDetailDueEnd'")).firstMatch
        XCTAssertTrue(datePicker.waitForExistence(timeout: 5), "Due end date picker should appear after toggle")
    }

    func testCardDetailLinkedNotePickerExists() {
        _ = openFirstKanbanCard(in: app)

        let picker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'cardDetailLinkedNote'")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Linked note picker should exist")
    }

    func testCardDetailLabelsSection() {
        _ = openFirstKanbanCard(in: app)

        let labels = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'cardDetailLabels'")).firstMatch
        XCTAssertTrue(labels.waitForExistence(timeout: 5), "Labels section should exist")
    }

    func testCardDetailSubtasksSection() {
        _ = openFirstKanbanCard(in: app)

        let subtasks = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'cardDetailSubtasks'")).firstMatch
        XCTAssertTrue(subtasks.waitForExistence(timeout: 5), "Subtasks section should exist")
    }

    func testCardDetailSavePersistsTitle() {
        _ = openFirstKanbanCard(in: app)

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
        let sheet = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'kanbanCardDetailSheet'")).firstMatch
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: sheet,
        )
        XCTWaiter.wait(for: [dismissed], timeout: 5)

        // Reopen the same card — find it by the new title text
        let updatedCard = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'kanbanCard_'"))
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
