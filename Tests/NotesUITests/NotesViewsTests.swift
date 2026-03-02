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
        let viewModel = makeViewModel()
        await viewModel.load()

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "newNoteButton"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "noteSearchField"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "noteTitleField"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "noteBodyEditor"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "saveNoteButton"))
    }

    func testTasksListContainsPickerAndRows() async throws {
        let viewModel = makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        let view = TasksListView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "taskFilterPicker"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "tasksList"))
    }

    func testKanbanRendersAllStatusColumns() async throws {
        let viewModel = makeViewModel()
        await viewModel.load()

        let view = KanbanBoardView(viewModel: viewModel)
        let inspected = try view.inspect()

        for status in TaskStatus.allCases {
            XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "kanbanColumn_\(status.rawValue)"))
        }
    }

    func testSyncDashboardHasCalendarFieldAndRunButton() async throws {
        let viewModel = makeViewModel()
        await viewModel.load()

        let view = SyncDashboardView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "syncCalendarField"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "runSyncButton"))
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "syncStatusText"))
    }

    func testNotesEditorNewNoteButtonTriggersCreation() async throws {
        let viewModel = makeViewModel()
        await viewModel.load()
        let countBefore = viewModel.notes.count

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()
        try inspected.find(viewWithAccessibilityIdentifier: "newNoteButton").button().tap()

        try await _Concurrency.Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(viewModel.notes.count, countBefore + 1)
    }

    func testSyncDashboardRunButtonUpdatesStatus() async throws {
        let viewModel = makeViewModel()
        await viewModel.load()

        let view = SyncDashboardView(viewModel: viewModel)
        let inspected = try view.inspect()
        try inspected.find(viewWithAccessibilityIdentifier: "runSyncButton").button().tap()

        try await _Concurrency.Task.sleep(nanoseconds: 120_000_000)
        XCTAssertNotNil(viewModel.lastSyncReport)
    }

    func testKanbanMoveRightButtonTransitionsTask() async throws {
        let viewModel = makeViewModel()
        await viewModel.load()
        await viewModel.setTaskFilter(.all)

        guard let task = viewModel.tasks.first(where: { $0.status == .backlog }) else {
            return XCTFail("Expected backlog task")
        }

        let view = KanbanBoardView(viewModel: viewModel)
        let inspected = try view.inspect()

        try inspected.find(viewWithAccessibilityIdentifier: "moveRight_\(task.id.uuidString)").button().tap()
        try await _Concurrency.Task.sleep(nanoseconds: 120_000_000)

        await viewModel.setTaskFilter(.all)
        let moved = viewModel.tasks.first { $0.id == task.id }
        XCTAssertEqual(moved?.status, .next)
    }

    func testRootViewRendersErrorBannerWhenViewModelHasError() async throws {
        let viewModel = makeViewModel()
        await viewModel.load()
        viewModel.syncCalendarID = "   "
        await viewModel.runSync()

        let view = NotesRootView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "globalErrorBanner"))
    }

    func testNotesEditorNoteRowTapSelectsNote() async throws {
        let viewModel = makeViewModel()
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

    func testNotesEditorSaveAndQuickTaskButtonsTriggerActions() async throws {
        let viewModel = makeViewModel()
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
        let viewModel = makeViewModel()
        await viewModel.load()

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "backlinksList"))
    }

    func testNotesEditorRendersBacklinksEmptyStateWhenNoSelection() async throws {
        let viewModel = makeViewModel()
        await viewModel.load()
        await viewModel.selectNote(id: nil)

        let view = NotesEditorView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "backlinksEmptyState"))
    }

    func testTasksListPickerSelectionUpdatesFilter() async throws {
        let viewModel = makeViewModel()
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
        let viewModel = makeViewModel()
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
        XCTAssertTrue(viewModel.tasks.contains(where: { $0.id == target.id }))
    }

    func testKanbanMoveLeftButtonTransitionsTask() async throws {
        let viewModel = makeViewModel()
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

    func testSyncDashboardShowsReportSectionAfterSync() async throws {
        let viewModel = makeViewModel()
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

    func testSyncDashboardExportDiagnosticsButtonWritesExportPath() async throws {
        let viewModel = makeViewModel()
        await viewModel.load()
        await viewModel.runSync()

        let view = SyncDashboardView(viewModel: viewModel)
        let inspected = try view.inspect()
        try inspected.find(viewWithAccessibilityIdentifier: "exportSyncDiagnosticsButton").button().tap()
        try await flushAsyncActions()

        XCTAssertNotNil(viewModel.lastDiagnosticsExportURL)
    }

    func testSyncDashboardShowsExportedPathAfterExport() async throws {
        let viewModel = makeViewModel()
        await viewModel.load()
        await viewModel.runSync()
        await viewModel.exportSyncDiagnostics()

        let view = SyncDashboardView(viewModel: viewModel)
        let inspected = try view.inspect()
        XCTAssertNoThrow(try inspected.find(viewWithAccessibilityIdentifier: "syncDiagnosticsExportPath"))
    }

    private func makeViewModel() -> AppViewModel {
        let service = MockWorkspaceService()
        let provider = InMemoryCalendarProvider()
        return AppViewModel(
            service: service,
            calendarProviderFactory: { provider },
            syncCalendarID: "dev-calendar"
        )
    }

    private func flushAsyncActions() async throws {
        try await _Concurrency.Task.sleep(nanoseconds: 160_000_000)
    }
}

actor MockWorkspaceService: WorkspaceServicing {
    private var notes: [Note]
    private var tasks: [Task]

    init() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        self.notes = [
            Note(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                title: "Q2 Launch Plan",
                body: "References [[Vendor Notes]]",
                updatedAt: now,
                version: 1,
                deletedAt: nil
            ),
            Note(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                title: "Vendor Notes",
                body: "Connected to [[Q2 Launch Plan]]",
                updatedAt: now,
                version: 1,
                deletedAt: nil
            )
        ]

        self.tasks = [
            try! Task(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                noteID: notes[0].id,
                stableID: "task-backlog",
                title: "Research",
                status: .backlog,
                priority: 2,
                kanbanOrder: 1,
                updatedAt: now
            ),
            try! Task(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
                noteID: notes[0].id,
                stableID: "task-next",
                title: "Call supplier",
                dueStart: now.addingTimeInterval(3600),
                dueEnd: now.addingTimeInterval(7200),
                status: .next,
                priority: 3,
                kanbanOrder: 1,
                updatedAt: now
            ),
            try! Task(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
                noteID: notes[0].id,
                stableID: "task-doing",
                title: "Draft email",
                status: .doing,
                priority: 3,
                kanbanOrder: 1,
                updatedAt: now
            ),
            try! Task(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
                noteID: notes[0].id,
                stableID: "task-waiting",
                title: "Await feedback",
                status: .waiting,
                priority: 2,
                kanbanOrder: 1,
                updatedAt: now
            ),
            try! Task(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!,
                noteID: notes[0].id,
                stableID: "task-done",
                title: "Kickoff",
                status: .done,
                priority: 1,
                kanbanOrder: 1,
                completedAt: now,
                updatedAt: now
            )
        ]
    }

    func listNotes() async throws -> [Note] {
        notes
    }

    func searchNotes(query: String, limit: Int) async throws -> [Note] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return notes
        }

        return notes
            .filter { $0.title.localizedCaseInsensitiveContains(trimmed) || $0.body.localizedCaseInsensitiveContains(trimmed) }
            .prefix(max(1, limit))
            .map { $0 }
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
                severity: .info,
                message: "mock diagnostics",
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
}
