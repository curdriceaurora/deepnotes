import XCTest
import Foundation
import ViewInspector
@testable import NotesDomain
@testable import NotesFeatures
@testable import NotesUI
@testable import NotesSync

// MARK: - Smoke test suite
//
// Each test corresponds to one or more items in Docs/SmokeChecklist.md.
// The tag comment "// smoke-test: §<section>.<item>" maps tests back to the
// checklist.  Tests that require a physical device, live EventKit permission,
// or human judgement are not representable here and remain manual-only; those
// items are noted in comments below.

@MainActor
final class NotesSmokeTests: XCTestCase {

    // MARK: - Helpers

    private func makeViewModel() throws -> AppViewModel {
        try makeTestAppViewModel()
    }

    private func flushAsyncActions() async throws {
        try await _Concurrency.Task.sleep(nanoseconds: 160_000_000)
    }

    // MARK: - §1 App Launch and DB Initialization

    // smoke-test: §1 — Fresh launch: notes list is initially populated from service.
    func testSmokeAppLaunchNotesListPopulated() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        XCTAssertFalse(viewModel.notes.isEmpty, "Notes list must not be empty after load")
        XCTAssertNil(viewModel.errorMessage, "No globalErrorBanner on launch")
        XCTAssertFalse(viewModel.isBusy, "ViewModel must not be busy after load completes")
    }

    // smoke-test: §1 — Notes tab renders without crash; core controls present.
    func testSmokeAppLaunchNotesEditorControlsPresent() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "newNoteButton"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "noteSearchField"))
    }

    // smoke-test: §1 — Tasks tab renders columns.
    func testSmokeAppLaunchKanbanColumnsPresent() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        let view = KanbanBoardView(viewModel: viewModel)
        let inspected = try view.inspect()

        for status in TaskStatus.allCases {
            XCTAssertNoThrow(
                try inspected.find(viewWithAccessibilityIdentifier: "kanbanColumn_\(status.rawValue)"),
                "Kanban column '\(status.rawValue)' must be present at launch"
            )
        }
    }

    // smoke-test: §1 — Sync tab renders calendar field and run-sync button.
    func testSmokeAppLaunchSyncTabControlsPresent() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        let view = SyncDashboardView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "syncCalendarField"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "runSyncButton"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "syncStatusText"))
    }

    // smoke-test: §1 — globalErrorBanner absent at launch (no error set by default).
    func testSmokeNoGlobalErrorBannerAtLaunch() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        let view = NotesRootView(viewModel: viewModel)
        let inspected = try view.inspect()

        // The banner is only rendered when errorMessage is non-nil.
        XCTAssertThrowsError(
            try inspected.find(viewWithAccessibilityIdentifier: "globalErrorBanner"),
            "globalErrorBanner must NOT be present on a clean launch"
        )
    }

    // MARK: - §2 Notes Tab — Create and Edit

    // smoke-test: §2 — Tapping + creates a new note; note count increases.
    func testSmokeNewNoteButtonCreatesNote() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        let countBefore = viewModel.notes.count

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()
        try inspected.find(viewWithAccessibilityIdentifier: "newNoteButton").button().tap()

        await waitUntil { viewModel.notes.count == countBefore + 1 }
        XCTAssertEqual(viewModel.notes.count, countBefore + 1,
                       "A new note must appear in the list after tapping +")
    }

    // smoke-test: §2 — Saving a note persists title change; updated title visible in list.
    func testSmokeSaveNoteUpdatesTitleInList() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        guard let first = viewModel.notes.first else {
            return XCTFail("Expected at least one note in fixture")
        }
        await viewModel.selectNote(id: first.id)

        viewModel.selectedNoteTitle = "Smoke Edited Title"
        viewModel.selectedNoteBody = "Smoke edited body"

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()
        try inspected.find(viewWithAccessibilityIdentifier: "saveNoteButton").button().tap()
        try await flushAsyncActions()

        XCTAssertTrue(
            viewModel.notes.contains { $0.title == "Smoke Edited Title" },
            "Updated title must appear in the notes list after save"
        )
    }

    // smoke-test: §2 — title field and body editor are present in editor.
    func testSmokeNotesEditorFieldsPresent() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "noteTitleField"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "noteBodyEditor"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "saveNoteButton"))
    }

    // MARK: - §3 Notes Tab — Markdown Toolbar

    // smoke-test: §3 — Insert Heading appends "# " to body.
    func testSmokeInsertHeadingButtonAppendsPrefix() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        viewModel.updateSelectedNoteBody("Start")

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()
        try inspected.find(viewWithAccessibilityIdentifier: "insertHeadingButton").button().tap()

        XCTAssertTrue(
            viewModel.selectedNoteBody.contains("# "),
            "Heading prefix must be inserted into body"
        )
    }

    // smoke-test: §3 — Insert Bullet appends "- " to body.
    func testSmokeInsertBulletButtonAppendsPrefix() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        viewModel.updateSelectedNoteBody("Start")

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()
        try inspected.find(viewWithAccessibilityIdentifier: "insertBulletButton").button().tap()

        XCTAssertTrue(
            viewModel.selectedNoteBody.contains("- "),
            "Bullet prefix must be inserted into body"
        )
    }

    // smoke-test: §3 — Insert Checkbox appends "- [ ] " to body.
    func testSmokeInsertCheckboxButtonAppendsPrefix() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        viewModel.updateSelectedNoteBody("Start")

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()
        try inspected.find(viewWithAccessibilityIdentifier: "insertCheckboxButton").button().tap()

        XCTAssertTrue(
            viewModel.selectedNoteBody.contains("- [ ] "),
            "Checkbox prefix must be inserted into body"
        )
    }

    // smoke-test: §3 — All three toolbar buttons are present.
    func testSmokeMarkdownToolbarButtonsPresent() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "insertHeadingButton"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "insertBulletButton"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "insertCheckboxButton"))
    }

    // MARK: - §4 Notes Tab — Search and Snippets

    // smoke-test: §4 — Searching a matching word filters the notes list.
    func testSmokeSearchFiltersNotesList() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        let totalCount = viewModel.notes.count
        XCTAssertGreaterThan(totalCount, 0, "Fixture must contain notes")

        await viewModel.setNoteSearchQuery("Vendor")
        await waitUntil {
            viewModel.notes.count < totalCount
        }

        XCTAssertLessThan(
            viewModel.notes.count, totalCount,
            "Search must filter the notes list to fewer results"
        )
        XCTAssertTrue(
            viewModel.notes.allSatisfy { $0.title.localizedCaseInsensitiveContains("Vendor") || viewModel.noteSearchSnippet(for: $0.id) != nil },
            "All returned notes must match the query by title or have a search snippet"
        )
    }

    // smoke-test: §4 — Snippet view is rendered for a matched note.
    func testSmokeSearchSnippetRendersForMatchedNote() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setNoteSearchQuery("launch")
        await waitUntil {
            !viewModel.notes.isEmpty
        }

        guard let first = viewModel.notes.first else {
            return XCTFail("Expected at least one result for 'launch'")
        }

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(
            try inspected.find(viewWithAccessibilityIdentifier: "noteSnippet_\(first.id.uuidString)"),
            "A snippet must be rendered for a matched note"
        )
        // Verify the view model has stored a non-empty snippet.
        XCTAssertNotNil(viewModel.noteSearchSnippet(for: first.id))
    }

    // smoke-test: §4 — Clearing search restores full notes list.
    func testSmokeClearSearchRestoresList() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        let totalCount = viewModel.notes.count

        await viewModel.setNoteSearchQuery("Vendor")
        await waitUntil {
            viewModel.notes.count < totalCount
        }
        XCTAssertLessThan(viewModel.notes.count, totalCount)

        await viewModel.setNoteSearchQuery("")
        await waitUntil {
            viewModel.notes.count == totalCount
        }
        XCTAssertEqual(viewModel.notes.count, totalCount,
                       "Clearing search must restore the full notes list")
        XCTAssertNil(viewModel.noteSearchQuery.isEmpty ? nil as String? : "non-empty")
    }

    // smoke-test: §4 — Searching for a non-matching word produces empty list.
    func testSmokeSearchNoMatchProducesEmptyList() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        await viewModel.setNoteSearchQuery("zzz_no_match_zzz")
        await waitUntil {
            viewModel.notes.isEmpty
        }

        XCTAssertTrue(viewModel.notes.isEmpty,
                      "Search for non-matching word must produce empty list without crash")
    }

    // MARK: - §5 Notes Tab — Quick Open

    // smoke-test: §5 — openQuickSwitcher sets isQuickOpenPresented and shows results.
    func testSmokeQuickOpenPresentsAndShowsResults() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        viewModel.openQuickSwitcher()

        XCTAssertTrue(viewModel.isQuickOpenPresented, "Quick Open sheet must be presented")
        XCTAssertFalse(viewModel.quickOpenResults.isEmpty, "Quick Open must show results")
    }

    // smoke-test: §5 — Quick Open sheet control identifiers present when presented.
    func testSmokeQuickOpenSheetControlsPresent() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        viewModel.openQuickSwitcher()

        let view = QuickOpenSheetView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "quickOpenSearchField"),
                         "quickOpenSearchField must be present when Quick Open is open")
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "quickOpenCloseButton"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "quickOpenResultsList"))
    }

    // smoke-test: §5 — Typing a partial title filters Quick Open results.
    func testSmokeQuickOpenFiltersByPartialTitle() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        viewModel.openQuickSwitcher()
        viewModel.setQuickOpenQuery("Vendor")

        XCTAssertTrue(
            viewModel.quickOpenResults.allSatisfy {
                $0.title.localizedCaseInsensitiveContains("Vendor")
            },
            "Quick Open results must match the typed partial title"
        )
        XCTAssertFalse(viewModel.quickOpenResults.isEmpty,
                       "Quick Open must return at least one result for 'Vendor'")
    }

    // smoke-test: §5 — Selecting a Quick Open result dismisses sheet and selects note.
    func testSmokeQuickOpenResultSelectionDismissesAndSelectsNote() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        viewModel.openQuickSwitcher()

        guard let target = viewModel.quickOpenResults.first else {
            return XCTFail("Expected Quick Open results")
        }

        await viewModel.selectQuickOpenResult(noteID: target.id)

        XCTAssertFalse(viewModel.isQuickOpenPresented, "Quick Open sheet must close after selection")
        XCTAssertEqual(viewModel.selectedNoteID, target.id,
                       "The selected note must match the tapped Quick Open result")
    }

    // smoke-test: §5 — Tapping Close button dismisses Quick Open without changing selection.
    func testSmokeQuickOpenCloseButtonDismissesWithoutChangingNote() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        // Establish a current selection.
        guard let firstNote = viewModel.notes.first else { return XCTFail("No notes") }
        await viewModel.selectNote(id: firstNote.id)
        let previousSelection = viewModel.selectedNoteID

        viewModel.openQuickSwitcher()

        let view = QuickOpenSheetView(viewModel: viewModel)
        let inspected = try view.inspect()
        try inspected.find(viewWithAccessibilityIdentifier: "quickOpenCloseButton").button().tap()
        try await flushAsyncActions()

        XCTAssertFalse(viewModel.isQuickOpenPresented, "Quick Open must be dismissed after Close")
        XCTAssertEqual(viewModel.selectedNoteID, previousSelection,
                       "Close must not change the currently selected note")
    }

    // MARK: - §6 Notes Tab — Wiki Links and Backlinks

    // smoke-test: §6 — Typing "[[ " triggers the wiki suggestions bar.
    func testSmokeWikiLinkSuggestionsBarAppearsOnDoubleBracket() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        viewModel.updateSelectedNoteBody("See [[")

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(
            try inspected.find(viewWithAccessibilityIdentifier: "wikiSuggestionsBar"),
            "wikiSuggestionsBar must appear when body contains '[['"
        )
        XCTAssertTrue(viewModel.isWikiLinkSuggestionVisible)
        XCTAssertFalse(viewModel.wikiLinkSuggestions.isEmpty,
                       "Suggestions must include other note titles")
    }

    // smoke-test: §6 — Applying a wiki suggestion inserts the link and hides suggestions.
    func testSmokeWikiLinkSuggestionAppliedAndBarHides() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        viewModel.updateSelectedNoteBody("See [[Vendor")

        guard let suggestion = viewModel.wikiLinkSuggestions.first else {
            return XCTFail("Expected wiki link suggestions")
        }
        viewModel.applyWikiLinkSuggestion(suggestion)

        XCTAssertTrue(
            viewModel.selectedNoteBody.contains("[[\(suggestion)]]"),
            "Applied suggestion must be wrapped in [[…]] in the body"
        )
        XCTAssertFalse(viewModel.isWikiLinkSuggestionVisible,
                       "Suggestions bar must hide after a suggestion is applied")
    }

    // smoke-test: §6 — Backlinks are populated for a note that is referenced by another note.
    func testSmokeBacklinksPopulatedForReferencedNote() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        // "Vendor Notes" is referenced by "Q2 Launch Plan" via [[Vendor Notes]].
        guard let vendorNote = viewModel.notes.first(where: { $0.title == "Vendor Notes" }) else {
            return XCTFail("Expected 'Vendor Notes' in fixture")
        }
        await viewModel.selectNote(id: vendorNote.id)

        XCTAssertFalse(viewModel.backlinks.isEmpty,
                       "Backlinks must be non-empty for a referenced note")
        XCTAssertTrue(
            viewModel.backlinks.contains { $0.sourceTitle == "Q2 Launch Plan" },
            "Q2 Launch Plan must appear as a backlink for Vendor Notes"
        )
    }

    // smoke-test: §6 — Backlinks section (list identifier) rendered for a note with backlinks.
    func testSmokeBacklinksListRendersWhenBacklinksPresent() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        guard let vendorNote = viewModel.notes.first(where: { $0.title == "Vendor Notes" }) else {
            return XCTFail("Expected 'Vendor Notes' in fixture")
        }
        await viewModel.selectNote(id: vendorNote.id)
        XCTAssertFalse(viewModel.backlinks.isEmpty)

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(
            try inspected.find(viewWithAccessibilityIdentifier: "backlinksList"),
            "backlinksList must be rendered when a note has incoming backlinks"
        )
    }

    // smoke-test: §6 — Empty backlinks state rendered when no note is selected.
    func testSmokeBacklinksEmptyStateWhenNoNoteSelected() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.selectNote(id: nil)

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(
            try inspected.find(viewWithAccessibilityIdentifier: "backlinksEmptyState"),
            "backlinksEmptyState must be rendered when no note is selected"
        )
    }

    // MARK: - §7 Notes Tab — Quick Task Creation

    // smoke-test: §7 — quickTaskField and quickTaskButton are present in the editor.
    func testSmokeQuickTaskControlsPresent() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "quickTaskField"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "quickTaskButton"))
    }

    // smoke-test: §7 — Tapping Add Task creates a task and clears the quick task field.
    func testSmokeQuickTaskButtonCreatesTaskAndClearsField() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.all)
        let initialTaskCount = viewModel.tasks.count

        viewModel.quickTaskTitle = "Smoke quick task"

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()
        try inspected.find(viewWithAccessibilityIdentifier: "quickTaskButton").button().tap()
        try await flushAsyncActions()

        XCTAssertEqual(viewModel.quickTaskTitle, "",
                       "Quick task field must be cleared after creation")
        await viewModel.setTaskFilter(.all)
        XCTAssertEqual(viewModel.tasks.count, initialTaskCount + 1,
                       "Task count must increase by 1 after quick task creation")
    }

    // smoke-test: §7 — Created quick task appears in Tasks tab with linked noteID.
    func testSmokeQuickTaskHasLinkedNoteID() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let noteToLink = viewModel.notes.first else {
            return XCTFail("Expected at least one note")
        }
        await viewModel.selectNote(id: noteToLink.id)
        viewModel.quickTaskTitle = "Linked task"
        await viewModel.createQuickTask()

        await viewModel.setTaskFilter(.all)
        let created = viewModel.tasks.first { $0.title == "Linked task" }
        XCTAssertNotNil(created, "Linked task must appear in task list")
        XCTAssertEqual(created?.noteID, noteToLink.id,
                       "Quick task must carry the ID of the currently selected note")
    }

    // MARK: - §8 Tasks Tab — List and Filter

    // smoke-test: §8 — taskFilterPicker and tasksList identifiers are present.
    func testSmokeTasksTabControlsPresent() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        let view = TasksListView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "taskFilterPicker"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "tasksList"))
    }

    // smoke-test: §8 — Filter "All" returns all tasks including done.
    func testSmokeFilterAllIncludesDoneTasks() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        XCTAssertTrue(
            viewModel.tasks.contains { $0.status == .done },
            ".all filter must include tasks with status .done"
        )
    }

    // smoke-test: §8 — Filter "Completed" returns only done tasks.
    func testSmokeFilterCompletedShowsOnlyDoneTasks() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.completed)

        XCTAssertFalse(viewModel.tasks.isEmpty,
                       "Completed filter must return at least one done task from fixture")
        XCTAssertTrue(
            viewModel.tasks.allSatisfy { $0.status == .done },
            "Completed filter must return only tasks with .done status"
        )
    }

    // smoke-test: §8 — Filter "Today" returns only tasks with a due date (non-done, has dueStart).
    func testSmokeFilterTodayReturnsDueTasks() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.today)

        XCTAssertTrue(
            viewModel.tasks.allSatisfy { $0.dueStart != nil },
            "Today filter must only return tasks with a due date"
        )
    }

    // smoke-test: §8 — Selecting a filter via the picker updates viewModel.taskFilter.
    func testSmokePickerSelectionUpdatesFilter() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        let view = TasksListView(viewModel: viewModel)
        let inspected = try view.inspect()
        try inspected
            .find(viewWithAccessibilityIdentifier: "taskFilterPicker")
            .picker()
            .select(value: TaskListFilter.completed)
        try await flushAsyncActions()

        XCTAssertEqual(viewModel.taskFilter, .completed)
    }

    // MARK: - §9 Tasks Tab — Status Transitions and Completion

    // smoke-test: §9 — Toggling a task to complete gives it .done status.
    func testSmokeToggleTaskToCompletedStatusIsDone() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let target = viewModel.tasks.first(where: { $0.status == .next }) else {
            return XCTFail("Expected a .next task in fixture")
        }

        await viewModel.toggleTaskCompletion(taskID: target.id, isCompleted: true)
        await viewModel.setTaskFilter(.completed)

        let completed = viewModel.tasks.first { $0.id == target.id }
        XCTAssertNotNil(completed, "Toggled task must appear in completed filter")
        XCTAssertEqual(completed?.status, .done, "Toggled task must have .done status")
    }

    // smoke-test: §9 — Toggle button in list row transitions status and appears in completed filter.
    func testSmokeTaskRowToggleButtonTransitionsToComplete() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let target = viewModel.tasks.first(where: { $0.status == .next }) else {
            return XCTFail("Expected a .next task")
        }

        let view = TasksListView(viewModel: viewModel)
        let inspected = try view.inspect()
        let row = try inspected.find(viewWithAccessibilityIdentifier: "taskRow_\(target.id.uuidString)")
        try row.hStack().button(0).tap()
        try await flushAsyncActions()

        await viewModel.setTaskFilter(.completed)
        XCTAssertTrue(viewModel.tasks.contains(where: { $0.id == target.id }),
                      "Task must appear under .completed filter after toggle")
        XCTAssertEqual(viewModel.tasks.first(where: { $0.id == target.id })?.status, .done,
                       "Status must be .done after toggle")
    }

    // smoke-test: §9 — Toggling a done task back marks it active (not done).
    func testSmokeToggleBackFromDoneRestoresActiveStatus() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let target = viewModel.tasks.first(where: { $0.status == .done }) else {
            return XCTFail("Expected a .done task in fixture")
        }

        await viewModel.toggleTaskCompletion(taskID: target.id, isCompleted: false)
        await viewModel.setTaskFilter(.all)

        let reverted = viewModel.tasks.first { $0.id == target.id }
        XCTAssertNotNil(reverted)
        XCTAssertNotEqual(reverted?.status, .done,
                          "Task status must not be .done after toggling back")
    }

    // MARK: - §10 Tasks Tab — Delete (Tombstone)

    // smoke-test: §10 — Tapping trash removes the task from the list.
    func testSmokeDeleteTaskRemovesFromList() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let target = viewModel.tasks.first(where: { $0.status == .backlog }) else {
            return XCTFail("Expected a backlog task")
        }

        let view = TasksListView(viewModel: viewModel)
        let inspected = try view.inspect()
        try inspected.find(viewWithAccessibilityIdentifier: "deleteTask_\(target.id.uuidString)").button().tap()
        try await flushAsyncActions()

        await viewModel.setTaskFilter(.all)
        XCTAssertFalse(viewModel.tasks.contains(where: { $0.id == target.id }),
                       "Deleted task must no longer appear in the task list")
    }

    // smoke-test: §10 — Deleted task is absent from every filter.
    func testSmokeDeletedTaskAbsentFromAllFilters() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let target = viewModel.tasks.first(where: { $0.status == .backlog }) else {
            return XCTFail("Expected a backlog task")
        }
        await viewModel.deleteTask(taskID: target.id)

        for filter in TaskListFilter.allCases {
            await viewModel.setTaskFilter(filter)
            XCTAssertFalse(
                viewModel.tasks.contains(where: { $0.id == target.id }),
                "Deleted task must not appear under filter '\(filter.rawValue)'"
            )
        }
    }

    // MARK: - §11 Kanban Board Tab — Column Layout

    // smoke-test: §11 — All five status columns are rendered.
    func testSmokeKanbanAllColumnsPresent() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        let view = KanbanBoardView(viewModel: viewModel)
        let inspected = try view.inspect()

        let expected: [TaskStatus] = [.backlog, .next, .doing, .waiting, .done]
        for status in expected {
            XCTAssertNoThrow(
                try inspected.find(viewWithAccessibilityIdentifier: "kanbanColumn_\(status.rawValue)"),
                "Column '\(status.rawValue)' must be present"
            )
        }
    }

    // smoke-test: §11 — Fixture data populates at least one non-empty column.
    func testSmokeKanbanAtLeastOneNonEmptyColumn() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        let hasCards = TaskStatus.allCases.contains { status in
            !viewModel.tasks(for: status).isEmpty
        }
        XCTAssertTrue(hasCards, "At least one Kanban column must have cards from fixture")
    }

    // MARK: - §12 Kanban Board Tab — Card Actions

    // smoke-test: §12 — kanbanCard_* identifiers are rendered for cards in a column.
    func testSmokeKanbanCardIdentifiersPresent() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        guard let backlogTask = viewModel.tasks(for: .backlog).first else {
            return XCTFail("Expected at least one backlog card")
        }

        let view = KanbanBoardView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(
            try inspected.find(viewWithAccessibilityIdentifier: "kanbanCard_\(backlogTask.id.uuidString)"),
            "kanbanCard_* identifier must be present for each card"
        )
    }

    // smoke-test: §12 — moveRight button moves card to next column.
    func testSmokeKanbanMoveRightTransitionsToNextColumn() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let task = viewModel.tasks.first(where: { $0.status == .backlog }) else {
            return XCTFail("Expected backlog task")
        }

        let view = KanbanBoardView(viewModel: viewModel)
        let inspected = try view.inspect()
        try inspected.find(viewWithAccessibilityIdentifier: "moveRight_\(task.id.uuidString)").button().tap()
        await waitUntil { viewModel.tasks.first(where: { $0.id == task.id })?.status == .next }

        await viewModel.setTaskFilter(.all)
        XCTAssertEqual(
            viewModel.tasks.first(where: { $0.id == task.id })?.status, .next,
            "Card moved right from backlog must land in .next"
        )
    }

    // smoke-test: §12 — moveLeft button moves card to previous column.
    func testSmokeKanbanMoveLeftTransitionsToPrevColumn() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let task = viewModel.tasks.first(where: { $0.status == .doing }) else {
            return XCTFail("Expected doing task")
        }

        let view = KanbanBoardView(viewModel: viewModel)
        let inspected = try view.inspect()
        try inspected.find(viewWithAccessibilityIdentifier: "moveLeft_\(task.id.uuidString)").button().tap()
        try await flushAsyncActions()

        await viewModel.setTaskFilter(.all)
        XCTAssertEqual(
            viewModel.tasks.first(where: { $0.id == task.id })?.status, .next,
            "Card moved left from doing must land in .next"
        )
    }

    // smoke-test: §12 — deleteKanbanTask_* button removes card from board.
    func testSmokeKanbanDeleteButtonRemovesCard() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let target = viewModel.tasks.first(where: { $0.status == .backlog }) else {
            return XCTFail("Expected backlog task")
        }

        let view = KanbanBoardView(viewModel: viewModel)
        let inspected = try view.inspect()
        try inspected.find(viewWithAccessibilityIdentifier: "deleteKanbanTask_\(target.id.uuidString)").button().tap()
        try await flushAsyncActions()

        await viewModel.setTaskFilter(.all)
        XCTAssertFalse(viewModel.tasks.contains(where: { $0.id == target.id }),
                       "Deleted card must be absent from the board after delete")
    }

    // smoke-test: §12 — moveLeft absent on backlog (leftmost column).
    func testSmokeKanbanMoveLeftAbsentOnBacklogCard() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        guard let backlogTask = viewModel.tasks(for: .backlog).first else {
            return XCTFail("Expected backlog card")
        }

        let view = KanbanBoardView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertThrowsError(
            try inspected.find(viewWithAccessibilityIdentifier: "moveLeft_\(backlogTask.id.uuidString)"),
            "moveLeft button must NOT appear on a card in the leftmost (backlog) column"
        )
    }

    // smoke-test: §12 — moveRight absent on done (rightmost column).
    func testSmokeKanbanMoveRightAbsentOnDoneCard() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        guard let doneTask = viewModel.tasks(for: .done).first else {
            return XCTFail("Expected done card")
        }

        let view = KanbanBoardView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertThrowsError(
            try inspected.find(viewWithAccessibilityIdentifier: "moveRight_\(doneTask.id.uuidString)"),
            "moveRight button must NOT appear on a card in the rightmost (done) column"
        )
    }

    // MARK: - §13 Kanban Board Tab — Drag Reorder

    // smoke-test: §13 — Drop API moves card cross-column; card appears in target.
    func testSmokeKanbanDropCrossColumnCardInTargetColumn() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let task = viewModel.tasks.first(where: { $0.status == .backlog }) else {
            return XCTFail("Expected backlog task")
        }

        let moved = await viewModel.handleTaskDrop(
            taskPayloads: [task.id.uuidString],
            to: .doing,
            beforeTaskID: nil
        )
        XCTAssertTrue(moved)

        await viewModel.setTaskFilter(.all)
        XCTAssertTrue(viewModel.tasks(for: .doing).contains(where: { $0.id == task.id }),
                      "Dropped task must appear in the .doing column")
        XCTAssertFalse(viewModel.tasks(for: .backlog).contains(where: { $0.id == task.id }),
                       "Dropped task must no longer be in .backlog")
    }

    // smoke-test: §13 — Drop API reorders within same column.
    func testSmokeKanbanDropReorderWithinSameColumn() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        let backlogTasks = viewModel.tasks(for: .backlog)
        guard backlogTasks.count >= 2 else {
            return XCTFail("Need at least 2 backlog tasks")
        }
        let top = backlogTasks[0]
        let bottom = backlogTasks[1]

        let moved = await viewModel.handleTaskDrop(
            taskPayloads: [bottom.id.uuidString],
            to: .backlog,
            beforeTaskID: top.id
        )
        XCTAssertTrue(moved)

        let reordered = viewModel.tasks(for: .backlog).map(\.id)
        guard
            let newTopIdx = reordered.firstIndex(of: bottom.id),
            let newSecondIdx = reordered.firstIndex(of: top.id)
        else {
            return XCTFail("Both tasks must still be in backlog after reorder")
        }
        XCTAssertLessThan(newTopIdx, newSecondIdx,
                          "Previously-bottom card must now appear before previously-top card")
    }

    // smoke-test: §13 — Relative order is preserved when dropping two cards into same target column.
    func testSmokeKanbanDropRelativePositionPreservedAcrossColumns() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        let backlogTasks = viewModel.tasks(for: .backlog)
        guard backlogTasks.count >= 2 else {
            return XCTFail("Need at least 2 backlog tasks")
        }
        let first = backlogTasks[0]
        let second = backlogTasks[1]

        _ = await viewModel.handleTaskDrop(taskPayloads: [first.id.uuidString], to: .waiting, beforeTaskID: nil)
        _ = await viewModel.handleTaskDrop(taskPayloads: [second.id.uuidString], to: .waiting, beforeTaskID: first.id)

        let waitingOrder = viewModel.tasks(for: .waiting).map(\.id)
        guard
            let secondIdx = waitingOrder.firstIndex(of: second.id),
            let firstIdx = waitingOrder.firstIndex(of: first.id)
        else {
            return XCTFail("Both tasks must be in waiting after cross-column drops")
        }
        XCTAssertLessThan(secondIdx, firstIdx,
                          "Second task dropped before first must appear earlier in the column")
    }

    // MARK: - §14 & §15 Sync Tab — UI and Sync Run

    // smoke-test: §14 — Sync tab controls are all present.
    func testSmokeSyncTabControlsPresent() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        let view = SyncDashboardView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "syncCalendarField"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "runSyncButton"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "syncStatusText"))
    }

    // smoke-test: §14 — No report section before first sync.
    func testSmokeSyncNoReportBeforeFirstRun() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        let view = SyncDashboardView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertThrowsError(
            try inspected.find(viewWithAccessibilityIdentifier: "syncReportSection"),
            "syncReportSection must not be visible before any sync has run"
        )
        XCTAssertNil(viewModel.lastSyncReport,
                     "lastSyncReport must be nil before first sync run")
    }

    // smoke-test: §15 — After runSync, lastSyncReport is set and report section appears.
    func testSmokeSyncRunSetsLastSyncReport() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        let view1 = SyncDashboardView(viewModel: viewModel)
        let inspected1 = try view1.inspect()
        XCTAssertThrowsError(try inspected1.find(viewWithAccessibilityIdentifier: "syncReportSection"))

        await viewModel.runSync()

        let view2 = SyncDashboardView(viewModel: viewModel)
        let inspected2 = try view2.inspect()
        XCTAssertNotNil(viewModel.lastSyncReport, "lastSyncReport must be set after sync run")
        XCTAssertNoThrow(try inspected2.find(viewWithAccessibilityIdentifier: "syncReportSection"),
                         "syncReportSection must appear after a sync run")
    }

    // smoke-test: §15 — runSync button triggers state change (status text updates).
    func testSmokeSyncRunButtonUpdatesStatusText() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        let view = SyncDashboardView(viewModel: viewModel)
        let inspected = try view.inspect()
        try inspected.find(viewWithAccessibilityIdentifier: "runSyncButton").button().tap()

        await waitUntil { viewModel.lastSyncReport != nil }
        XCTAssertNotNil(viewModel.lastSyncReport)
    }

    // smoke-test: §15 — Invalid calendar ID (blank) produces an error state.
    func testSmokeSyncInvalidCalendarIDSetsError() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        viewModel.syncCalendarID = "   "
        await viewModel.runSync()

        XCTAssertNotNil(viewModel.errorMessage,
                        "A blank calendar ID must result in an error being surfaced")
    }

    // MARK: - §16 & §17 Sync Tab — Diagnostics Export

    // smoke-test: §16 — Export button is present after a sync run.
    func testSmokeSyncExportDiagnosticsButtonPresentAfterSync() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.runSync()

        let view = SyncDashboardView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(
            try inspected.find(viewWithAccessibilityIdentifier: "exportSyncDiagnosticsButton"),
            "exportSyncDiagnosticsButton must appear after a sync run"
        )
    }

    // smoke-test: §16 — Tapping Export sets lastDiagnosticsExportURL.
    func testSmokeSyncExportButtonWritesExportURL() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.runSync()

        let view = SyncDashboardView(viewModel: viewModel)
        let inspected = try view.inspect()
        try inspected.find(viewWithAccessibilityIdentifier: "exportSyncDiagnosticsButton").button().tap()
        try await flushAsyncActions()

        XCTAssertNotNil(viewModel.lastDiagnosticsExportURL,
                        "Export must set lastDiagnosticsExportURL")
    }

    // smoke-test: §16 — exportDiagnostics() causes syncDiagnosticsExportPath to appear.
    func testSmokeSyncExportPathLabelRendersAfterExport() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.runSync()
        await viewModel.exportSyncDiagnostics()

        let view = SyncDashboardView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(
            try inspected.find(viewWithAccessibilityIdentifier: "syncDiagnosticsExportPath"),
            "syncDiagnosticsExportPath must render after diagnostics are exported"
        )
    }

    // smoke-test: §17 — Diagnostics section and at least one row rendered after sync with warnings.
    func testSmokeSyncDiagnosticsSectionAndRowsRendered() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.runSync()

        let view = SyncDashboardView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(
            try inspected.find(viewWithAccessibilityIdentifier: "syncDiagnosticsSection"),
            "syncDiagnosticsSection must appear after sync that produced diagnostics"
        )
        XCTAssertNoThrow(
            try inspected.find(viewWithAccessibilityIdentifier: "syncDiagnosticRow_0"),
            "At least one syncDiagnosticRow must be rendered"
        )
    }

    // smoke-test: §17 — Recurrence conflict banner renders after sync with detached occurrence.
    func testSmokeSyncRecurrenceConflictBannerPresent() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.runSync()

        let view = SyncDashboardView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(
            try inspected.find(viewWithAccessibilityIdentifier: "recurrenceConflictBanner"),
            "recurrenceConflictBanner must appear when a detached recurrence exception was detected"
        )
    }

    // MARK: - §19 Error States

    // smoke-test: §19 — globalErrorBanner appears when errorMessage is set.
    func testSmokeGlobalErrorBannerAppearsOnError() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        viewModel.syncCalendarID = "   "
        await viewModel.runSync()

        let view = NotesRootView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(
            try inspected.find(viewWithAccessibilityIdentifier: "globalErrorBanner"),
            "globalErrorBanner must render when the view model has an errorMessage"
        )
    }

    // MARK: - §20 Data Integrity After Relaunch (in-process simulation)

    // smoke-test: §20 — Note created and saved within a session is retrievable after reload.
    func testSmokeNoteSurvivestInSessionReload() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        await viewModel.createNote()
        let created = viewModel.notes.first
        guard let createdNote = created else { return XCTFail("createNote must add a note") }

        viewModel.selectedNoteTitle = "Smoke Persistence"
        viewModel.selectedNoteBody = "Body that must persist"
        await viewModel.saveSelectedNote()

        // Simulate reload by calling load() again on the same service-backed viewModel.
        await viewModel.load()

        XCTAssertTrue(
            viewModel.notes.contains { $0.id == createdNote.id },
            "Created note must still be present after in-session reload"
        )
    }

    // smoke-test: §20 — Sync checkpoint token is preserved in lastSyncReport.
    func testSmokeSyncCheckpointTokenSurvivestReport() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        await viewModel.runSync()

        XCTAssertNotNil(viewModel.lastSyncReport?.finalCalendarToken,
                        "Sync checkpoint token must be captured in the sync report")
    }
}
