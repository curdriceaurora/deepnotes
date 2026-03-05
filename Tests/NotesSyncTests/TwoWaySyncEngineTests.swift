import Foundation
import XCTest
@testable import NotesDomain
@testable import NotesStorage
@testable import NotesSync

final class TwoWaySyncEngineTests: XCTestCase {
    func testSmoke_RunOncePushesTaskAndCreatesBinding() async throws {
        let store = try makeStore()
        let provider = InMemoryCalendarProvider()

        let task = try Task(
            stableID: "task-push-1",
            title: "Call supplier",
            details: "Confirm schedule",
            dueStart: Date(timeIntervalSince1970: 1_700_000_000),
            dueEnd: Date(timeIntervalSince1970: 1_700_000_900),
            status: .next,
            priority: 4,
            recurrenceRule: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        let persisted = try await store.upsertTask(task)

        let engine = TwoWaySyncEngine(
            taskStore: store,
            bindingStore: store,
            checkpointStore: store,
            calendarProvider: provider,
        )

        let report = try await engine.runOnce(
            configuration: SyncEngineConfiguration(
                checkpointID: "default",
                calendarID: "calendar-1",
                taskBatchSize: 100,
                policy: .lastWriteWins,
            ),
        )

        XCTAssertEqual(report.tasksPushed, 1)

        let binding = try await store.fetchBinding(taskID: persisted.id, calendarID: "calendar-1")
        XCTAssertNotNil(binding?.eventIdentifier)
        let eventCount = await provider.eventCount(calendarID: "calendar-1")
        XCTAssertEqual(eventCount, 1)
    }

    func testSmoke_RunOnceImportsCalendarEventAsTask() async throws {
        let store = try makeStore()
        let provider = InMemoryCalendarProvider()

        let seededEvent = try CalendarEvent(
            eventIdentifier: nil,
            externalIdentifier: nil,
            calendarID: "calendar-2",
            title: "Imported from calendar",
            notes: "task-stable-id:task-import-1\n\nCaptured externally",
            startDate: Date(timeIntervalSince1970: 1_700_100_000),
            endDate: Date(timeIntervalSince1970: 1_700_100_900),
            recurrenceRule: nil,
            isCompleted: false,
            updatedAt: Date(timeIntervalSince1970: 1_700_100_000),
            sourceStableID: "task-import-1",
        )
        await provider.seed(event: seededEvent)

        let engine = TwoWaySyncEngine(
            taskStore: store,
            bindingStore: store,
            checkpointStore: store,
            calendarProvider: provider,
        )

        let report = try await engine.runOnce(
            configuration: SyncEngineConfiguration(
                checkpointID: "import",
                calendarID: "calendar-2",
                taskBatchSize: 100,
                policy: .lastWriteWins,
            ),
        )

        XCTAssertEqual(report.tasksImported, 1)

        let importedTask = try await store.fetchTaskByStableID("task-import-1")
        XCTAssertEqual(importedTask?.title, "Imported from calendar")

        let binding = try await store.fetchBinding(taskID: XCTUnwrap(importedTask?.id), calendarID: "calendar-2")
        XCTAssertNotNil(binding)
    }

    func testSmoke_CalendarDeletionCreatesTaskTombstone() async throws {
        let store = try makeStore()
        let provider = InMemoryCalendarProvider()

        let task = try Task(
            stableID: "task-delete-flow",
            title: "Delete flow",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        let persisted = try await store.upsertTask(task)

        let engine = TwoWaySyncEngine(
            taskStore: store,
            bindingStore: store,
            checkpointStore: store,
            calendarProvider: provider,
        )

        _ = try await engine.runOnce(
            configuration: SyncEngineConfiguration(
                checkpointID: "delete-flow",
                calendarID: "calendar-3",
                taskBatchSize: 100,
                policy: .lastWriteWins,
            ),
        )

        let binding = try await store.fetchBinding(taskID: persisted.id, calendarID: "calendar-3")
        XCTAssertNotNil(binding?.eventIdentifier)

        try await provider.deleteEvent(eventIdentifier: XCTUnwrap(binding?.eventIdentifier), calendarID: "calendar-3")

        let report = try await engine.runOnce(
            configuration: SyncEngineConfiguration(
                checkpointID: "delete-flow",
                calendarID: "calendar-3",
                taskBatchSize: 100,
                policy: .lastWriteWins,
            ),
        )

        XCTAssertEqual(report.tasksDeletedFromCalendar, 1)

        let tombstoned = try await store.fetchTask(id: persisted.id)
        XCTAssertNotNil(tombstoned?.deletedAt)
    }

    private func makeStore() throws -> SQLiteStore {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-engine-sync-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try SQLiteStore(databaseURL: folder.appendingPathComponent("notes.sqlite"))
    }
}
