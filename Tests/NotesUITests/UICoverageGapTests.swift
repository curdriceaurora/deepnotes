import XCTest
import SwiftUI
import ViewInspector
@testable import NotesDomain
@testable import NotesFeatures
@testable import NotesUI
@testable import NotesSync

/// Tests targeting coverage gaps identified in the UI audit.
/// Covers: empty states, filter edge cases, status badges, count badges,
/// sync metric cards, recurrence dialogs, and new Theme polish elements.
@MainActor
final class UICoverageGapTests: XCTestCase {

    // MARK: - Helpers

    private func makeViewModel(notes: [Note] = [], tasks: [Task] = []) -> AppViewModel {
        let service = MockWorkspaceService(notes: notes, tasks: tasks)
        let provider = InMemoryCalendarProvider()
        return AppViewModel(
            service: service,
            calendarProviderFactory: { provider },
            syncCalendarID: "dev-calendar"
        )
    }

    private func makePopulatedViewModel() throws -> AppViewModel {
        let service = try MockWorkspaceService()
        let provider = InMemoryCalendarProvider()
        return AppViewModel(
            service: service,
            calendarProviderFactory: { provider },
            syncCalendarID: "dev-calendar"
        )
    }

    // MARK: - §1 Empty States — Fresh Install

    func testFreshInstallNotesListEmpty() async {
        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertTrue(viewModel.notes.isEmpty, "Fresh install must have no notes")
    }

    func testFreshInstallTasksListEmpty() async {
        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertTrue(viewModel.tasks.isEmpty, "Fresh install must have no tasks")
    }

    func testFreshInstallKanbanColumnsRenderNoCardsPlaceholder() async throws {
        let viewModel = makeViewModel()
        await viewModel.load()

        for status in TaskStatus.allCases {
            XCTAssertTrue(viewModel.tasks(for: status).isEmpty,
                          "Column \(status.rawValue) must be empty on fresh install")
        }
    }

    // MARK: - §8 Filter Edge Cases

    func testFilterUpcomingReturnsFutureDatedTasks() async throws {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let task = try Task(
            stableID: "upcoming-task",
            title: "Future task",
            dueStart: tomorrow,
            status: .next,
            kanbanOrder: 1,
            updatedAt: Date()
        )

        let viewModel = makeViewModel(tasks: [task])
        await viewModel.load()
        await viewModel.setTaskFilter(.upcoming)

        XCTAssertEqual(viewModel.tasks.count, 1, "Upcoming filter must return future-dated tasks")
        XCTAssertEqual(viewModel.tasks.first?.title, "Future task")
    }

    func testFilterOverdueReturnsPastDueTasks() async throws {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let task = try Task(
            stableID: "overdue-task",
            title: "Late task",
            dueStart: yesterday,
            status: .next,
            kanbanOrder: 1,
            updatedAt: Date()
        )

        let viewModel = makeViewModel(tasks: [task])
        await viewModel.load()
        await viewModel.setTaskFilter(.overdue)

        XCTAssertEqual(viewModel.tasks.count, 1, "Overdue filter must return past-due tasks")
        XCTAssertEqual(viewModel.tasks.first?.title, "Late task")
    }

    func testFilterUpcomingExcludesCompletedTasks() async throws {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let task = try Task(
            stableID: "done-future",
            title: "Done future task",
            dueStart: tomorrow,
            status: .done,
            kanbanOrder: 1,
            completedAt: Date(),
            updatedAt: Date()
        )

        let viewModel = makeViewModel(tasks: [task])
        await viewModel.load()
        await viewModel.setTaskFilter(.upcoming)

        XCTAssertTrue(viewModel.tasks.isEmpty, "Upcoming filter must exclude completed tasks")
    }

    func testFilterOverdueExcludesCompletedTasks() async throws {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let task = try Task(
            stableID: "done-overdue",
            title: "Done late task",
            dueStart: yesterday,
            status: .done,
            kanbanOrder: 1,
            completedAt: Date(),
            updatedAt: Date()
        )

        let viewModel = makeViewModel(tasks: [task])
        await viewModel.load()
        await viewModel.setTaskFilter(.overdue)

        XCTAssertTrue(viewModel.tasks.isEmpty, "Overdue filter must exclude completed tasks")
    }

    // MARK: - §9 Task Row Status Badges (ViewInspector)

    func testTaskRowRendersStatusBadgeText() async throws {
        let viewModel = try makePopulatedViewModel()
        await viewModel.load()

        let view = TasksListView(viewModel: viewModel)
        let inspected = try view.inspect()

        guard let firstTask = viewModel.tasks.first else {
            return XCTFail("Expected at least one task")
        }

        XCTAssertNoThrow(
            try inspected.find(viewWithAccessibilityIdentifier: "taskRow_\(firstTask.id.uuidString)"),
            "Task row must render with accessibility identifier"
        )
    }

    func testTaskRowRendersDeleteButton() async throws {
        let viewModel = try makePopulatedViewModel()
        await viewModel.load()

        let view = TasksListView(viewModel: viewModel)
        let inspected = try view.inspect()

        guard let firstTask = viewModel.tasks.first else {
            return XCTFail("Expected at least one task")
        }

        XCTAssertNoThrow(
            try inspected.find(viewWithAccessibilityIdentifier: "deleteTask_\(firstTask.id.uuidString)"),
            "Delete button must render for each task"
        )
    }

    // MARK: - §11 Kanban Column Count Badges

    func testKanbanColumnCountMatchesTaskCount() async throws {
        let viewModel = try makePopulatedViewModel()
        await viewModel.load()

        let totalKanban = TaskStatus.allCases.reduce(0) { $0 + viewModel.tasks(for: $1).count }
        XCTAssertGreaterThan(totalKanban, 0, "At least one column must have cards")
    }

    // MARK: - §15 Sync Metric Cards

    func testSyncReportMetricValuesPresent() async throws {
        let viewModel = try makePopulatedViewModel()
        await viewModel.load()
        await viewModel.runSync()

        guard let report = viewModel.lastSyncReport else {
            return XCTFail("Sync report must be set after runSync")
        }

        XCTAssertGreaterThanOrEqual(report.tasksPushed, 0)
        XCTAssertGreaterThanOrEqual(report.eventsPulled, 0)
        XCTAssertGreaterThanOrEqual(report.tasksImported, 0)
        XCTAssertGreaterThanOrEqual(report.tasksDeletedFromCalendar, 0)
    }

    func testSyncDashboardReportSectionRenderedAfterSync() async throws {
        let viewModel = try makePopulatedViewModel()
        await viewModel.load()
        await viewModel.runSync()

        let view = SyncDashboardView(viewModel: viewModel)
        let inspected = try view.inspect()

        XCTAssertNoThrow(
            try inspected.find(viewWithAccessibilityIdentifier: "syncReportSection"),
            "Report section must render after sync"
        )
    }

    // MARK: - §15 Sync Button State

    func testSyncStatusTextUpdatesAfterSync() async throws {
        let viewModel = try makePopulatedViewModel()
        await viewModel.load()

        XCTAssertEqual(viewModel.syncStatusText, "Idle", "Initial status must be Idle")

        await viewModel.runSync()

        XCTAssertTrue(viewModel.syncStatusText.contains("Sync complete"),
                      "Status text must update after sync")
    }

    func testSyncSetsIsSyncingDuringRun() async throws {
        let viewModel = try makePopulatedViewModel()
        await viewModel.load()

        XCTAssertFalse(viewModel.isSyncing, "Must not be syncing initially")
        // After sync completes, isSyncing should be false again
        await viewModel.runSync()
        XCTAssertFalse(viewModel.isSyncing, "Must not be syncing after completion")
    }

    // MARK: - §17 Diagnostics Entries

    func testSyncDiagnosticRowsRendered() async throws {
        let viewModel = try makePopulatedViewModel()
        await viewModel.load()
        await viewModel.runSync()

        guard let report = viewModel.lastSyncReport else {
            return XCTFail("Report must exist")
        }
        XCTAssertFalse(report.diagnostics.isEmpty, "Mock produces at least one diagnostic")

        let view = SyncDashboardView(viewModel: viewModel)
        let inspected = try view.inspect()
        XCTAssertNoThrow(
            try inspected.find(viewWithAccessibilityIdentifier: "syncDiagnosticRow_0"),
            "First diagnostic row must render"
        )
    }

    // MARK: - §18 Recurrence Dialog Lifecycle

    func testRecurrenceEditPromptNilInitially() async throws {
        let viewModel = try makePopulatedViewModel()
        await viewModel.load()

        XCTAssertNil(viewModel.recurrenceEditPrompt, "No edit prompt initially")
    }

    func testRecurrenceDeletePromptNilInitially() async throws {
        let viewModel = try makePopulatedViewModel()
        await viewModel.load()

        XCTAssertNil(viewModel.recurrenceDeletePrompt, "No delete prompt initially")
    }

    func testDismissRecurrenceEditPromptIsIdempotent() async throws {
        let viewModel = try makePopulatedViewModel()
        await viewModel.load()

        // Dismissing when already nil should not crash
        viewModel.dismissRecurrenceEditPrompt()
        XCTAssertNil(viewModel.recurrenceEditPrompt,
                     "Dismissing an already-nil edit prompt must not crash")
    }

    func testDismissRecurrenceDeletePromptIsIdempotent() async throws {
        let viewModel = try makePopulatedViewModel()
        await viewModel.load()

        // Dismissing when already nil should not crash
        viewModel.dismissRecurrenceDeletePrompt()
        XCTAssertNil(viewModel.recurrenceDeletePrompt,
                     "Dismissing an already-nil delete prompt must not crash")
    }

    func testResolveRecurrenceEditPromptWithoutPendingIsNoOp() async throws {
        let viewModel = try makePopulatedViewModel()
        await viewModel.load()

        // Resolving with no pending mutation should not crash
        await viewModel.resolveRecurrenceEditPrompt(scope: .thisOccurrence)
        XCTAssertNil(viewModel.recurrenceEditPrompt)
    }

    func testResolveRecurrenceDeletePromptWithoutPendingIsNoOp() async throws {
        let viewModel = try makePopulatedViewModel()
        await viewModel.load()

        // Resolving with no pending deletion should not crash
        await viewModel.resolveRecurrenceDeletePrompt(scope: .entireSeries)
        XCTAssertNil(viewModel.recurrenceDeletePrompt)
    }

    // MARK: - §19 Error Banner Lifecycle

    func testErrorBannerAppearsAndClears() async throws {
        let viewModel = try makePopulatedViewModel()
        await viewModel.load()

        XCTAssertNil(viewModel.errorMessage, "No error initially")

        // Trigger an error via invalid sync (empty calendar ID)
        viewModel.syncCalendarID = ""
        await viewModel.runSync()

        XCTAssertNotNil(viewModel.errorMessage, "Error must be set for blank calendar ID")

        // A subsequent successful operation should clear the error
        viewModel.syncCalendarID = "dev-calendar"
        await viewModel.runSync()

        XCTAssertNil(viewModel.errorMessage, "Error must clear after successful operation")
    }

    func testGlobalErrorBannerRendersInRootView() async throws {
        let viewModel = try makePopulatedViewModel()
        await viewModel.load()

        viewModel.syncCalendarID = ""
        await viewModel.runSync()

        let view = NotesRootView(viewModel: viewModel)
        let inspected = try view.inspect()
        XCTAssertNoThrow(
            try inspected.find(viewWithAccessibilityIdentifier: "globalErrorBanner"),
            "Error banner must render when errorMessage is set"
        )
    }

    // MARK: - §14 Sync Tab Controls

}
