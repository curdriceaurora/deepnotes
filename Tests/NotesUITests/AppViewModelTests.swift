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

    // MARK: - Pagination

    func testLoadPaginatesNotesListTo50() async {
        let service = WorkspaceServiceSpy()
        await service.addBulkNotes(count: 60)
        let viewModel = makeViewModel(service: service)

        await viewModel.load()

        XCTAssertEqual(viewModel.notes.count, 50)
        XCTAssertNotNil(viewModel.notesNextOffset)
        XCTAssertEqual(viewModel.notesTotalCount, 62) // 60 + 2 initial
    }

    func testLoadMoreNotesAppendsNextPage() async {
        let service = WorkspaceServiceSpy()
        await service.addBulkNotes(count: 60)
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        await viewModel.loadMoreNotes()

        XCTAssertEqual(viewModel.notes.count, 62) // 50 + 12 remaining
        XCTAssertNil(viewModel.notesNextOffset)
    }

    func testLoadMoreNotesNoOpDuringSearch() async {
        let service = WorkspaceServiceSpy()
        await service.addBulkNotes(count: 60)
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        viewModel.noteSearchQuery = "Alpha"
        await viewModel.loadMoreNotes()

        // Should still be 50 from initial load (loadMore is a no-op during search)
        XCTAssertEqual(viewModel.notes.count, 50)
    }

    func testLoadMoreNotesNoOpWhenExhausted() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        // Only 2 notes, all on first page
        XCTAssertNil(viewModel.notesNextOffset)

        await viewModel.loadMoreNotes()

        XCTAssertEqual(viewModel.notes.count, 2)
    }

    func testBacklinksCachedAcrossSelections() async {
        let service = WorkspaceServiceSpy()
        await service.addTaggedNote(title: "Gamma", body: "[[Alpha]] reference", tags: [])
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        let alphaID = viewModel.notes.first(where: { $0.title == "Alpha" })?.id
        let betaID = viewModel.notes.first(where: { $0.title == "Beta" })?.id
        XCTAssertNotNil(alphaID)

        await viewModel.selectNote(id: alphaID)
        let firstBacklinks = viewModel.backlinks

        await viewModel.selectNote(id: betaID)
        await viewModel.selectNote(id: alphaID)

        XCTAssertEqual(viewModel.backlinks.count, firstBacklinks.count)
    }

    func testLoadParallelizesPhases() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)

        await viewModel.load()

        // Functional verification: all data should be populated
        XCTAssertFalse(viewModel.notes.isEmpty)
        XCTAssertFalse(viewModel.isBusy)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testReloadNotesResetsPageOnNewSearch() async {
        let service = WorkspaceServiceSpy()
        await service.addBulkNotes(count: 60)
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        XCTAssertNotNil(viewModel.notesNextOffset)

        // Trigger search (which resets pagination)
        await viewModel.setNoteSearchQuery("Alpha")
        try? await _Concurrency.Task.sleep(for: .milliseconds(400))

        // Search path does not use pagination
        XCTAssertNil(viewModel.notesNextOffset)
    }

    func testLoadMoreNotesNoOpWithTagFilter() async {
        let service = WorkspaceServiceSpy()
        await service.addBulkNotes(count: 60)
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        await viewModel.filterByTag("bulk")
        let countAfterFilter = viewModel.notes.count

        await viewModel.loadMoreNotes()

        // Tag filter bypasses pagination, so loadMore is a no-op
        XCTAssertEqual(viewModel.notes.count, countAfterFilter)
    }

    // MARK: - Kanban Card Detail

    func testOpenTaskDetailSetsSelectedTask() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        let taskID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        viewModel.openTaskDetail(taskID: taskID)

        XCTAssertNotNil(viewModel.selectedTaskForEditing)
        XCTAssertEqual(viewModel.selectedTaskForEditing?.id, taskID)
    }

    func testOpenTaskDetailWithInvalidIDDoesNothing() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        viewModel.openTaskDetail(taskID: UUID())

        XCTAssertNil(viewModel.selectedTaskForEditing)
    }

    func testCloseTaskDetailClearsSelection() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        let taskID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        viewModel.openTaskDetail(taskID: taskID)
        XCTAssertNotNil(viewModel.selectedTaskForEditing)

        viewModel.closeTaskDetail()

        XCTAssertNil(viewModel.selectedTaskForEditing)
    }

    func testSaveTaskDetailPersistsAndReloads() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        let taskID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        viewModel.openTaskDetail(taskID: taskID)
        guard var task = viewModel.selectedTaskForEditing else {
            return XCTFail("Expected task to be selected")
        }
        task.title = "Updated Title"

        await viewModel.saveTaskDetail(task)

        let updateCalls = await service.updateTaskCallCount
        XCTAssertEqual(updateCalls, 1)
        XCTAssertNil(viewModel.selectedTaskForEditing)
    }

    func testCreateQuickTaskUsesCustomPriority() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        viewModel.quickTaskTitle = "Priority task"
        viewModel.quickTaskPriority = 1

        await viewModel.createQuickTask()

        let createCalls = await service.createTaskCallCount
        XCTAssertEqual(createCalls, 1)
        let lastPriority = await service.lastCreatedTaskPriority
        XCTAssertEqual(lastPriority, 1)
    }

    func testCreateQuickTaskResetsPriorityAfterCreation() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        viewModel.quickTaskTitle = "Some task"
        viewModel.quickTaskPriority = 0

        await viewModel.createQuickTask()

        XCTAssertEqual(viewModel.quickTaskPriority, 3)
    }

    // MARK: - Kanban E2E Integration tests

    func testEndToEndCustomColumnWorkflow() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        // 1. Create custom column
        viewModel.newColumnTitle = "Review"
        await viewModel.createKanbanColumn()
        XCTAssertEqual(viewModel.kanbanColumns.count, 6)
        let customCol = viewModel.kanbanColumns.last!
        XCTAssertEqual(customCol.title, "Review")

        // 2. Verify grouping works with custom column (empty column = 0 groups)
        viewModel.kanbanGrouping = .priority
        let grouped = viewModel.groupedTasks(for: customCol.id)
        XCTAssertTrue(grouped.isEmpty || grouped.allSatisfy({ $0.tasks.isEmpty }))

        // 3. Delete custom column
        await viewModel.deleteKanbanColumn(id: customCol.id)
        XCTAssertEqual(viewModel.kanbanColumns.count, 5)
        XCTAssertFalse(viewModel.kanbanColumns.contains(where: { $0.id == customCol.id }))
    }

    func testExistingTasksWorkWithColumnBasedBoard() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        // All tasks have nil kanbanColumnID — they should appear in built-in status columns
        XCTAssertEqual(viewModel.kanbanColumns.count, 5)

        let backlogTasks = viewModel.tasks(for: .backlog)
        let nextTasks = viewModel.tasks(for: .next)
        let doneTasks = viewModel.tasks(for: .done)

        XCTAssertFalse(backlogTasks.isEmpty, "Backlog column should have tasks")
        XCTAssertFalse(nextTasks.isEmpty, "Next column should have tasks")
        XCTAssertFalse(doneTasks.isEmpty, "Done column should have tasks")

        // Verify backward-compat: tasks(for:) matches tasksForColumn
        let backlogCol = viewModel.kanbanColumns.first(where: { $0.builtInStatus == .backlog })!
        XCTAssertEqual(
            backlogTasks.map(\.id),
            viewModel.tasksForColumn(backlogCol.id).map(\.id)
        )
    }

    // MARK: - Kanban Column ViewModel tests

    func testLoadPopulatesKanbanColumnsWithDefaults() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)

        await viewModel.load()

        XCTAssertEqual(viewModel.kanbanColumns.count, 5)
        XCTAssertEqual(viewModel.kanbanColumns[0].builtInStatus, .backlog)
        XCTAssertEqual(viewModel.kanbanColumns[4].builtInStatus, .done)
    }

    func testCreateKanbanColumnAppendsCustomColumn() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        viewModel.newColumnTitle = "Review"
        await viewModel.createKanbanColumn()

        XCTAssertEqual(viewModel.kanbanColumns.count, 6)
        XCTAssertEqual(viewModel.kanbanColumns.last?.title, "Review")
        let callCount = await service.createColumnCallCount
        XCTAssertEqual(callCount, 1)
    }

    func testDeleteCustomColumnRemovesColumn() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        viewModel.newColumnTitle = "Temp"
        await viewModel.createKanbanColumn()
        XCTAssertEqual(viewModel.kanbanColumns.count, 6)

        let customID = viewModel.kanbanColumns.last!.id
        await viewModel.deleteKanbanColumn(id: customID)

        XCTAssertEqual(viewModel.kanbanColumns.count, 5)
        XCTAssertFalse(viewModel.kanbanColumns.contains(where: { $0.id == customID }))
    }

    func testDeleteBuiltInColumnSetsError() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        let backlogID = viewModel.kanbanColumns.first(where: { $0.builtInStatus == .backlog })!.id
        await viewModel.deleteKanbanColumn(id: backlogID)

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.kanbanColumns.count, 5)
    }

    func testTasksForColumnReturnsCorrectTasks() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        let backlogColumn = viewModel.kanbanColumns.first(where: { $0.builtInStatus == .backlog })!
        let backlogTasks = viewModel.tasksForColumn(backlogColumn.id)
        XCTAssertFalse(backlogTasks.isEmpty)
        XCTAssertTrue(backlogTasks.allSatisfy { $0.status == .backlog })
    }

    func testTasksForStatusBackwardCompat() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        let backlogTasks = viewModel.tasks(for: .backlog)
        XCTAssertFalse(backlogTasks.isEmpty)
        XCTAssertTrue(backlogTasks.allSatisfy { $0.status == .backlog })
    }

    // MARK: - WIP Limits

    func testUpdateColumnWipLimitPersists() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        var col = viewModel.kanbanColumns.first(where: { $0.builtInStatus == .backlog })!
        col.wipLimit = 3
        await viewModel.updateKanbanColumn(col)

        let updated = viewModel.kanbanColumns.first(where: { $0.builtInStatus == .backlog })
        XCTAssertEqual(updated?.wipLimit, 3)
    }

    func testColumnOverWipLimitDetected() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        // Backlog has 2 tasks in the spy; set WIP limit to 2
        var col = viewModel.kanbanColumns.first(where: { $0.builtInStatus == .backlog })!
        col.wipLimit = 2
        await viewModel.updateKanbanColumn(col)

        let backlogTasks = viewModel.tasksForColumn(col.id)
        XCTAssertGreaterThanOrEqual(backlogTasks.count, col.wipLimit!)
    }

    // MARK: - Labels

    func testAddLabelToTaskPersists() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let task = viewModel.tasks.first(where: { $0.status == .backlog }) else {
            return XCTFail("Expected backlog task")
        }

        let label = TaskLabel(name: "Bug", colorHex: "#FF0000")
        await viewModel.addLabelToTask(taskID: task.id, label: label)

        let callCount = await service.addLabelCallCount
        XCTAssertEqual(callCount, 1)
    }

    func testRemoveLabelFromTaskRemoves() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let task = viewModel.tasks.first(where: { $0.status == .backlog }) else {
            return XCTFail("Expected backlog task")
        }

        let label = TaskLabel(name: "Bug", colorHex: "#FF0000")
        await viewModel.addLabelToTask(taskID: task.id, label: label)
        await viewModel.removeLabelFromTask(taskID: task.id, labelName: "Bug")

        let removeCount = await service.removeLabelCallCount
        XCTAssertEqual(removeCount, 1)
    }

    func testAllLabelsDerivedFromTasks() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let task = viewModel.tasks.first(where: { $0.status == .backlog }) else {
            return XCTFail("Expected backlog task")
        }

        await viewModel.addLabelToTask(taskID: task.id, label: TaskLabel(name: "Bug", colorHex: "#FF0000"))
        await viewModel.addLabelToTask(taskID: task.id, label: TaskLabel(name: "Feature", colorHex: "#00FF00"))

        XCTAssertTrue(viewModel.allLabels.contains(where: { $0.name == "Bug" }))
        XCTAssertTrue(viewModel.allLabels.contains(where: { $0.name == "Feature" }))
    }

    // MARK: - Swimlane Grouping

    func testGroupedTasksByPriority() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        viewModel.kanbanGrouping = .priority

        let backlogColumn = viewModel.kanbanColumns.first(where: { $0.builtInStatus == .backlog })!
        let grouped = viewModel.groupedTasks(for: backlogColumn.id)

        XCTAssertFalse(grouped.isEmpty)
        XCTAssertTrue(grouped.allSatisfy { !$0.key.isEmpty })
    }

    func testGroupedTasksByNone() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        viewModel.kanbanGrouping = .none

        let backlogColumn = viewModel.kanbanColumns.first(where: { $0.builtInStatus == .backlog })!
        let grouped = viewModel.groupedTasks(for: backlogColumn.id)

        XCTAssertEqual(grouped.count, 1)
        XCTAssertEqual(grouped.first?.key, "")
    }

    func testGroupingChangeIsViewOnly() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        let callsBefore = await service.createColumnCallCount
        viewModel.kanbanGrouping = .priority
        viewModel.kanbanGrouping = .label
        viewModel.kanbanGrouping = .none
        let callsAfter = await service.createColumnCallCount

        XCTAssertEqual(callsBefore, callsAfter)
    }

    // MARK: - Drag-Drop Column

    func testDropTargetColumnIDSetAndCleared() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        let backlogColumn = viewModel.kanbanColumns.first(where: { $0.builtInStatus == .backlog })!
        viewModel.beginTaskDrag(taskID: UUID())
        viewModel.setDropTargetColumn(backlogColumn.id)
        XCTAssertEqual(viewModel.dropTargetColumnID, backlogColumn.id)

        viewModel.endTaskDrag()
        XCTAssertNil(viewModel.dropTargetColumnID)
        XCTAssertNil(viewModel.draggingTaskID)
    }

    func testMoveTaskClearsKanbanColumnID() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let task = viewModel.tasks.first(where: { $0.status == .backlog }) else {
            return XCTFail("Expected backlog task")
        }

        await viewModel.moveTask(taskID: task.id, to: .next)
        await viewModel.setTaskFilter(.all)

        let moved = viewModel.tasks.first(where: { $0.id == task.id })
        XCTAssertEqual(moved?.status, .next)
    }

    func testToggleMultiSelectMode_entersAndExits() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        XCTAssertFalse(viewModel.isMultiSelectMode)
        XCTAssertTrue(viewModel.selectedTaskIDs.isEmpty)

        viewModel.toggleMultiSelectMode()
        XCTAssertTrue(viewModel.isMultiSelectMode)

        guard let task = viewModel.tasks.first else {
            return XCTFail("Expected at least one task")
        }
        viewModel.toggleTaskSelection(taskID: task.id)
        XCTAssertEqual(viewModel.selectedTaskIDs.count, 1)

        viewModel.toggleMultiSelectMode()
        XCTAssertFalse(viewModel.isMultiSelectMode)
        XCTAssertTrue(viewModel.selectedTaskIDs.isEmpty)
    }

    func testToggleTaskSelection_addsAndRemoves() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let task1 = viewModel.tasks.first else {
            return XCTFail("Expected at least one task")
        }
        guard let task2 = viewModel.tasks.dropFirst().first else {
            return XCTFail("Expected at least two tasks")
        }

        viewModel.toggleTaskSelection(taskID: task1.id)
        XCTAssertEqual(viewModel.selectedTaskIDs.count, 1)
        XCTAssertTrue(viewModel.selectedTaskIDs.contains(task1.id))

        viewModel.toggleTaskSelection(taskID: task2.id)
        XCTAssertEqual(viewModel.selectedTaskIDs.count, 2)
        XCTAssertTrue(viewModel.selectedTaskIDs.contains(task1.id))
        XCTAssertTrue(viewModel.selectedTaskIDs.contains(task2.id))

        viewModel.toggleTaskSelection(taskID: task1.id)
        XCTAssertEqual(viewModel.selectedTaskIDs.count, 1)
        XCTAssertFalse(viewModel.selectedTaskIDs.contains(task1.id))
        XCTAssertTrue(viewModel.selectedTaskIDs.contains(task2.id))
    }

    func testBulkMoveTasksToStatus_callsServiceForEachID() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard viewModel.tasks.count >= 3 else {
            return XCTFail("Expected at least 3 tasks")
        }

        let task1 = viewModel.tasks[0]
        let task2 = viewModel.tasks[1]
        let task3 = viewModel.tasks[2]

        viewModel.toggleTaskSelection(taskID: task1.id)
        viewModel.toggleTaskSelection(taskID: task2.id)
        viewModel.toggleTaskSelection(taskID: task3.id)

        await viewModel.bulkMoveTasksToStatus(.done)

        let moveCount = await service.moveTaskCallCount
        XCTAssertEqual(moveCount, 3)
    }

    func testBulkMoveTasksToStatus_clearsSelectionAndExitsMulitSelectMode() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard viewModel.tasks.count >= 2 else {
            return XCTFail("Expected at least 2 tasks")
        }

        viewModel.isMultiSelectMode = true
        viewModel.toggleTaskSelection(taskID: viewModel.tasks[0].id)
        viewModel.toggleTaskSelection(taskID: viewModel.tasks[1].id)

        XCTAssertTrue(viewModel.isMultiSelectMode)
        XCTAssertEqual(viewModel.selectedTaskIDs.count, 2)

        await viewModel.bulkMoveTasksToStatus(.next)

        XCTAssertFalse(viewModel.isMultiSelectMode)
        XCTAssertTrue(viewModel.selectedTaskIDs.isEmpty)
    }

    // MARK: - Subtask tests

    func testAddSubtaskAppendsToParent() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard !viewModel.tasks.isEmpty else {
            return XCTFail("Expected at least 1 task")
        }

        let parentTask = viewModel.tasks[0]
        let initialCount = parentTask.subtasks.count
        viewModel.newSubtaskTitle = "New Subtask"

        await viewModel.addSubtask(to: parentTask.id)

        let updated = viewModel.tasks.first { $0.id == parentTask.id }
        XCTAssertEqual(updated?.subtasks.count, initialCount + 1)
        XCTAssertEqual(updated?.subtasks.last?.title, "New Subtask")
    }

    func testToggleSubtaskUpdatesCompletion() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard !viewModel.tasks.isEmpty else {
            return XCTFail("Expected at least 1 task")
        }

        let parentID = viewModel.tasks[0].id
        viewModel.newSubtaskTitle = "Subtask 1"
        await viewModel.addSubtask(to: parentID)
        viewModel.newSubtaskTitle = "Subtask 2"
        await viewModel.addSubtask(to: parentID)

        guard let taskAfterAdd = viewModel.tasks.first(where: { $0.id == parentID }),
              taskAfterAdd.subtasks.count == 2 else {
            return XCTFail("Expected 2 subtasks to be added")
        }

        let firstSubtaskID = taskAfterAdd.subtasks[0].id
        await viewModel.toggleSubtask(parentTaskID: parentID, subtaskID: firstSubtaskID, isCompleted: true)

        let final = viewModel.tasks.first(where: { $0.id == parentID })
        guard let finalTask = final else {
            return XCTFail("Parent task not found after toggling first subtask")
        }
        guard let updatedSubtask = finalTask.subtasks.first(where: { $0.id == firstSubtaskID }) else {
            return XCTFail("Subtask not found after toggle")
        }
        XCTAssertTrue(updatedSubtask.isCompleted)
    }

    func testToggleAllSubtasksCompletesParent() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard !viewModel.tasks.isEmpty else {
            return XCTFail("Expected at least 1 task")
        }

        let parentID = viewModel.tasks[0].id
        viewModel.newSubtaskTitle = "Subtask 1"
        await viewModel.addSubtask(to: parentID)
        viewModel.newSubtaskTitle = "Subtask 2"
        await viewModel.addSubtask(to: parentID)

        guard let task = viewModel.tasks.first(where: { $0.id == parentID }) else {
            return XCTFail("Expected parent task")
        }

        let subtaskIDs = task.subtasks.map(\.id)
        for subtaskID in subtaskIDs {
            await viewModel.toggleSubtask(parentTaskID: parentID, subtaskID: subtaskID, isCompleted: true)
        }

        await viewModel.setTaskFilter(.completed)
        let updated = viewModel.tasks.first { $0.id == parentID }
        XCTAssertEqual(updated?.status, .done)
    }

    func testDeleteSubtaskRemovesFromParent() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard !viewModel.tasks.isEmpty else {
            return XCTFail("Expected at least 1 task")
        }

        let parentTask = viewModel.tasks[0]
        viewModel.newSubtaskTitle = "Test Subtask"
        await viewModel.addSubtask(to: parentTask.id)

        guard let task = viewModel.tasks.first(where: { $0.id == parentTask.id }),
              let subtask = task.subtasks.last else {
            return XCTFail("Expected subtask to be added")
        }

        await viewModel.deleteSubtask(parentTaskID: parentTask.id, subtaskID: subtask.id)

        let updated = viewModel.tasks.first { $0.id == parentTask.id }
        XCTAssertTrue(updated?.subtasks.isEmpty ?? false)
    }

    func testLoadRequestsNotificationPermission() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        let callCount = await service.requestNotificationPermissionCallCount
        XCTAssertEqual(callCount, 1)
    }

    func testSetTaskSortOrderByPriority() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskSortOrder(.priority)
        XCTAssertEqual(viewModel.taskSortOrder, .priority)
        let sortOrderCalled = await service.listTasksSortOrderCalled
        XCTAssertEqual(sortOrderCalled, .priority)
    }

    func testSetTaskSortOrderPersistsToUserDefaults() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskSortOrder(.title)
        let saved = UserDefaults.standard.string(forKey: "taskSortOrder")
        XCTAssertEqual(saved, "title")
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
    private(set) var moveTaskCallCount: Int = 0
    private(set) var lastCreatedTaskPriority: Int = 3

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

    func addBulkNotes(count: Int) {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<count {
            let note = Note(id: UUID(), title: "Bulk Note \(i)", body: "Body \(i)", tags: ["bulk"], updatedAt: base.addingTimeInterval(Double(i)), version: 1)
            notes.append(note)
        }
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

    func listNoteListItems(limit: Int, offset: Int) async throws -> NoteListItemPage {
        let allItems = notes.map(\.listItem).sorted { $0.updatedAt > $1.updatedAt }
        let start = min(max(0, offset), allItems.count)
        let end = min(allItems.count, start + max(1, limit))
        return NoteListItemPage(offset: start, limit: limit, totalCount: allItems.count, items: Array(allItems[start..<end]))
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
        lastCreatedTaskPriority = input.priority
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
        moveTaskCallCount += 1
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

    // MARK: - Kanban Column & Label methods

    private(set) var createColumnCallCount: Int = 0
    private(set) var deleteColumnCallCount: Int = 0
    private(set) var addLabelCallCount: Int = 0
    private(set) var removeLabelCallCount: Int = 0

    private var kanbanColumns: [KanbanColumn] = [
        KanbanColumn(id: UUID(uuidString: "C0000001-0000-0000-0000-000000000001")!, title: "Backlog", builtInStatus: .backlog, position: 0),
        KanbanColumn(id: UUID(uuidString: "C0000002-0000-0000-0000-000000000002")!, title: "Next", builtInStatus: .next, position: 1),
        KanbanColumn(id: UUID(uuidString: "C0000003-0000-0000-0000-000000000003")!, title: "Doing", builtInStatus: .doing, position: 2),
        KanbanColumn(id: UUID(uuidString: "C0000004-0000-0000-0000-000000000004")!, title: "Waiting", builtInStatus: .waiting, position: 3),
        KanbanColumn(id: UUID(uuidString: "C0000005-0000-0000-0000-000000000005")!, title: "Done", builtInStatus: .done, position: 4)
    ]

    func listKanbanColumns() async throws -> [KanbanColumn] {
        kanbanColumns.sorted { $0.position < $1.position }
    }

    func createKanbanColumn(title: String) async throws -> KanbanColumn {
        createColumnCallCount += 1
        let position = (kanbanColumns.map(\.position).max() ?? -1) + 1
        let column = KanbanColumn(title: title, position: position)
        kanbanColumns.append(column)
        return column
    }

    func updateKanbanColumn(_ column: KanbanColumn) async throws -> KanbanColumn {
        guard let idx = kanbanColumns.firstIndex(where: { $0.id == column.id }) else {
            throw NSError(domain: "workspace-spy", code: 404)
        }
        kanbanColumns[idx] = column
        return kanbanColumns[idx]
    }

    func deleteKanbanColumn(id: UUID) async throws {
        deleteColumnCallCount += 1
        guard let col = kanbanColumns.first(where: { $0.id == id }) else { return }
        guard col.builtInStatus == nil else {
            throw NSError(domain: "workspace-spy", code: 403, userInfo: [NSLocalizedDescriptionKey: "Cannot delete built-in column"])
        }
        kanbanColumns.removeAll { $0.id == id }
        for idx in tasks.indices where tasks[idx].kanbanColumnID == id {
            tasks[idx].kanbanColumnID = nil
            tasks[idx].status = .backlog
        }
    }

    func addLabelToTask(taskID: UUID, label: TaskLabel) async throws -> Task {
        addLabelCallCount += 1
        guard let idx = tasks.firstIndex(where: { $0.id == taskID }) else {
            throw NSError(domain: "workspace-spy", code: 404)
        }
        if !tasks[idx].labels.contains(where: { $0.name.lowercased() == label.name.lowercased() }) {
            tasks[idx].labels.append(label)
        }
        return tasks[idx]
    }

    func removeLabelFromTask(taskID: UUID, labelName: String) async throws -> Task {
        removeLabelCallCount += 1
        guard let idx = tasks.firstIndex(where: { $0.id == taskID }) else {
            throw NSError(domain: "workspace-spy", code: 404)
        }
        tasks[idx].labels.removeAll { $0.name.lowercased() == labelName.lowercased() }
        return tasks[idx]
    }

    // MARK: - Subtask methods

    private(set) var addSubtaskCallCount: Int = 0
    private(set) var lastSubtaskParentID: UUID?

    func addSubtask(to parentTaskID: UUID, title: String) async throws -> Task {
        addSubtaskCallCount += 1
        lastSubtaskParentID = parentTaskID
        guard let idx = tasks.firstIndex(where: { $0.id == parentTaskID }) else {
            throw NSError(domain: "workspace-spy", code: 404)
        }
        let subtask = Subtask(title: title, order: tasks[idx].subtasks.count)
        tasks[idx].subtasks.append(subtask)
        return tasks[idx]
    }

    func toggleSubtask(parentTaskID: UUID, subtaskID: UUID, isCompleted: Bool) async throws -> Task {
        guard let taskIdx = tasks.firstIndex(where: { $0.id == parentTaskID }) else {
            throw NSError(domain: "workspace-spy", code: 404)
        }
        guard let subtaskIdx = tasks[taskIdx].subtasks.firstIndex(where: { $0.id == subtaskID }) else {
            throw NSError(domain: "workspace-spy", code: 404)
        }
        tasks[taskIdx].subtasks[subtaskIdx].isCompleted = isCompleted

        if isCompleted && tasks[taskIdx].subtasks.allSatisfy(\.isCompleted) && tasks[taskIdx].status != .done {
            tasks[taskIdx].status = .done
            tasks[taskIdx].completedAt = Date()
        }

        return tasks[taskIdx]
    }

    func deleteSubtask(parentTaskID: UUID, subtaskID: UUID) async throws -> Task {
        guard let idx = tasks.firstIndex(where: { $0.id == parentTaskID }) else {
            throw NSError(domain: "workspace-spy", code: 404)
        }
        tasks[idx].subtasks.removeAll { $0.id == subtaskID }

        var order = 0
        for i in tasks[idx].subtasks.indices {
            tasks[idx].subtasks[i].order = order
            order += 1
        }

        return tasks[idx]
    }

    private(set) var requestNotificationPermissionCallCount = 0

    func requestNotificationPermission() async -> Bool {
        requestNotificationPermissionCallCount += 1
        return true
    }

    private(set) var listTasksSortOrderCalled: TaskSortOrder?

    func listTasks(filter: TaskListFilter, sortOrder: TaskSortOrder) async throws -> [Task] {
        listTasksSortOrderCalled = sortOrder
        return try await listTasks(filter: filter)
    }
}
