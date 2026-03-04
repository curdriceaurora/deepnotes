import Foundation
import XCTest

@MainActor
final class NotesAccessibilityTests: XCTestCase {
    // MARK: - Helpers

    /// Loads the source of Views.swift relative to this test file's location.
    /// Using `#filePath` ensures the path is resolved correctly regardless of
    /// the test runner's working directory.
    private func loadViewsSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let packageRoot = testFileURL
            .deletingLastPathComponent() // NotesUITests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // package root
        let viewsURL = packageRoot.appendingPathComponent("Sources/NotesUI/Views.swift")
        return try String(contentsOf: viewsURL, encoding: .utf8)
    }

    // MARK: - Semantic Accessibility Tests

    // These tests verify that semantic accessibility attributes (labels, hints) are defined
    // in Views.swift for key interactive elements. The presence of these attributes in the
    // source code ensures screen reader support; runtime validation of their actual values
    // requires XCUI tests with the full app context.

    /// Test 1: NotesEditorView has accessibility structure (Quick Open, New Note buttons).
    func testA11yLabels_NotesEditorButtons() throws {
        // Verify accessibility definitions exist in Views.swift by checking source
        let viewsSource = try loadViewsSource()

        XCTAssertTrue(
            viewsSource.contains(".accessibilityIdentifier(\"quickOpenButton\")"),
            "quickOpenButton must have accessibility identifier",
        )
        XCTAssertTrue(
            viewsSource.contains(".accessibilityLabel(\"Quick Open\")"),
            "quickOpenButton must have accessibility label",
        )
        XCTAssertTrue(
            viewsSource.contains(".accessibilityIdentifier(\"newNoteButton\")"),
            "newNoteButton must have accessibility identifier",
        )
        XCTAssertTrue(
            viewsSource.contains(".accessibilityLabel(\"New Note\")"),
            "newNoteButton must have accessibility label",
        )
    }

    /// Test 2: Markdown toolbar buttons have accessibility labels and hints.
    func testA11yLabels_MarkdownToolbarButtons() throws {
        let viewsSource = try loadViewsSource()

        // Insert Heading
        XCTAssertTrue(
            viewsSource.contains(".accessibilityIdentifier(\"insertHeadingButton\")"),
            "insertHeadingButton must have accessibility identifier",
        )
        XCTAssertTrue(
            viewsSource.contains(".accessibilityLabel(\"Insert Heading\")"),
            "insertHeadingButton must have 'Insert Heading' label",
        )
        XCTAssertTrue(
            viewsSource.contains(".accessibilityHint(\"Inserts a # heading at the cursor\")"),
            "insertHeadingButton must have hint",
        )

        // Insert Bullet
        XCTAssertTrue(
            viewsSource.contains(".accessibilityIdentifier(\"insertBulletButton\")"),
            "insertBulletButton must have accessibility identifier",
        )
        XCTAssertTrue(
            viewsSource.contains(".accessibilityLabel(\"Insert Bullet\")"),
            "insertBulletButton must have 'Insert Bullet' label",
        )
        XCTAssertTrue(
            viewsSource.contains(".accessibilityHint(\"Inserts a bullet list item\")"),
            "insertBulletButton must have hint",
        )

        // Insert Checkbox
        XCTAssertTrue(
            viewsSource.contains(".accessibilityIdentifier(\"insertCheckboxButton\")"),
            "insertCheckboxButton must have accessibility identifier",
        )
        XCTAssertTrue(
            viewsSource.contains(".accessibilityLabel(\"Insert Checkbox\")"),
            "insertCheckboxButton must have 'Insert Checkbox' label",
        )
        XCTAssertTrue(
            viewsSource.contains(".accessibilityHint(\"Inserts a task checkbox\")"),
            "insertCheckboxButton must have hint",
        )
    }

    /// Test 3: Editor action buttons (Save) have hints.
    func testA11yHints_EditorActionButtons() throws {
        let viewsSource = try loadViewsSource()

        XCTAssertTrue(
            viewsSource.contains(".accessibilityIdentifier(\"saveNoteButton\")"),
            "saveNoteButton must have accessibility identifier",
        )
        XCTAssertTrue(
            viewsSource.contains(".accessibilityHint(\"Saves the current note\")"),
            "saveNoteButton must have accessibility hint",
        )
    }

    /// Test 4: Sync and quick task buttons have hints.
    func testA11yHints_SyncAndQuickTask() throws {
        let viewsSource = try loadViewsSource()

        XCTAssertTrue(
            viewsSource.contains(".accessibilityIdentifier(\"quickTaskButton\")"),
            "quickTaskButton must have accessibility identifier",
        )
        XCTAssertTrue(
            viewsSource.contains(".accessibilityHint(\"Creates the task from the field\")"),
            "quickTaskButton must have accessibility hint",
        )
    }

    /// Test 5: Task control elements are labeled.
    func testA11yLabels_TaskControls() throws {
        let viewsSource = try loadViewsSource()

        XCTAssertTrue(
            viewsSource.contains(".accessibilityIdentifier(\"quickTaskButton\")"),
            "quickTaskButton must be defined with accessibility identifier",
        )
        XCTAssertTrue(
            viewsSource.contains(".accessibilityLabel(\"Add Task\")"),
            "quickTaskButton must have 'Add Task' label",
        )
    }

    /// Test 6: Sync controls are labeled (calendar field, run button).
    func testA11yLabels_SyncControls() throws {
        let viewsSource = try loadViewsSource()

        // Calendar field
        XCTAssertTrue(
            viewsSource.contains(".accessibilityIdentifier(\"syncCalendarField\")"),
            "syncCalendarField must have accessibility identifier",
        )

        // Run Sync button: identifier + label + hint
        XCTAssertTrue(
            viewsSource.contains(".accessibilityIdentifier(\"runSyncButton\")"),
            "runSyncButton must have accessibility identifier",
        )
        XCTAssertTrue(
            viewsSource.contains(".accessibilityLabel(\"Sync\")"),
            "runSyncButton must have 'Sync' accessibility label",
        )
        XCTAssertTrue(
            viewsSource.contains(".accessibilityHint(\"Runs calendar sync\")"),
            "runSyncButton must have accessibility hint describing its action",
        )
    }

    /// Test 7: Quick Open button is accessible.
    func testA11yLabels_QuickOpenControls() throws {
        let viewsSource = try loadViewsSource()

        XCTAssertTrue(
            viewsSource.contains(".accessibilityIdentifier(\"quickOpenButton\")"),
            "quickOpenButton must have accessibility identifier",
        )
        XCTAssertTrue(
            viewsSource.contains(".accessibilityLabel(\"Quick Open\")"),
            "quickOpenButton must have 'Quick Open' label",
        )
    }

    /// Test 8: Search field has accessibility label and hint.
    func testA11yLabels_SearchField() throws {
        let viewsSource = try loadViewsSource()

        XCTAssertTrue(
            viewsSource.contains(".accessibilityIdentifier(\"noteSearchField\")"),
            "noteSearchField must have accessibility identifier",
        )
        XCTAssertTrue(
            viewsSource.contains(".accessibilityLabel(\"Search Notes\")"),
            "noteSearchField must have 'Search Notes' label",
        )
        XCTAssertTrue(
            viewsSource.contains(".accessibilityHint(\"Search notes by title or content\")"),
            "noteSearchField must have search hint",
        )
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
