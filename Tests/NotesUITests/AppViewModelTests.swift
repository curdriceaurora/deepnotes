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
        XCTAssertEqual(viewModel.notes.count, 1)

        await viewModel.setNoteSearchQuery("")
        XCTAssertEqual(viewModel.noteSearchQuery, "")
        XCTAssertEqual(viewModel.notes.count, 2)
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

    func testHandleTaskDropSameStatusWithoutBeforeIsNoOp() async {
        let service = WorkspaceServiceSpy()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let backlogA = viewModel.tasks.first(where: { $0.stableID == "t-backlog-a" }) else {
            return XCTFail("Missing backlog fixture")
        }

        let moved = await viewModel.handleTaskDrop(
            taskPayloads: [backlogA.id.uuidString],
            to: .backlog,
            beforeTaskID: nil
        )
        XCTAssertTrue(moved)
        XCTAssertNil(viewModel.errorMessage)
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

    private(set) var updateNoteCallCount: Int = 0
    private(set) var createTaskCallCount: Int = 0

    private var notes: [Note]
    private var tasks: [Task]

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
            try! Task(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, noteID: notes[0].id, stableID: "t-done", title: "Done", status: .done, kanbanOrder: 1, completedAt: now, updatedAt: now)
        ]
    }

    func setFailure(_ mode: FailureMode?) {
        self.failure = mode
    }

    func listNotes() async throws -> [Note] {
        notes.sorted { $0.updatedAt > $1.updatedAt }
    }

    func searchNotes(query: String, limit: Int) async throws -> [Note] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return try await listNotes()
        }

        return notes
            .filter { $0.title.localizedCaseInsensitiveContains(normalized) || $0.body.localizedCaseInsensitiveContains(normalized) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(max(1, limit))
            .map { $0 }
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
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else {
            throw NSError(domain: "workspace-spy", code: 404)
        }
        tasks[idx] = task
        return tasks[idx]
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
        return report
    }

    func seedDemoDataIfNeeded() async throws {
        if failure == .seed {
            throw NSError(domain: "workspace-spy", code: 500)
        }
    }
}
