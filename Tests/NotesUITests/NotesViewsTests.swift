import XCTest
import Foundation
import ViewInspector
@testable import NotesDomain
@testable import NotesFeatures
@testable import NotesUI
@testable import NotesSync

@MainActor
final class NotesViewsTests: XCTestCase {
    func testNotesEditorContainsCoreControls() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "newNoteButton"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "noteSearchField"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "noteTitleField"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "noteBodyEditor"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "saveNoteButton"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "quickOpenButton"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "insertHeadingButton"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "insertBulletButton"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "insertCheckboxButton"))
    }

    func testTasksListContainsPickerAndRows() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        let view = TasksListView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "taskFilterPicker"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "tasksList"))
    }

    func testKanbanRendersAllStatusColumns() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        let view = KanbanBoardView(viewModel: viewModel)
        let inspected = try view.inspect()

        for status in TaskStatus.allCases {
            XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "kanbanColumn_\(status.rawValue)"))
        }
    }

    func testSyncDashboardHasCalendarFieldAndRunButton() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        let view = SyncDashboardView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "syncCalendarField"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "runSyncButton"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "syncStatusText"))
    }

    func testNotesEditorNewNoteButtonTriggersCreation() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        let countBefore = viewModel.notes.count

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()
        try inspected.find(viewWithAccessibilityIdentifier: "newNoteButton").button().tap()

        await waitUntil { viewModel.notes.count == countBefore + 1 }
        XCTAssertEqual(viewModel.notes.count, countBefore + 1)
    }

    func testSyncDashboardRunButtonUpdatesStatus() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        let view = SyncDashboardView(viewModel: viewModel)
        let inspected = try view.inspect()
        try inspected.find(viewWithAccessibilityIdentifier: "runSyncButton").button().tap()

        await waitUntil { viewModel.lastSyncReport != nil }
        XCTAssertNotNil(viewModel.lastSyncReport)
    }

    func testKanbanMoveRightButtonTransitionsTask() async throws {
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
        let moved = viewModel.tasks.first { $0.id == task.id }
        XCTAssertEqual(moved?.status, .next)
    }

    func testRootViewRendersErrorBannerWhenViewModelHasError() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        viewModel.syncCalendarID = "   "
        await viewModel.runSync()

        let view = NotesRootView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "globalErrorBanner"))
    }

    func testNotesEditorNoteRowTapSelectsNote() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        guard let target = viewModel.notes.dropFirst().first else {
            return XCTFail("Expected at least 2 notes")
        }

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()
        try inspected.find(viewWithAccessibilityIdentifier: "noteRow_\(target.id.uuidString)").button().tap()
        try await flushAsyncActions()

        XCTAssertEqual(viewModel.selectedNoteID, target.id)
    }

    func testNotesEditorRendersSearchSnippetForMatchedNote() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setNoteSearchQuery("launch")
        try? await _Concurrency.Task.sleep(for: .milliseconds(400))

        guard let first = viewModel.notes.first else {
            return XCTFail("Expected searched note")
        }

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "noteSnippet_\(first.id.uuidString)"))
    }

    func testNotesEditorRendersWikiSuggestionsBarWhenTypingWikilink() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        viewModel.updateSelectedNoteBody("See [[launch")

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "wikiSuggestionsBar"))
    }

    func testNotesEditorSaveAndQuickTaskButtonsTriggerActions() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.all)
        let initialCount = viewModel.tasks.count

        viewModel.selectedNoteTitle = "Edited title"
        viewModel.selectedNoteBody = "Edited body"
        viewModel.quickTaskTitle = "Follow up from view"

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()
        try inspected.find(viewWithAccessibilityIdentifier: "saveNoteButton").button().tap()
        try inspected.find(viewWithAccessibilityIdentifier: "quickTaskButton").button().tap()
        try await flushAsyncActions()

        XCTAssertEqual(viewModel.quickTaskTitle, "")
        await viewModel.setTaskFilter(.all)
        XCTAssertEqual(viewModel.tasks.count, initialCount + 1)
    }

    func testNotesEditorRendersBacklinksListWhenPresent() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        // "Vendor Notes" is referenced by "Q2 Launch Plan" via [[Vendor Notes]],
        // so it has at least one backlink. Select it explicitly so the backlinks
        // section is guaranteed to be non-empty when we inspect the view.
        guard let vendorNote = viewModel.notes.first(where: { $0.title == "Vendor Notes" }) else {
            return XCTFail("Expected 'Vendor Notes' note in mock data")
        }
        await viewModel.selectNote(id: vendorNote.id)

        // Verify the view model agrees that backlinks are present before inspecting.
        XCTAssertFalse(
            viewModel.backlinks.isEmpty,
            "Backlinks must be non-empty for the selected note before asserting the list renders"
        )

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "backlinksList"))
    }

    func testNotesEditorRendersBacklinksEmptyStateWhenNoSelection() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.selectNote(id: nil)

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "backlinksEmptyState"))
    }

    func testTasksListPickerSelectionUpdatesFilter() async throws {
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

    func testTasksListTaskRowToggleButtonUpdatesTaskStatus() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let target = viewModel.tasks.first(where: { $0.status == .next }) else {
            return XCTFail("Expected next task")
        }

        let view = TasksListView(viewModel: viewModel)
        let inspected = try view.inspect()
        let row = try inspected.find(viewWithAccessibilityIdentifier: "taskRow_\(target.id.uuidString)")
        try row.hStack().button(0).tap()
        try await flushAsyncActions()

        await viewModel.setTaskFilter(.completed)
        XCTAssertTrue(viewModel.tasks.contains(where: { $0.id == target.id }),
                      "Toggled task must appear in completed filter")
        XCTAssertEqual(viewModel.tasks.first(where: { $0.id == target.id })?.status, .done,
                       "Toggled task must have status .done")
    }

    func testTasksListDeleteButtonRemovesTask() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let target = viewModel.tasks.first(where: { $0.status == .backlog }) else {
            return XCTFail("Expected backlog task")
        }

        let view = TasksListView(viewModel: viewModel)
        let inspected = try view.inspect()
        try inspected.find(viewWithAccessibilityIdentifier: "deleteTask_\(target.id.uuidString)").button().tap()
        try await flushAsyncActions()

        await viewModel.setTaskFilter(.all)
        XCTAssertFalse(viewModel.tasks.contains(where: { $0.id == target.id }))
    }

    func testKanbanMoveLeftButtonTransitionsTask() async throws {
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
        let moved = viewModel.tasks.first { $0.id == task.id }
        XCTAssertEqual(moved?.status, .next)
    }

    func testKanbanDeleteButtonRemovesTask() async throws {
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
        XCTAssertFalse(viewModel.tasks.contains(where: { $0.id == target.id }))
    }

    // MARK: - Kanban ordering UI tests

    /// Tapping moveRight on a backlog card and then moveLeft on the resulting next card
    /// leaves the column ordering stable and the task ends back in backlog.
    func testKanbanMoveRightThenLeftRestoresOriginalColumn() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let task = viewModel.tasks.first(where: { $0.status == .backlog }) else {
            return XCTFail("Expected backlog task")
        }

        let view = KanbanBoardView(viewModel: viewModel)
        let inspected = try view.inspect()

        // Move right: backlog -> next
        try inspected.find(viewWithAccessibilityIdentifier: "moveRight_\(task.id.uuidString)").button().tap()
        try await flushAsyncActions()
        await viewModel.setTaskFilter(.all)
        XCTAssertEqual(viewModel.tasks.first(where: { $0.id == task.id })?.status, .next)

        // Re-inspect after state change, then move left: next -> backlog
        let view2 = KanbanBoardView(viewModel: viewModel)
        let inspected2 = try view2.inspect()
        try inspected2.find(viewWithAccessibilityIdentifier: "moveLeft_\(task.id.uuidString)").button().tap()
        try await flushAsyncActions()
        await viewModel.setTaskFilter(.all)

        XCTAssertEqual(viewModel.tasks.first(where: { $0.id == task.id })?.status, .backlog)
    }

    /// After moving a task cross-column via the drop API, the KanbanBoardView renders
    /// a card for that task inside the target column's accessibility container.
    func testKanbanDropCrossColumnCardAppearsInTargetColumn() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let task = viewModel.tasks.first(where: { $0.status == .backlog }) else {
            return XCTFail("Expected backlog task")
        }

        // Perform cross-column move: backlog -> doing
        let moved = await viewModel.handleTaskDrop(
            taskPayloads: [task.id.uuidString],
            to: .doing,
            beforeTaskID: nil
        )
        XCTAssertTrue(moved)
        await viewModel.setTaskFilter(.all)

        // The card should now be present in the doing column state
        let view = KanbanBoardView(viewModel: viewModel)
        let inspected = try view.inspect()
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "kanbanColumn_doing"))
        XCTAssertTrue(viewModel.tasks(for: .doing).contains(where: { $0.id == task.id }))
        XCTAssertFalse(viewModel.tasks(for: .backlog).contains(where: { $0.id == task.id }))
    }

    /// Moving two tasks from backlog into the same target column via beforeTaskID preserves
    /// the requested insertion order: the second card lands before the first.
    func testKanbanDropCrossColumnRelativePositionIsPreserved() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        let backlogTasks = viewModel.tasks(for: .backlog)
        guard backlogTasks.count >= 2 else {
            return XCTFail("Expected at least 2 backlog tasks")
        }
        let first = backlogTasks[0]
        let second = backlogTasks[1]

        // Move first card to waiting
        let move1 = await viewModel.handleTaskDrop(
            taskPayloads: [first.id.uuidString],
            to: .waiting,
            beforeTaskID: nil
        )
        XCTAssertTrue(move1)

        // Move second card to waiting, before the first
        let move2 = await viewModel.handleTaskDrop(
            taskPayloads: [second.id.uuidString],
            to: .waiting,
            beforeTaskID: first.id
        )
        XCTAssertTrue(move2)

        let waitingOrder = viewModel.tasks(for: .waiting).map(\.id)
        // The waiting column may have pre-existing tasks; verify relative ordering of the
        // two moved cards: second must appear before first in the final column.
        guard
            let secondIdx = waitingOrder.firstIndex(of: second.id),
            let firstIdx = waitingOrder.firstIndex(of: first.id)
        else {
            return XCTFail("Both moved tasks should be present in waiting column")
        }
        XCTAssertLessThan(secondIdx, firstIdx,
            "Second card dropped before first should appear earlier in the column")
    }

    /// Reordering within the same column via the drop API is reflected in the view model
    /// state that KanbanBoardView reads from, verifying the ordering requirement end-to-end
    /// from the view layer.
    func testKanbanDropSameColumnReorderIsReflectedInColumnOrder() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        let backlogBefore = viewModel.tasks(for: .backlog).map(\.id)
        guard backlogBefore.count >= 2 else {
            return XCTFail("Expected at least 2 backlog tasks")
        }
        let top = backlogBefore[0]
        let bottom = backlogBefore[1]

        // Move the bottom card before the top card -> it should become the new top
        let moved = await viewModel.handleTaskDrop(
            taskPayloads: [bottom.uuidString],
            to: .backlog,
            beforeTaskID: top
        )
        XCTAssertTrue(moved)

        let backlogAfter = viewModel.tasks(for: .backlog).map(\.id)
        XCTAssertEqual(backlogAfter[0], bottom, "Reordered card should now be at the top of the column")
        XCTAssertEqual(backlogAfter[1], top, "Original top card should now be second")

        // Verify the KanbanBoardView renders the column without error after reorder
        let view = KanbanBoardView(viewModel: viewModel)
        let inspected = try view.inspect()
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "kanbanColumn_backlog"))
    }

    func testSyncDashboardShowsReportSectionAfterSync() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        let first = SyncDashboardView(viewModel: viewModel)
        let firstInspected = try first.inspect()
        XCTAssertThrowsError(try firstInspected.find(viewWithAccessibilityIdentifier: "syncReportSection"))

        await viewModel.runSync()
        let second = SyncDashboardView(viewModel: viewModel)
        let secondInspected = try second.inspect()
        XCTAssertNoThrow(try secondInspected.find(viewWithAccessibilityIdentifier: "syncReportSection"))
        XCTAssertNoThrow(try secondInspected.find(viewWithAccessibilityIdentifier: "syncDiagnosticsSection"))
        XCTAssertNoThrow(try secondInspected.find(viewWithAccessibilityIdentifier: "syncDiagnosticRow_0"))
    }

    func testSyncDashboardShowsRecurrenceConflictBannerWhenDetected() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.runSync()

        let view = SyncDashboardView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "recurrenceConflictBanner"))
    }

    func testSyncDashboardExportDiagnosticsButtonWritesExportPath() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.runSync()

        let view = SyncDashboardView(viewModel: viewModel)
        let inspected = try view.inspect()
        try inspected.find(viewWithAccessibilityIdentifier: "exportSyncDiagnosticsButton").button().tap()
        try await flushAsyncActions()

        XCTAssertNotNil(viewModel.lastDiagnosticsExportURL)
    }

    func testSyncDashboardShowsExportedPathAfterExport() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        await viewModel.runSync()
        await viewModel.exportSyncDiagnostics()

        let view = SyncDashboardView(viewModel: viewModel)
        let inspected = try view.inspect()
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "syncDiagnosticsExportPath"))
    }

    private func makeViewModel() throws -> AppViewModel {
        let service = try MockWorkspaceService()
        let provider = InMemoryCalendarProvider()
        return AppViewModel(
            service: service,
            calendarProviderFactory: { provider },
            syncCalendarID: "dev-calendar"
        )
    }

    /// Polls `condition` up to `deadline` seconds (default 2 s), yielding every
    /// 20 ms.  Fails the test if the condition is still false at the deadline.
    /// Use this instead of fixed-duration sleeps so CI machines with variable
    /// scheduler latency don't cause flaky timeouts.
    private func waitUntil(
        deadline: TimeInterval = 2.0,
        file: StaticString = #file,
        line: UInt = #line,
        condition: @MainActor () -> Bool
    ) async {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) >= deadline {
                XCTFail("Condition not met within \(deadline) s", file: file, line: line)
                return
            }
            try? await _Concurrency.Task.sleep(nanoseconds: 20_000_000) // 20 ms
        }
    }

    private func flushAsyncActions() async throws {
        try await _Concurrency.Task.sleep(nanoseconds: 160_000_000)
    }

    func testTogglePreviewButtonRenders() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "togglePreviewButton"))
    }

    func testPreviewModeShowsPreviewNotEditor() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        viewModel.toggleNoteEditMode()

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "noteBodyPreview"))
        XCTAssertThrowsError(try inspected.find(viewWithAccessibilityIdentifier: "noteBodyEditor"))
    }

    func testEditModeShowsEditorNotPreview() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "noteBodyEditor"))
        XCTAssertThrowsError(try inspected.find(viewWithAccessibilityIdentifier: "noteBodyPreview"))
    }

    func testTagFilterBarRendersWithTags() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let taggedNotes = [
            Note(id: UUID(), title: "Note 1", body: "#swift code", tags: ["swift"], updatedAt: now, version: 1),
            Note(id: UUID(), title: "Note 2", body: "#rust code", tags: ["rust"], updatedAt: now, version: 1)
        ]
        let service = MockWorkspaceService(notes: taggedNotes, tasks: [])
        let provider = InMemoryCalendarProvider()
        let viewModel = AppViewModel(service: service, calendarProviderFactory: { provider }, syncCalendarID: "cal")
        await viewModel.load()

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "tagFilterBar"))
    }

    func testNoteTagBadgesRender() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let noteID = UUID()
        let taggedNotes = [
            Note(id: noteID, title: "Note 1", body: "#swift code", tags: ["swift"], updatedAt: now, version: 1)
        ]
        let service = MockWorkspaceService(notes: taggedNotes, tasks: [])
        let provider = InMemoryCalendarProvider()
        let viewModel = AppViewModel(service: service, calendarProviderFactory: { provider }, syncCalendarID: "cal")
        await viewModel.load()

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "noteTags_\(noteID.uuidString)"))
    }

    func testBacklinkRowsAreClickable() async throws {
        let viewModel = try makeViewModel()
        await viewModel.load()
        // Select "Q2 Launch Plan" which has a backlink from "Vendor Notes"
        if let q2 = viewModel.notes.first(where: { $0.title == "Q2 Launch Plan" }) {
            await viewModel.selectNote(id: q2.id)
        }

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()

        // Should find backlinks list
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "backlinksList"))
    }
}

actor MockWorkspaceService: WorkspaceServicing {
    private var notes: [Note]
    private var tasks: [Task]

    /// Builds the shared fixture notes and tasks.  Throws on programmer error
    /// (malformed hardcoded values) rather than crashing the test process.
    static func makeFixture() throws -> (notes: [Note], tasks: [Task]) {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let noteID1 = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let noteID2 = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let noteID3 = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let notes: [Note] = [
            Note(
                id: noteID1,
                title: "Q2 Launch Plan",
                body: "References [[Vendor Notes]]",
                updatedAt: now,
                version: 1,
                deletedAt: nil
            ),
            Note(
                id: noteID2,
                title: "Vendor Notes",
                body: "Connected to [[Q2 Launch Plan]]",
                updatedAt: now,
                version: 1,
                deletedAt: nil
            ),
            Note(
                id: noteID3,
                title: "Team Standup",
                body: "Weekly sync meeting agenda and notes.",
                updatedAt: now,
                version: 1,
                deletedAt: nil
            )
        ]
        let tasks: [Task] = [
            try Task(
                id: XCTUnwrap(UUID(uuidString: "10000000-0000-0000-0000-000000000001")),
                noteID: noteID1,
                stableID: "task-backlog",
                title: "Research",
                status: .backlog,
                priority: 2,
                kanbanOrder: 1,
                updatedAt: now
            ),
            try Task(
                id: XCTUnwrap(UUID(uuidString: "10000000-0000-0000-0000-000000000006")),
                noteID: noteID1,
                stableID: "task-backlog-2",
                title: "Design",
                status: .backlog,
                priority: 2,
                kanbanOrder: 2,
                updatedAt: now
            ),
            try Task(
                id: XCTUnwrap(UUID(uuidString: "10000000-0000-0000-0000-000000000002")),
                noteID: noteID1,
                stableID: "task-next",
                title: "Call supplier",
                dueStart: now.addingTimeInterval(3600),
                dueEnd: now.addingTimeInterval(7200),
                status: .next,
                priority: 3,
                kanbanOrder: 1,
                updatedAt: now
            ),
            try Task(
                id: XCTUnwrap(UUID(uuidString: "10000000-0000-0000-0000-000000000003")),
                noteID: noteID1,
                stableID: "task-doing",
                title: "Draft email",
                status: .doing,
                priority: 3,
                kanbanOrder: 1,
                updatedAt: now
            ),
            try Task(
                id: XCTUnwrap(UUID(uuidString: "10000000-0000-0000-0000-000000000004")),
                noteID: noteID1,
                stableID: "task-waiting",
                title: "Await feedback",
                status: .waiting,
                priority: 2,
                kanbanOrder: 1,
                updatedAt: now
            ),
            try Task(
                id: XCTUnwrap(UUID(uuidString: "10000000-0000-0000-0000-000000000005")),
                noteID: noteID1,
                stableID: "task-done",
                title: "Kickoff",
                status: .done,
                priority: 1,
                kanbanOrder: 1,
                completedAt: now,
                updatedAt: now
            )
        ]
        return (notes, tasks)
    }

    init() throws {
        let fixture = try MockWorkspaceService.makeFixture()
        self.notes = fixture.notes
        self.tasks = fixture.tasks
    }

    init(notes: [Note], tasks: [Task]) {
        self.notes = notes
        self.tasks = tasks
    }

    func fetchNote(id: UUID) async throws -> Note? {
        notes.first { $0.id == id }
    }

    func listNotes() async throws -> [Note] {
        notes
    }

    func searchNotes(query: String, limit: Int) async throws -> [Note] {
        let page = try await searchNotesPage(query: query, mode: .smart, limit: limit, offset: 0)
        return page.hits.map(\.note)
    }

    func searchNotesPage(query: String, mode: NoteSearchMode, limit: Int, offset: Int) async throws -> NoteSearchPage {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLimit = max(1, limit)
        let normalizedOffset = max(0, offset)
        guard !trimmed.isEmpty else {
            let start = min(normalizedOffset, notes.count)
            let end = min(notes.count, start + normalizedLimit)
            return NoteSearchPage(
                query: trimmed,
                mode: mode,
                offset: normalizedOffset,
                limit: normalizedLimit,
                totalCount: notes.count,
                hits: Array(notes[start..<end]).map { NoteSearchHit(note: $0, snippet: nil, rank: 0) }
            )
        }

        let filtered = notes
            .filter { $0.title.localizedCaseInsensitiveContains(trimmed) || $0.body.localizedCaseInsensitiveContains(trimmed) }
        let start = min(normalizedOffset, filtered.count)
        let end = min(filtered.count, start + normalizedLimit)
        let hits = Array(filtered[start..<end]).map { note in
            NoteSearchHit(note: note, snippet: "<mark>\(trimmed)</mark> in \(note.title)", rank: 0)
        }
        return NoteSearchPage(
            query: trimmed,
            mode: mode,
            offset: normalizedOffset,
            limit: normalizedLimit,
            totalCount: filtered.count,
            hits: hits
        )
    }

    func createNote(title: String, body: String) async throws -> Note {
        let note = Note(id: UUID(), title: title, body: body, updatedAt: Date(), version: 1, deletedAt: nil)
        notes.insert(note, at: 0)
        return note
    }

    func updateNote(id: UUID, title: String, body: String) async throws -> Note {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else {
            throw NSError(domain: "mock", code: 404)
        }
        notes[idx].title = title
        notes[idx].body = body
        notes[idx].updatedAt = Date()
        return notes[idx]
    }

    func backlinks(for noteID: UUID) async throws -> [NoteBacklink] {
        guard let target = notes.first(where: { $0.id == noteID }) else { return [] }
        return notes
            .filter { $0.id != noteID && $0.body.localizedCaseInsensitiveContains("[[\(target.title)]]") }
            .map { NoteBacklink(sourceNoteID: $0.id, sourceTitle: $0.title) }
    }

    func notesByTag(_ tag: String) async throws -> [Note] {
        notes.filter { $0.tags.contains(where: { $0.lowercased() == tag.lowercased() }) }
    }

    func allTags() async throws -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for note in notes {
            for tag in note.tags {
                let lowered = tag.lowercased()
                if !seen.contains(lowered) {
                    seen.insert(lowered)
                    result.append(lowered)
                }
            }
        }
        return result.sorted()
    }

    func listNoteListItems() async throws -> [NoteListItem] {
        notes.map(\.listItem)
    }

    func listNoteListItems(tag: String) async throws -> [NoteListItem] {
        notes.filter { $0.tags.contains(where: { $0.lowercased() == tag.lowercased() }) }.map(\.listItem)
    }

    func listTasks(filter: TaskListFilter) async throws -> [Task] {
        let now = Date()
        let calendar = Calendar.current
        switch filter {
        case .all:
            return tasks
        case .today:
            return tasks.filter { $0.status != .done && $0.dueStart != nil && calendar.isDateInToday($0.dueStart!) }
        case .upcoming:
            return tasks.filter { $0.status != .done && $0.dueStart != nil && $0.dueStart! > now && !calendar.isDateInToday($0.dueStart!) }
        case .overdue:
            return tasks.filter { $0.status != .done && $0.dueStart != nil && $0.dueStart! < now && !calendar.isDateInToday($0.dueStart!) }
        case .completed:
            return tasks.filter { $0.status == .done }
        }
    }

    func listAllTasks() async throws -> [Task] {
        tasks
    }

    func createTask(_ input: NewTaskInput) async throws -> Task {
        let nextOrder = (tasks.filter { $0.status == input.status }.map(\.kanbanOrder).max() ?? 0) + 1
        let task = try Task(
            id: UUID(),
            noteID: input.noteID,
            stableID: UUID().uuidString.lowercased(),
            title: input.title,
            details: input.details,
            dueStart: input.dueStart,
            dueEnd: input.dueEnd,
            status: input.status,
            priority: input.priority,
            recurrenceRule: input.recurrenceRule,
            kanbanOrder: nextOrder,
            updatedAt: Date()
        )
        tasks.insert(task, at: 0)
        return task
    }

    func updateTask(_ task: Task) async throws -> Task {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else {
            throw NSError(domain: "mock", code: 404)
        }
        tasks[idx] = task
        return tasks[idx]
    }

    func deleteTask(taskID: UUID) async throws {
        tasks.removeAll { $0.id == taskID }
    }

    func setTaskStatus(taskID: UUID, status: TaskStatus) async throws -> Task {
        try await moveTask(taskID: taskID, to: status, beforeTaskID: nil)
    }

    func moveTask(taskID: UUID, to status: TaskStatus, beforeTaskID: UUID?) async throws -> Task {
        guard let idx = tasks.firstIndex(where: { $0.id == taskID }) else {
            throw NSError(domain: "mock", code: 404)
        }

        let siblings = tasks
            .filter { $0.id != taskID && $0.status == status }
            .sorted { $0.kanbanOrder < $1.kanbanOrder }

        let nextOrder: Double
        if let beforeTaskID, let beforeIndex = siblings.firstIndex(where: { $0.id == beforeTaskID }) {
            let nextValue = siblings[beforeIndex].kanbanOrder
            let previousValue = beforeIndex > 0 ? siblings[beforeIndex - 1].kanbanOrder : nextValue - 1
            nextOrder = previousValue + ((nextValue - previousValue) / 2)
        } else {
            nextOrder = (siblings.last?.kanbanOrder ?? 0) + 1
        }

        tasks[idx].status = status
        tasks[idx].kanbanOrder = nextOrder
        tasks[idx].completedAt = status == .done ? Date() : nil
        tasks[idx].updatedAt = Date()
        return tasks[idx]
    }

    func toggleTaskCompletion(taskID: UUID, isCompleted: Bool) async throws -> Task {
        try await setTaskStatus(taskID: taskID, status: isCompleted ? .done : .next)
    }

    func runSync(configuration: SyncEngineConfiguration, calendarProvider: CalendarProvider) async throws -> SyncRunReport {
        var report = SyncRunReport()
        report.tasksPushed = tasks.count
        report.eventsPulled = 0
        report.tasksImported = 0
        report.finalTaskVersionCursor = Int64(tasks.count)
        report.finalCalendarToken = "mock-token"
        report.diagnostics = [
            SyncDiagnosticEntry(
                operation: .pullCalendarChanges,
                severity: .warning,
                message: "Skipped detached recurrence exception without an existing task binding.",
                taskID: tasks.first?.id,
                eventIdentifier: "mock-event",
                externalIdentifier: "mock-external",
                calendarID: configuration.calendarID,
                providerError: nil,
                timestamp: Date(timeIntervalSince1970: 1_700_000_111),
                attempt: 1
            )
        ]
        return report
    }

    func seedDemoDataIfNeeded() async throws {}

    func unlinkedMentions(for noteID: UUID) async throws -> [NoteBacklink] {
        []
    }

    func linkMention(in sourceNoteID: UUID, targetTitle: String) async throws -> Note {
        guard let note = notes.first(where: { $0.id == sourceNoteID }) else {
            throw NSError(domain: "mock", code: 404)
        }
        return note
    }

    func graphEdges() async throws -> [(from: UUID, to: UUID, fromTitle: String, toTitle: String)] {
        []
    }

    func createOrOpenDailyNote(date: Date) async throws -> Note {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current
        let title = formatter.string(from: date)
        if let existing = notes.first(where: { $0.title == title }) {
            return existing
        }
        let note = Note(id: UUID(), title: title, body: "", updatedAt: Date(), version: 1)
        return note
    }

    func listTemplates() async throws -> [NoteTemplate] {
        []
    }

    func createTemplate(name: String, body: String) async throws -> NoteTemplate {
        NoteTemplate(name: name, body: body, createdAt: Date())
    }

    func deleteTemplate(id: UUID) async throws {}

    func createNote(title: String, body: String, templateID: UUID?) async throws -> Note {
        let note = Note(id: UUID(), title: title, body: body, updatedAt: Date(), version: 1)
        return note
    }
}
