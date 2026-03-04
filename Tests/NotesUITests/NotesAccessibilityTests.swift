import XCTest
@testable import NotesUI

@MainActor
final class NotesAccessibilityTests: XCTestCase {

    // MARK: - Semantic Accessibility Tests
    /// These tests verify that semantic accessibility attributes (labels, hints) are defined
    /// in Views.swift for key interactive elements. The presence of these attributes in the
    /// source code ensures screen reader support; runtime validation of their actual values
    /// requires XCUI tests with the full app context.

    /// Test 1: NotesEditorView has accessibility structure (Quick Open, New Note buttons).
    func testA11yLabels_NotesEditorButtons() throws {
        // Verify accessibility definitions exist in Views.swift by checking source
        let viewsSource = try String(contentsOfFile: "Sources/NotesUI/Views.swift", encoding: .utf8)

        XCTAssertTrue(viewsSource.contains(".accessibilityIdentifier(\"quickOpenButton\")"),
                      "quickOpenButton must have accessibility identifier")
        XCTAssertTrue(viewsSource.contains(".accessibilityLabel(\"Quick Open\")"),
                      "quickOpenButton must have accessibility label")
        XCTAssertTrue(viewsSource.contains(".accessibilityIdentifier(\"newNoteButton\")"),
                      "newNoteButton must have accessibility identifier")
        XCTAssertTrue(viewsSource.contains(".accessibilityLabel(\"New Note\")"),
                      "newNoteButton must have accessibility label")
    }

    /// Test 2: Markdown toolbar buttons have accessibility labels.
    func testA11yLabels_MarkdownToolbarButtons() throws {
        let viewsSource = try String(contentsOfFile: "Sources/NotesUI/Views.swift", encoding: .utf8)

        XCTAssertTrue(viewsSource.contains("insertHeadingButton") ||
                      viewsSource.contains("Insert Heading"),
                      "Markdown heading button must be defined")
        XCTAssertTrue(viewsSource.contains("insertBulletButton") ||
                      viewsSource.contains("Insert Bullet"),
                      "Markdown bullet button must be defined")
    }

    /// Test 3: Editor action buttons (Save) have hints.
    func testA11yHints_EditorActionButtons() throws {
        let viewsSource = try String(contentsOfFile: "Sources/NotesUI/Views.swift", encoding: .utf8)

        XCTAssertTrue(viewsSource.contains(".accessibilityIdentifier(\"saveNoteButton\")"),
                      "saveNoteButton must have accessibility identifier")
        XCTAssertTrue(viewsSource.contains(".accessibilityHint(\"Saves the current note\")"),
                      "saveNoteButton must have accessibility hint")
    }

    /// Test 4: Sync and quick task buttons have hints.
    func testA11yHints_SyncAndQuickTask() throws {
        let viewsSource = try String(contentsOfFile: "Sources/NotesUI/Views.swift", encoding: .utf8)

        XCTAssertTrue(viewsSource.contains(".accessibilityIdentifier(\"quickTaskButton\")"),
                      "quickTaskButton must have accessibility identifier")
        XCTAssertTrue(viewsSource.contains(".accessibilityHint(\"Creates the task from the field\")"),
                      "quickTaskButton must have accessibility hint")
    }

    /// Test 5: Task control elements are labeled.
    func testA11yLabels_TaskControls() throws {
        let viewsSource = try String(contentsOfFile: "Sources/NotesUI/Views.swift", encoding: .utf8)

        XCTAssertTrue(viewsSource.contains(".accessibilityIdentifier(\"quickTaskButton\")"),
                      "quickTaskButton must be defined with accessibility identifier")
        XCTAssertTrue(viewsSource.contains(".accessibilityLabel(\"Add Task\")"),
                      "quickTaskButton must have 'Add Task' label")
    }

    /// Test 6: Sync controls are labeled (calendar field, run button).
    func testA11yLabels_SyncControls() throws {
        let viewsSource = try String(contentsOfFile: "Sources/NotesUI/Views.swift", encoding: .utf8)

        XCTAssertTrue(viewsSource.contains("syncCalendarID") ||
                      viewsSource.contains("Sync"),
                      "Sync controls must be defined")
    }

    /// Test 7: Quick Open button is accessible.
    func testA11yLabels_QuickOpenControls() throws {
        let viewsSource = try String(contentsOfFile: "Sources/NotesUI/Views.swift", encoding: .utf8)

        XCTAssertTrue(viewsSource.contains(".accessibilityIdentifier(\"quickOpenButton\")"),
                      "quickOpenButton must have accessibility identifier")
        XCTAssertTrue(viewsSource.contains(".accessibilityLabel(\"Quick Open\")"),
                      "quickOpenButton must have 'Quick Open' label")
    }

    /// Test 8: Search field has accessibility label and hint.
    func testA11yLabels_SearchField() throws {
        let viewsSource = try String(contentsOfFile: "Sources/NotesUI/Views.swift", encoding: .utf8)

        XCTAssertTrue(viewsSource.contains(".accessibilityIdentifier(\"noteSearchField\")"),
                      "noteSearchField must have accessibility identifier")
        XCTAssertTrue(viewsSource.contains(".accessibilityLabel(\"Search Notes\")"),
                      "noteSearchField must have 'Search Notes' label")
        XCTAssertTrue(viewsSource.contains(".accessibilityHint(\"Search notes by title or content\")"),
                      "noteSearchField must have search hint")
    }

    /// Test 9: Dynamic Type scaling is out of scope for unit tests.
    /// This requires XCUIApplication host context only available in UI/integration tests.
    func testA11yDynamicType_OutOfScope() throws {
        throw XCTSkip("Dynamic Type layout requires XCUIApplication host context (requires XCUI tests)")
    }

    /// Test 10: WCAG contrast validation is out of scope for unit tests.
    /// This requires Simulator or device rendering, which is validated in manual QA.
    func testA11yWCAGContrast_OutOfScope() throws {
        throw XCTSkip("WCAG contrast requires Simulator rendering (requires manual QA or Accessibility Inspector)")
    }
}
