import XCTest
import Foundation
@testable import NotesDomain
@testable import NotesFeatures
@testable import NotesUI
@testable import NotesSync

@MainActor
final class AppViewModelTests: XCTestCase {
    func testLoadSeedsAndSelectsFirstNote() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)

        await viewModel.load()

        XCTAssertEqual(viewModel.notes.count, 2)
        XCTAssertEqual(viewModel.selectedNoteTitle, "Alpha")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isBusy)
    }

    func testLoadFailureSetsErrorMessage() async {
        let service = WorkspaceServiceSpy()
        await service.setFailure(.seed)
        let viewModel = makeViewModel(service: service)

        await viewModel.load()

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isBusy)
    }

    func testCreateNoteSelectsCreatedNote() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        await viewModel.createNote()

        XCTAssertEqual(viewModel.notes.first?.title, "New Note")
        XCTAssertEqual(viewModel.selectedNoteTitle, "New Note")
    }

    func testSaveSelectedNoteWithoutSelectionNoCalls() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)

        await viewModel.saveSelectedNote()

        let updateCalls = await service.updateNoteCallCount
        XCTAssertEqual(updateCalls, 0)
    }

    func testSaveSelectedNotePersistsChanges() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        viewModel.selectedNoteTitle = "Alpha Updated"
        viewModel.selectedNoteBody = "Updated body"
        await viewModel.saveSelectedNote()

        let updateCalls = await service.updateNoteCallCount
        XCTAssertEqual(updateCalls, 1)
        XCTAssertEqual(viewModel.notes.first?.title, "Alpha Updated")
    }

    func testSelectNoteNilClearsEditor() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        await viewModel.selectNote(id: nil)

        XCTAssertNil(viewModel.selectedNoteID)
        XCTAssertEqual(viewModel.selectedNoteTitle, "")
        XCTAssertEqual(viewModel.selectedNoteBody, "")
        XCTAssertTrue(viewModel.backlinks.isEmpty)
    }

    func testCreateQuickTaskIgnoresEmptyTitle() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        viewModel.quickTaskTitle = "   "
        await viewModel.createQuickTask()

        let createCalls = await service.createTaskCallCount
        XCTAssertEqual(createCalls, 0)
    }

    func testCreateQuickTaskCreatesTaskAndClearsField() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        viewModel.quickTaskTitle = "Ship draft"
        await viewModel.createQuickTask()

        let createCalls = await service.createTaskCallCount
        XCTAssertEqual(createCalls, 1)
        XCTAssertEqual(viewModel.quickTaskTitle, "")
        XCTAssertTrue(viewModel.tasks.contains { $0.title == "Ship draft" })
    }

    func testSetTaskFilterReloadsTasks() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        await viewModel.setTaskFilter(.completed)

        XCTAssertEqual(viewModel.taskFilter, .completed)
        XCTAssertEqual(viewModel.tasks.count, 1)
        XCTAssertEqual(viewModel.tasks.first?.status, .done)
    }

    func testSetNoteSearchQueryFiltersAndClearsSelectionWhenMissing() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        XCTAssertEqual(viewModel.selectedNoteTitle, "Alpha")

        await viewModel.setNoteSearchQuery("beta")
        try? await _Concurrency.Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(viewModel.noteSearchQuery, "beta")
        XCTAssertEqual(viewModel.notes.count, 1)
        XCTAssertEqual(viewModel.notes.first?.title, "Beta")
        XCTAssertNil(viewModel.selectedNoteID)
        XCTAssertEqual(viewModel.selectedNoteTitle, "")
    }

    func testSetNoteSearchQueryEmptyRestoresAllNotes() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        await viewModel.setNoteSearchQuery("alpha")
        try? await _Concurrency.Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(viewModel.notes.count, 1)

        await viewModel.setNoteSearchQuery("")
        try? await _Concurrency.Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(viewModel.noteSearchQuery, "")
        XCTAssertEqual(viewModel.notes.count, 2)
    }

    func testWikiLinkAutocompleteSuggestsAndAppliesReplacement() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        viewModel.updateSelectedNoteBody("Linking to [[be")
        XCTAssertTrue(viewModel.isWikiLinkSuggestionVisible)
        XCTAssertTrue(viewModel.wikiLinkSuggestions.contains("Beta"))

        viewModel.applyWikiLinkSuggestion("Beta")
        XCTAssertEqual(viewModel.selectedNoteBody, "Linking to [[Beta]]")
        XCTAssertFalse(viewModel.isWikiLinkSuggestionVisible)
    }

    func testQuickOpenFiltersAndSelectsNote() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        viewModel.openQuickSwitcher()
        XCTAssertTrue(viewModel.isQuickOpenPresented)
        XCTAssertEqual(viewModel.quickOpenResults.count, 2)

        viewModel.setQuickOpenQuery("beta")
        XCTAssertEqual(viewModel.quickOpenResults.map(\.title), ["Beta"])

        guard let target = viewModel.quickOpenResults.first else {
            return XCTFail("Expected quick open match")
        }
        await viewModel.selectQuickOpenResult(noteID: target.id)

        XCTAssertFalse(viewModel.isQuickOpenPresented)
        XCTAssertEqual(viewModel.selectedNoteID, target.id)
    }

    func testMarkdownInsertActionsAppendExpectedPrefixes() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        viewModel.updateSelectedNoteBody("Start")

        viewModel.insertMarkdownHeading()
        XCTAssertTrue(viewModel.selectedNoteBody.contains("\n# "))

        viewModel.insertMarkdownBullet()
        XCTAssertTrue(viewModel.selectedNoteBody.contains("\n- "))

        viewModel.insertMarkdownCheckbox()
        XCTAssertTrue(viewModel.selectedNoteBody.contains("\n- [ ] "))
    }

    func testSetNoteSearchQueryStoresSnippetsAndClearsWhenReset() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        await viewModel.setNoteSearchQuery("alpha")
        try? await _Concurrency.Task.sleep(for: .milliseconds(400))
        guard let firstID = viewModel.notes.first?.id else {
            return XCTFail("Expected at least one note")
        }
        XCTAssertNotNil(viewModel.noteSearchSnippet(for: firstID))

        await viewModel.setNoteSearchQuery("")
        try? await _Concurrency.Task.sleep(for: .milliseconds(400))
        XCTAssertNil(viewModel.noteSearchSnippet(for: firstID))
    }

    func testHandleTaskDropMovesTaskToTargetStatus() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let task = viewModel.tasks.first(where: { $0.status == .backlog }) else {
            return XCTFail("Missing backlog task")
        }

        viewModel.beginTaskDrag(taskID: task.id)
        let moved = await viewModel.handleTaskDrop(taskPayloads: [task.id.uuidString], to: .waiting, beforeTaskID: nil)
        XCTAssertTrue(moved)
        XCTAssertNil(viewModel.draggingTaskID)
        XCTAssertNil(viewModel.dropTargetStatus)
        XCTAssertNil(viewModel.dropTargetTaskID)

        await viewModel.setTaskFilter(.all)
        XCTAssertTrue(viewModel.tasks.contains(where: { $0.id == task.id && $0.status == .waiting }))
    }

    func testHandleTaskDropRejectsInvalidPayload() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        let moved = await viewModel.handleTaskDrop(taskPayloads: ["not-a-uuid"], to: .doing, beforeTaskID: nil)
        XCTAssertFalse(moved)
    }

    func testHandleTaskDropReturnsFalseWhenTaskMissingFromViewModel() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        let moved = await viewModel.handleTaskDrop(taskPayloads: [UUID().uuidString], to: .doing, beforeTaskID: nil)
        XCTAssertFalse(moved)
    }

    func testPerformTaskDropRejectsInvalidPayload() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        XCTAssertFalse(viewModel.performTaskDrop(taskPayloads: ["bad-payload"], to: .doing, beforeTaskID: nil))
    }

    func testPerformTaskDropReturnsFalseWhenTaskMissing() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        XCTAssertFalse(viewModel.performTaskDrop(taskPayloads: [UUID().uuidString], to: .doing, beforeTaskID: nil))
    }

    func testPerformTaskDropReturnsTrueForNoOpSelfDrop() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let backlog = viewModel.tasks.first(where: { $0.stableID == "t-backlog-a" }) else {
            return XCTFail("Missing backlog fixture")
        }

        XCTAssertTrue(viewModel.performTaskDrop(taskPayloads: [backlog.id.uuidString], to: .backlog, beforeTaskID: backlog.id))
    }

    func testPerformTaskDropDetachedOccurrenceShowsPromptAndReturnsFalse() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let detached = viewModel.tasks.first(where: { TaskCalendarMapper.recurrenceExceptionDate(in: $0.details) != nil }) else {
            return XCTFail("Missing detached occurrence fixture")
        }

        let accepted = viewModel.performTaskDrop(
            taskPayloads: [detached.id.uuidString],
            to: .doing,
            beforeTaskID: nil
        )
        XCTAssertFalse(accepted)
        XCTAssertNotNil(viewModel.recurrenceEditPrompt)
    }

    func testPerformTaskDropQueuesMoveAndClearsDragTargets() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let backlog = viewModel.tasks.first(where: { $0.stableID == "t-backlog-a" }) else {
            return XCTFail("Missing backlog fixture")
        }

        viewModel.beginTaskDrag(taskID: backlog.id)
        viewModel.setDropTargetStatus(.waiting)
        viewModel.setDropTargetTaskID(backlog.id)

        let accepted = viewModel.performTaskDrop(
            taskPayloads: [backlog.id.uuidString],
            to: .waiting,
            beforeTaskID: nil
        )
        XCTAssertTrue(accepted)
        XCTAssertNil(viewModel.draggingTaskID)
        XCTAssertNil(viewModel.dropTargetStatus)
        XCTAssertNil(viewModel.dropTargetTaskID)

        try? await _Concurrency.Task.sleep(nanoseconds: 120_000_000)
        XCTAssertTrue(viewModel.tasks(for: .waiting).contains { $0.id == backlog.id })
    }

    func testHandleTaskDropSameStatusWithoutBeforeIsNoOpWhenAlreadyLastInColumn() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let backlogB = viewModel.tasks.first(where: { $0.stableID == "t-backlog-b" }) else {
            return XCTFail("Missing backlog fixture")
        }

        let before = viewModel.tasks(for: .backlog).map(\.stableID)
        let moved = await viewModel.handleTaskDrop(
            taskPayloads: [backlogB.id.uuidString],
            to: .backlog,
            beforeTaskID: nil
        )
        XCTAssertTrue(moved)
        XCTAssertNil(viewModel.errorMessage)
        let after = viewModel.tasks(for: .backlog).map(\.stableID)
        XCTAssertEqual(after, before)
    }

    func testHandleTaskDropReordersWithinSameColumn() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard
            let backlogA = viewModel.tasks.first(where: { $0.stableID == "t-backlog-a" }),
            let backlogB = viewModel.tasks.first(where: { $0.stableID == "t-backlog-b" })
        else {
            return XCTFail("Missing backlog fixtures")
        }

        let before = viewModel.tasks(for: .backlog).map(\.stableID)
        XCTAssertEqual(before, ["t-backlog-a", "t-backlog-b"])

        viewModel.beginTaskDrag(taskID: backlogB.id)
        let moved = await viewModel.handleTaskDrop(
            taskPayloads: [backlogB.id.uuidString],
            to: .backlog,
            beforeTaskID: backlogA.id
        )
        XCTAssertTrue(moved)

        let after = viewModel.tasks(for: .backlog).map(\.stableID)
        XCTAssertEqual(after, ["t-backlog-b", "t-backlog-a"])
    }

    func testKanbanDropMatrixReordersTopMiddleBottomWithinSameColumn() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard
            let backlogA = viewModel.tasks.first(where: { $0.stableID == "t-backlog-a" }),
            let backlogB = viewModel.tasks.first(where: { $0.stableID == "t-backlog-b" }),
            let next = viewModel.tasks.first(where: { $0.stableID == "t-next" })
        else {
            return XCTFail("Missing fixtures")
        }

        // Build three cards in one column to validate top/middle/bottom placements.
        await viewModel.moveTask(taskID: next.id, to: .backlog)
        XCTAssertEqual(viewModel.tasks(for: .backlog).map(\.stableID), ["t-backlog-a", "t-backlog-b", "t-next"])

        // Top: move the last card before the current top card.
        let topMoved = await viewModel.handleTaskDrop(
            taskPayloads: [next.id.uuidString],
            to: .backlog,
            beforeTaskID: backlogA.id
        )
        XCTAssertTrue(topMoved)
        XCTAssertEqual(viewModel.tasks(for: .backlog).map(\.stableID), ["t-next", "t-backlog-a", "t-backlog-b"])

        // Middle: move bottom card before the current middle card.
        let middleMoved = await viewModel.handleTaskDrop(
            taskPayloads: [backlogB.id.uuidString],
            to: .backlog,
            beforeTaskID: backlogA.id
        )
        XCTAssertTrue(middleMoved)
        XCTAssertEqual(viewModel.tasks(for: .backlog).map(\.stableID), ["t-next", "t-backlog-b", "t-backlog-a"])

        // Bottom: drop top card on column body (beforeTaskID=nil) to move it to end.
        let bottomMoved = await viewModel.handleTaskDrop(
            taskPayloads: [next.id.uuidString],
            to: .backlog,
            beforeTaskID: nil
        )
        XCTAssertTrue(bottomMoved)
        XCTAssertEqual(viewModel.tasks(for: .backlog).map(\.stableID), ["t-backlog-b", "t-backlog-a", "t-next"])
    }

    func testKanbanDropToEmptyColumnAndCrossColumnRelativeOrder() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard
            let backlogA = viewModel.tasks.first(where: { $0.stableID == "t-backlog-a" }),
            let backlogB = viewModel.tasks.first(where: { $0.stableID == "t-backlog-b" })
        else {
            return XCTFail("Missing backlog fixtures")
        }

        // Waiting starts empty in fixtures; first drop validates empty-column handling.
        let firstMove = await viewModel.handleTaskDrop(
            taskPayloads: [backlogA.id.uuidString],
            to: .waiting,
            beforeTaskID: nil
        )
        XCTAssertTrue(firstMove)
        XCTAssertEqual(viewModel.tasks(for: .waiting).map(\.stableID), ["t-backlog-a"])

        // Second drop into same target column should preserve relative order.
        let secondMove = await viewModel.handleTaskDrop(
            taskPayloads: [backlogB.id.uuidString],
            to: .waiting,
            beforeTaskID: nil
        )
        XCTAssertTrue(secondMove)
        XCTAssertEqual(viewModel.tasks(for: .waiting).map(\.stableID), ["t-backlog-a", "t-backlog-b"])
    }

    func testKanbanRapidRepeatedDragActionsRemainDeterministic() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let backlogA = viewModel.tasks.first(where: { $0.stableID == "t-backlog-a" }) else {
            return XCTFail("Missing backlog fixture")
        }

        for _ in 0..<20 {
            let movedToNext = await viewModel.handleTaskDrop(
                taskPayloads: [backlogA.id.uuidString],
                to: .next,
                beforeTaskID: nil
            )
            XCTAssertTrue(movedToNext)

            let movedToDoing = await viewModel.handleTaskDrop(
                taskPayloads: [backlogA.id.uuidString],
                to: .doing,
                beforeTaskID: nil
            )
            XCTAssertTrue(movedToDoing)

            let movedToBacklog = await viewModel.handleTaskDrop(
                taskPayloads: [backlogA.id.uuidString],
                to: .backlog,
                beforeTaskID: nil
            )
            XCTAssertTrue(movedToBacklog)
        }

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.tasks.filter { $0.id == backlogA.id }.count, 1)
        XCTAssertEqual(viewModel.tasks.first(where: { $0.id == backlogA.id })?.status, .backlog)
    }

    func testToggleTaskCompletionUpdatesTaskState() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        guard let first = viewModel.tasks.first else {
            return XCTFail("Missing task")
        }

        await viewModel.toggleTaskCompletion(taskID: first.id, isCompleted: true)
        await viewModel.setTaskFilter(.completed)

        XCTAssertTrue(viewModel.tasks.contains { $0.id == first.id && $0.status == .done })
    }

    func testMoveTaskUpdatesStatus() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        guard let first = viewModel.tasks.first else {
            return XCTFail("Missing task")
        }

        await viewModel.moveTask(taskID: first.id, to: .waiting)
        await viewModel.setTaskFilter(.all)

        XCTAssertTrue(viewModel.tasks.contains { $0.id == first.id && $0.status == .waiting })
    }

    func testKanbanDoneColumnRetainsMovedTaskWhenListFilterIsAll() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let first = viewModel.tasks.first(where: { $0.status == .backlog }) else {
            return XCTFail("Missing backlog task")
        }

        await viewModel.moveTask(taskID: first.id, to: .done)
        await viewModel.setTaskFilter(.all)

        XCTAssertFalse(viewModel.tasks.contains { $0.id == first.id })
        XCTAssertTrue(viewModel.tasks(for: .done).contains { $0.id == first.id })
    }

    func testMoveTaskDetachedOccurrenceRequiresScopeSelection() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        guard let detached = viewModel.tasks.first(where: { TaskCalendarMapper.recurrenceExceptionDate(in: $0.details) != nil }) else {
            return XCTFail("Missing detached occurrence fixture")
        }

        await viewModel.moveTask(taskID: detached.id, to: .doing)

        XCTAssertNotNil(viewModel.recurrenceEditPrompt)
        XCTAssertEqual(viewModel.tasks.first(where: { $0.id == detached.id })?.status, .next)

        await viewModel.resolveRecurrenceEditPrompt(scope: .thisOccurrence)

        XCTAssertNil(viewModel.recurrenceEditPrompt)
        XCTAssertEqual(viewModel.tasks.first(where: { $0.id == detached.id })?.status, .doing)
    }

    func testDismissRecurrenceEditPromptClearsPendingMutationAndResolveNoops() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        guard let detached = viewModel.tasks.first(where: { TaskCalendarMapper.recurrenceExceptionDate(in: $0.details) != nil }) else {
            return XCTFail("Missing detached occurrence fixture")
        }

        await viewModel.moveTask(taskID: detached.id, to: .doing)
        XCTAssertNotNil(viewModel.recurrenceEditPrompt)

        viewModel.dismissRecurrenceEditPrompt()
        XCTAssertNil(viewModel.recurrenceEditPrompt)

        await viewModel.resolveRecurrenceEditPrompt(scope: .thisOccurrence)
        XCTAssertEqual(viewModel.tasks.first(where: { $0.id == detached.id })?.status, .next)
    }

    func testMoveTaskIgnoresMissingTaskID() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        await viewModel.moveTask(taskID: UUID(), to: .doing)

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.recurrenceEditPrompt)
    }

    func testHandleTaskDropDetachedOccurrenceReturnsFalseUntilScopeResolved() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let detached = viewModel.tasks.first(where: { TaskCalendarMapper.recurrenceExceptionDate(in: $0.details) != nil }) else {
            return XCTFail("Missing detached occurrence fixture")
        }

        let moved = await viewModel.handleTaskDrop(
            taskPayloads: [detached.id.uuidString],
            to: .doing,
            beforeTaskID: nil
        )
        XCTAssertFalse(moved)
        XCTAssertNotNil(viewModel.recurrenceEditPrompt)

        await viewModel.resolveRecurrenceEditPrompt(scope: .thisOccurrence)
        XCTAssertEqual(viewModel.tasks.first(where: { $0.id == detached.id })?.status, .doing)
    }

    func testResolveRecurrenceEditPromptEntireSeriesStripsExceptionMarker() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        guard let detached = viewModel.tasks.first(where: { TaskCalendarMapper.recurrenceExceptionDate(in: $0.details) != nil }) else {
            return XCTFail("Missing detached occurrence fixture")
        }

        await viewModel.moveTask(taskID: detached.id, to: .waiting)
        XCTAssertNotNil(viewModel.recurrenceEditPrompt)

        await viewModel.resolveRecurrenceEditPrompt(scope: .entireSeries)

        guard let updated = viewModel.tasks.first(where: { $0.id == detached.id }) else {
            return XCTFail("Missing updated detached task")
        }
        XCTAssertEqual(updated.status, .waiting)
        XCTAssertFalse(updated.details.contains("event-recurrence-exception:"))

        let sharedSeries = viewModel.tasks.filter { $0.stableID == "t-series-shared" }
        XCTAssertEqual(sharedSeries.count, 2)
        XCTAssertTrue(sharedSeries.allSatisfy { $0.status == .waiting })
    }

    func testResolveRecurrenceEditPromptEntireSeriesWithoutAnchorShowsError() async {
        let service = WorkspaceServiceSpy()
        await service.clearSeriesAnchorRecurrenceRule(stableID: "t-series-shared")
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        guard let detached = viewModel.tasks.first(where: { TaskCalendarMapper.recurrenceExceptionDate(in: $0.details) != nil }) else {
            return XCTFail("Missing detached occurrence fixture")
        }

        await viewModel.moveTask(taskID: detached.id, to: .waiting)
        XCTAssertNotNil(viewModel.recurrenceEditPrompt)

        await viewModel.resolveRecurrenceEditPrompt(scope: .entireSeries)
        XCTAssertEqual(viewModel.errorMessage, "Could not resolve a parent recurring series for this occurrence.")
    }

    func testDeleteTaskRemovesTaskWithoutPromptWhenNotDetached() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let task = viewModel.tasks.first(where: { $0.stableID == "t-backlog-a" }) else {
            return XCTFail("Missing non-detached task")
        }

        await viewModel.deleteTask(taskID: task.id)

        XCTAssertNil(viewModel.recurrenceDeletePrompt)
        XCTAssertFalse(viewModel.tasks.contains(where: { $0.id == task.id }))
    }

    func testDeleteTaskDetachedOccurrenceRequiresScopeAndDeletesAfterResolve() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let detached = viewModel.tasks.first(where: { TaskCalendarMapper.recurrenceExceptionDate(in: $0.details) != nil }) else {
            return XCTFail("Missing detached occurrence fixture")
        }

        await viewModel.deleteTask(taskID: detached.id)
        XCTAssertNotNil(viewModel.recurrenceDeletePrompt)
        XCTAssertTrue(viewModel.tasks.contains(where: { $0.id == detached.id }))

        await viewModel.resolveRecurrenceDeletePrompt(scope: .thisOccurrence)
        XCTAssertFalse(viewModel.tasks.contains(where: { $0.id == detached.id }))
    }

    func testDeleteTaskEntireSeriesClearsExceptionMarkerBeforeDelete() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let detached = viewModel.tasks.first(where: { TaskCalendarMapper.recurrenceExceptionDate(in: $0.details) != nil }) else {
            return XCTFail("Missing detached occurrence fixture")
        }

        await viewModel.deleteTask(taskID: detached.id)
        await viewModel.resolveRecurrenceDeletePrompt(scope: .entireSeries)

        let updateTaskCalls = await service.updateTaskCallCount
        let deleteTaskCalls = await service.deleteTaskCallCount
        XCTAssertEqual(updateTaskCalls, 0)
        XCTAssertEqual(deleteTaskCalls, 2)
        XCTAssertFalse(viewModel.tasks.contains(where: { $0.stableID == detached.stableID }))
    }

    func testTasksForDoneReturnsOnlyDone() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        let done = viewModel.tasks(for: .done)
        let backlog = viewModel.tasks(for: .backlog)

        XCTAssertTrue(done.allSatisfy { $0.status == .done })
        XCTAssertTrue(backlog.allSatisfy { $0.status == .backlog })
    }

    func testTasksForDoneWhenCompletedFilterLoadedUsesDoneBranch() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.completed)

        let done = viewModel.tasks(for: .done)
        XCTAssertFalse(done.isEmpty)
        XCTAssertTrue(done.allSatisfy { $0.status == .done })
    }

    func testDropTargetSettersAndEndTaskDragResetState() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        viewModel.beginTaskDrag(taskID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
        viewModel.setDropTargetStatus(.waiting)
        viewModel.setDropTargetTaskID(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))

        XCTAssertNotNil(viewModel.draggingTaskID)
        XCTAssertEqual(viewModel.dropTargetStatus, .waiting)
        XCTAssertNotNil(viewModel.dropTargetTaskID)

        viewModel.endTaskDrag()
        XCTAssertNil(viewModel.draggingTaskID)
        XCTAssertNil(viewModel.dropTargetStatus)
        XCTAssertNil(viewModel.dropTargetTaskID)
    }

    func testRunSyncWithoutCalendarShowsValidationError() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        viewModel.syncCalendarID = "  "
        await viewModel.runSync()

        XCTAssertEqual(viewModel.errorMessage, "Calendar ID is required before syncing.")
        XCTAssertFalse(viewModel.isSyncing)
    }

    func testRunSyncSuccessStoresReport() async {
        let service = WorkspaceServiceSpy()
        let provider = InMemoryCalendarProvider()
        let viewModel = AppViewModel(service: service, calendarProviderFactory: { provider }, syncCalendarID: "cal")
        await viewModel.load()

        await viewModel.runSync()

        XCTAssertNotNil(viewModel.lastSyncReport)
        XCTAssertTrue(viewModel.syncStatusText.contains("Sync complete"))
        XCTAssertFalse(viewModel.isSyncing)
    }

    func testRunSyncSurfacesRecurrenceConflictMessage() async {
        let service = WorkspaceServiceSpy()
        let provider = InMemoryCalendarProvider()
        let viewModel = AppViewModel(service: service, calendarProviderFactory: { provider }, syncCalendarID: "cal")
        await viewModel.load()

        await viewModel.runSync()

        XCTAssertNotNil(viewModel.recurrenceConflictMessage)
        XCTAssertTrue(viewModel.recurrenceConflictMessage?.localizedCaseInsensitiveContains("detached recurrence exception") == true)
    }

    func testRunSyncClearsRecurrenceConflictWhenDetachedDiagnosticMissing() async {
        let service = WorkspaceServiceSpy()
        let provider = InMemoryCalendarProvider()
        let viewModel = AppViewModel(service: service, calendarProviderFactory: { provider }, syncCalendarID: "cal")
        await viewModel.load()

        await viewModel.runSync()
        XCTAssertNotNil(viewModel.recurrenceConflictMessage)

        await service.setIncludeDetachedDiagnostic(false)
        await viewModel.runSync()
        XCTAssertNil(viewModel.recurrenceConflictMessage)
    }

    func testRunSyncFailureSetsErrorAndStopsSync() async {
        let service = WorkspaceServiceSpy()
        await service.setFailure(.sync)
        let provider = InMemoryCalendarProvider()
        let viewModel = AppViewModel(service: service, calendarProviderFactory: { provider }, syncCalendarID: "cal")
        await viewModel.load()

        await viewModel.runSync()

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isSyncing)
    }

    func testExportSyncDiagnosticsFailsWhenNoReport() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        await viewModel.exportSyncDiagnostics()

        XCTAssertEqual(viewModel.errorMessage, "Run sync before exporting diagnostics.")
        XCTAssertNil(viewModel.lastDiagnosticsExportURL)
    }

    func testExportSyncDiagnosticsWritesFileAfterSync() async throws {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.runSync()

        await viewModel.exportSyncDiagnostics()

        guard let exportURL = viewModel.lastDiagnosticsExportURL else {
            return XCTFail("Expected diagnostics export URL")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
        XCTAssertTrue(viewModel.lastDiagnosticsExportText.contains("NotesEngine Sync Diagnostics"))
        XCTAssertTrue(viewModel.lastDiagnosticsExportText.contains("provider timeout"))
        XCTAssertTrue(viewModel.syncStatusText.contains("Diagnostics exported to"))
    }

    func testExportSyncDiagnosticsFailsWhenLastReportHasNoDiagnostics() async {
        let service = WorkspaceServiceSpy()
        await service.setIncludeDiagnostics(false)
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.runSync()

        await viewModel.exportSyncDiagnostics()

        XCTAssertEqual(viewModel.errorMessage, "No diagnostics available to export.")
        XCTAssertNil(viewModel.lastDiagnosticsExportURL)
    }

    func testNavigateToNoteByTitleSelectsCorrectNote() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        await viewModel.navigateToNoteByTitle("Beta")

        XCTAssertEqual(viewModel.selectedNoteTitle, "Beta")
    }

    func testNavigateToNoteByTitleIsCaseInsensitive() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        await viewModel.navigateToNoteByTitle("beta")

        XCTAssertEqual(viewModel.selectedNoteTitle, "Beta")
    }

    func testNavigateToNoteByTitleNoMatchIsNoOp() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        let originalTitle = viewModel.selectedNoteTitle

        await viewModel.navigateToNoteByTitle("Nonexistent")

        XCTAssertEqual(viewModel.selectedNoteTitle, originalTitle)
    }

    func testNavigateToNoteByTitleSwitchesToEditMode() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        viewModel.toggleNoteEditMode()
        XCTAssertEqual(viewModel.noteEditMode, .preview)

        await viewModel.navigateToNoteByTitle("Beta")

        XCTAssertEqual(viewModel.noteEditMode, .edit)
    }

    func testToggleSwitchesToPreviewMode() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        viewModel.toggleNoteEditMode()

        XCTAssertEqual(viewModel.noteEditMode, .preview)
        XCTAssertFalse(viewModel.renderedMarkdown.characters.isEmpty || viewModel.selectedNoteBody.isEmpty)
    }

    func testToggleRoundTrips() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        viewModel.toggleNoteEditMode()
        XCTAssertEqual(viewModel.noteEditMode, .preview)

        viewModel.toggleNoteEditMode()
        XCTAssertEqual(viewModel.noteEditMode, .edit)
    }

    func testSelectNoteResetsToEditMode() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        viewModel.toggleNoteEditMode()
        XCTAssertEqual(viewModel.noteEditMode, .preview)

        await viewModel.selectNote(id: viewModel.notes.last?.id)
        XCTAssertEqual(viewModel.noteEditMode, .edit)
    }

    func testFilterByTagFiltersNotesList() async {
        let service = WorkspaceServiceSpy()
        await service.addTaggedNote(title: "Swift Note", body: "Content", tags: ["swift"])
        await service.addTaggedNote(title: "Rust Note", body: "Content", tags: ["rust"])
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        await viewModel.filterByTag("swift")

        XCTAssertEqual(viewModel.selectedTagFilter, "swift")
        XCTAssertTrue(viewModel.notes.allSatisfy { $0.tags.contains("swift") })
    }

    func testClearTagFilterRestoresFullList() async {
        let service = WorkspaceServiceSpy()
        await service.addTaggedNote(title: "Swift Note", body: "Content", tags: ["swift"])
        await service.addTaggedNote(title: "Rust Note", body: "Content", tags: ["rust"])
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        await viewModel.filterByTag("swift")
        await viewModel.filterByTag(nil)

        XCTAssertNil(viewModel.selectedTagFilter)
        XCTAssertGreaterThanOrEqual(viewModel.notes.count, 2)
    }

    func testAllTagsLoadedOnLoad() async {
        let service = WorkspaceServiceSpy()
        await service.addTaggedNote(title: "Note", body: "Content", tags: ["alpha", "beta"])
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        XCTAssertTrue(viewModel.allTagsList.contains("alpha"))
        XCTAssertTrue(viewModel.allTagsList.contains("beta"))
    }

    // MARK: - Daily Notes

    func testOpenDailyNoteSelectsDailyNote() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        viewModel.noteSearchQuery = "Alpha"

        await viewModel.openDailyNote()

        XCTAssertEqual(viewModel.noteSearchQuery, "")
        XCTAssertNotNil(viewModel.selectedNoteID)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current
        let todayTitle = formatter.string(from: Date())
        XCTAssertEqual(viewModel.selectedNoteTitle, todayTitle)
        XCTAssertTrue(viewModel.notes.contains(where: { $0.title == todayTitle }))
    }

    func testOpenDailyNoteIdempotent() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        await viewModel.openDailyNote()
        let firstID = viewModel.selectedNoteID
        let countAfterFirst = viewModel.notes.count

        await viewModel.openDailyNote()
        let secondID = viewModel.selectedNoteID

        XCTAssertEqual(firstID, secondID)
        XCTAssertEqual(viewModel.notes.count, countAfterFirst)
    }

    // MARK: - Link Mentions

    func testLinkMentionGuardsEmptyTitle() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.selectNote(id: nil)

        let alphaID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        await viewModel.linkMention(sourceNoteID: alphaID)

        XCTAssertTrue(viewModel.selectedNoteTitle.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLinkMentionUpdatesUnlinkedMentions() async {
        let service = WorkspaceServiceSpy()
        let alphaID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let betaID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        await service.setStubbedUnlinkedMentions([
            NoteBacklink(sourceNoteID: betaID, sourceTitle: "Beta")
        ])
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.selectNote(id: alphaID)

        await viewModel.linkMention(sourceNoteID: betaID)

        XCTAssertEqual(viewModel.unlinkedMentions.count, 1)
        XCTAssertEqual(viewModel.unlinkedMentions.first?.sourceTitle, "Beta")
    }

    // MARK: - Graph View

    func testReloadGraphPopulatesNodesAndEdges() async {
        let service = WorkspaceServiceSpy()
        await service.addTaggedNote(title: "Gamma", body: "", tags: [])
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        await viewModel.reloadGraph()

        XCTAssertGreaterThanOrEqual(viewModel.graphNodes.count, 3)
        XCTAssertEqual(viewModel.graphEdges.count, 1)
    }

    func testReloadGraphEmptyWhenNoLinks() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        await viewModel.reloadGraph()

        XCTAssertGreaterThanOrEqual(viewModel.graphNodes.count, 2)
        XCTAssertEqual(viewModel.graphEdges.count, 0)
    }

    // MARK: - Templates

    func testCreateNoteFromTemplateClearsStateAndSelects() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        viewModel.noteSearchQuery = "search"
        viewModel.isTemplatePickerPresented = true

        await viewModel.createNoteFromTemplate(templateID: UUID())

        XCTAssertEqual(viewModel.noteSearchQuery, "")
        XCTAssertFalse(viewModel.isTemplatePickerPresented)
        XCTAssertEqual(viewModel.selectedNoteTitle, "New Note")
    }

    func testCreateTemplateGuardsEmptyName() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        viewModel.newTemplateName = "   "
        viewModel.newTemplateBody = "body"

        await viewModel.createTemplate()

        XCTAssertEqual(viewModel.newTemplateName, "   ")
        XCTAssertEqual(viewModel.newTemplateBody, "body")
        XCTAssertTrue(viewModel.templates.isEmpty)
    }

    func testCreateTemplateClearsFormAndReloads() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        viewModel.newTemplateName = "Meeting Notes"
        viewModel.newTemplateBody = "## Agenda\n- "

        await viewModel.createTemplate()

        XCTAssertEqual(viewModel.newTemplateName, "")
        XCTAssertEqual(viewModel.newTemplateBody, "")
        XCTAssertEqual(viewModel.templates.count, 1)
        XCTAssertEqual(viewModel.templates.first?.name, "Meeting Notes")
    }

    func testDeleteTemplateReloadsTemplates() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        viewModel.newTemplateName = "Temp"
        viewModel.newTemplateBody = "body"
        await viewModel.createTemplate()
        let templateID = viewModel.templates.first!.id

        await viewModel.deleteTemplate(id: templateID)

        XCTAssertTrue(viewModel.templates.isEmpty)
    }

    private func makeViewModel(service: WorkspaceServiceSpy) -> AppViewModel {
        let provider = InMemoryCalendarProvider()
        return AppViewModel(service: service, calendarProviderFactory: { provider }, syncCalendarID: "cal")
    }
}

private actor WorkspaceServiceSpy: WorkspaceServicing {
    enum FailureMode {
        case seed
        case sync
    }

    private var failure: FailureMode?
    private var includeDiagnostics: Bool = true
    private var includeDetachedDiagnostic: Bool = true

    private(set) var updateNoteCallCount: Int = 0
    private(set) var updateTaskCallCount: Int = 0
    private(set) var deleteTaskCallCount: Int = 0
    private(set) var createTaskCallCount: Int = 0

    private var notes: [Note]
    private var tasks: [Task]
    private var templates: [NoteTemplate] = []
    private var stubbedUnlinkedMentions: [NoteBacklink] = []

    init() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        notes = [
            Note(id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!, title: "Alpha", body: "[[Gamma]]", updatedAt: now, version: 1),
            Note(id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!, title: "Beta", body: "", updatedAt: now, version: 1)
        ]

        tasks = [
            try! Task(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, noteID: notes[0].id, stableID: "t-backlog-a", title: "Backlog A", status: .backlog, kanbanOrder: 1, updatedAt: now),
            try! Task(id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!, noteID: notes[0].id, stableID: "t-backlog-b", title: "Backlog B", status: .backlog, kanbanOrder: 2, updatedAt: now),
            try! Task(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, noteID: notes[0].id, stableID: "t-next", title: "Next", dueStart: now.addingTimeInterval(3600), dueEnd: now.addingTimeInterval(7200), status: .next, kanbanOrder: 1, updatedAt: now),
            try! Task(id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!, noteID: notes[0].id, stableID: "t-series-shared", title: "Series parent", details: "", dueStart: now.addingTimeInterval(5000), dueEnd: now.addingTimeInterval(8600), status: .next, recurrenceRule: "FREQ=WEEKLY;BYDAY=MO", kanbanOrder: 2, updatedAt: now),
            try! Task(id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!, noteID: notes[0].id, stableID: "t-series-shared", title: "Detached occurrence", details: "event-recurrence-exception:1700000123", dueStart: now.addingTimeInterval(5400), dueEnd: now.addingTimeInterval(9000), status: .next, recurrenceRule: "FREQ=WEEKLY;BYDAY=MO", kanbanOrder: 3, updatedAt: now),
            try! Task(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, noteID: notes[0].id, stableID: "t-done", title: "Done", status: .done, kanbanOrder: 1, completedAt: now, updatedAt: now)
        ]
    }

    func addTaggedNote(title: String, body: String, tags: [String]) {
        let note = Note(id: UUID(), title: title, body: body, tags: tags, updatedAt: Date(), version: 1)
        notes.insert(note, at: 0)
    }

    func setFailure(_ mode: FailureMode?) {
        self.failure = mode
    }

    func setIncludeDiagnostics(_ include: Bool) {
        includeDiagnostics = include
    }

    func setIncludeDetachedDiagnostic(_ include: Bool) {
        includeDetachedDiagnostic = include
    }

    func setStubbedUnlinkedMentions(_ mentions: [NoteBacklink]) {
        stubbedUnlinkedMentions = mentions
    }

    func clearSeriesAnchorRecurrenceRule(stableID: String) {
        for idx in tasks.indices where tasks[idx].stableID == stableID {
            if TaskCalendarMapper.recurrenceExceptionDate(in: tasks[idx].details) == nil {
                tasks[idx].recurrenceRule = nil
            }
        }
    }

    func fetchNote(id: UUID) async throws -> Note? {
        notes.first { $0.id == id }
    }

    func listNotes() async throws -> [Note] {
        notes.sorted { $0.updatedAt > $1.updatedAt }
    }

    func searchNotes(query: String, limit: Int) async throws -> [Note] {
        let page = try await searchNotesPage(query: query, mode: .smart, limit: limit, offset: 0)
        return page.hits.map(\.note)
    }

    func searchNotesPage(query: String, mode: NoteSearchMode, limit: Int, offset: Int) async throws -> NoteSearchPage {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLimit = max(1, limit)
        let normalizedOffset = max(0, offset)
        guard !normalized.isEmpty else {
            let all = try await listNotes()
            let start = min(normalizedOffset, all.count)
            let end = min(all.count, start + normalizedLimit)
            return NoteSearchPage(
                query: normalized,
                mode: mode,
                offset: normalizedOffset,
                limit: normalizedLimit,
                totalCount: all.count,
                hits: Array(all[start..<end]).map { NoteSearchHit(note: $0, snippet: nil, rank: 0) }
            )
        }

        let filtered = notes
            .filter { $0.title.localizedCaseInsensitiveContains(normalized) || $0.body.localizedCaseInsensitiveContains(normalized) }
            .sorted { $0.updatedAt > $1.updatedAt }

        let start = min(normalizedOffset, filtered.count)
        let end = min(filtered.count, start + normalizedLimit)
        let hits = Array(filtered[start..<end]).map { note in
            NoteSearchHit(note: note, snippet: "<mark>\(normalized)</mark> in \(note.title)", rank: 0)
        }
        return NoteSearchPage(
            query: normalized,
            mode: mode,
            offset: normalizedOffset,
            limit: normalizedLimit,
            totalCount: filtered.count,
            hits: hits
        )
    }

    func createNote(title: String, body: String) async throws -> Note {
        let note = Note(id: UUID(), title: title, body: body, updatedAt: Date(), version: 1)
        notes.insert(note, at: 0)
        return note
    }

    func updateNote(id: UUID, title: String, body: String) async throws -> Note {
        updateNoteCallCount += 1
        guard let idx = notes.firstIndex(where: { $0.id == id }) else {
            throw NSError(domain: "workspace-spy", code: 404)
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
        switch filter {
        case .all:
            return tasks.filter { $0.status != .done }
        case .today:
            return tasks.filter { $0.status != .done && $0.dueStart != nil }
        case .upcoming:
            return []
        case .overdue:
            return []
        case .completed:
            return tasks.filter { $0.status == .done }
        }
    }

    func listAllTasks() async throws -> [Task] {
        tasks
    }

    func createTask(_ input: NewTaskInput) async throws -> Task {
        createTaskCallCount += 1
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
            updatedAt: Date()
        )
        tasks.insert(task, at: 0)
        return task
    }

    func updateTask(_ task: Task) async throws -> Task {
        updateTaskCallCount += 1
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else {
            throw NSError(domain: "workspace-spy", code: 404)
        }
        tasks[idx] = task
        return tasks[idx]
    }

    func deleteTask(taskID: UUID) async throws {
        deleteTaskCallCount += 1
        tasks.removeAll { $0.id == taskID }
    }

    func setTaskStatus(taskID: UUID, status: TaskStatus) async throws -> Task {
        try await moveTask(taskID: taskID, to: status, beforeTaskID: nil)
    }

    func moveTask(taskID: UUID, to status: TaskStatus, beforeTaskID: UUID?) async throws -> Task {
        guard let idx = tasks.firstIndex(where: { $0.id == taskID }) else {
            throw NSError(domain: "workspace-spy", code: 404)
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
        if failure == .sync {
            throw NSError(domain: "workspace-spy", code: 500)
        }
        var report = SyncRunReport()
        report.tasksPushed = tasks.count
        report.eventsPulled = 2
        report.tasksImported = 1
        report.finalTaskVersionCursor = Int64(tasks.count)
        report.finalCalendarToken = "token-1"
        if includeDiagnostics {
            report.diagnostics = [
                SyncDiagnosticEntry(
                    operation: .pullCalendarChanges,
                    severity: .warning,
                    message: "provider timeout",
                    taskID: nil,
                    eventIdentifier: "evt-1",
                    externalIdentifier: "ext-1",
                    calendarID: configuration.calendarID,
                    providerError: "timeout",
                    timestamp: Date(timeIntervalSince1970: 1_700_000_123),
                    attempt: 1
                )
            ]
            if includeDetachedDiagnostic {
                report.diagnostics.append(
                    SyncDiagnosticEntry(
                        operation: .pullEventUpsert,
                        severity: .warning,
                        message: "Skipped detached recurrence exception without an existing task binding.",
                        entityType: .task,
                        entityID: tasks.first?.id,
                        taskID: tasks.first?.id,
                        eventIdentifier: "evt-detached",
                        externalIdentifier: "ext-detached",
                        calendarID: configuration.calendarID,
                        providerError: nil,
                        timestamp: Date(timeIntervalSince1970: 1_700_000_124),
                        attempt: 1
                    )
                )
            }
        } else {
            report.diagnostics = []
        }
        return report
    }

    func seedDemoDataIfNeeded() async throws {
        if failure == .seed {
            throw NSError(domain: "workspace-spy", code: 500)
        }
    }

    func unlinkedMentions(for noteID: UUID) async throws -> [NoteBacklink] {
        stubbedUnlinkedMentions
    }

    func linkMention(in sourceNoteID: UUID, targetTitle: String) async throws -> Note {
        guard let note = notes.first(where: { $0.id == sourceNoteID }) else {
            throw NSError(domain: "workspace-spy", code: 404)
        }
        return note
    }

    func graphEdges() async throws -> [(from: UUID, to: UUID, fromTitle: String, toTitle: String)] {
        let pattern = try NSRegularExpression(pattern: #"\[\[([^\]|]+)(?:\|[^\]]+)?\]\]"#)
        var edges: [(from: UUID, to: UUID, fromTitle: String, toTitle: String)] = []
        for note in notes {
            let range = NSRange(note.body.startIndex..<note.body.endIndex, in: note.body)
            let matches = pattern.matches(in: note.body, range: range)
            for match in matches {
                if let targetRange = Range(match.range(at: 1), in: note.body) {
                    let targetTitle = String(note.body[targetRange])
                    if let target = notes.first(where: { $0.title.lowercased() == targetTitle.lowercased() }) {
                        edges.append((from: note.id, to: target.id, fromTitle: note.title, toTitle: target.title))
                    }
                }
            }
        }
        return edges
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
        notes.insert(note, at: 0)
        return note
    }

    func listTemplates() async throws -> [NoteTemplate] {
        templates
    }

    func createTemplate(name: String, body: String) async throws -> NoteTemplate {
        let template = NoteTemplate(name: name, body: body, createdAt: Date())
        templates.append(template)
        return template
    }

    func deleteTemplate(id: UUID) async throws {
        templates.removeAll { $0.id == id }
    }

    func createNote(title: String, body: String, templateID: UUID?) async throws -> Note {
        let note = Note(id: UUID(), title: title, body: body, updatedAt: Date(), version: 1)
        notes.insert(note, at: 0)
        return note
    }
}
