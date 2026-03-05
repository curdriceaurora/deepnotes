// swiftlint:disable file_length type_body_length function_body_length
import Foundation
import XCTest
@testable import NotesDomain
@testable import NotesStorage
@testable import NotesSync

final class TwoWaySyncEngineEdgeCaseTests: XCTestCase {
    func testSmoke_RunOnceThrowsWhenUpsertEventHasNoIdentifier() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        let task = try Task(stableID: "task-no-id", title: "A", updatedAt: Date(timeIntervalSince1970: 100))
        _ = try await store.upsertTask(task)

        let returned = try CalendarEvent(
            eventIdentifier: nil,
            externalIdentifier: nil,
            calendarID: "cal",
            title: "A",
            updatedAt: Date(timeIntervalSince1970: 101),
        )
        await provider.queueUpsertResponse(.success(returned))

        let engine = makeEngine(store: store, provider: provider)

        await XCTAssertThrowsErrorAsync(
            try await engine.runOnce(configuration: SyncEngineConfiguration(checkpointID: "default", calendarID: "cal")),
        ) { error in
            guard case .missingEventIdentifier = error as? SyncError else {
                return XCTFail("Expected missingEventIdentifier, got \(error)")
            }
        }
    }

    func testSmoke_RunOnceRetriesTransientUpsertAndCapturesDiagnostic() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        let task = try Task(stableID: "task-retry", title: "Retry task", updatedAt: Date(timeIntervalSince1970: 100))
        _ = try await store.upsertTask(task)

        await provider.queueUpsertResponse(.failure(CalendarProviderError.transient(reason: "timeout")))
        let successful = try CalendarEvent(
            eventIdentifier: "evt-retry",
            externalIdentifier: "ext-retry",
            calendarID: "cal",
            title: "Retry task",
            updatedAt: Date(timeIntervalSince1970: 101),
            sourceStableID: "task-retry",
        )
        await provider.queueUpsertResponse(.success(successful))

        let engine = makeEngine(store: store, provider: provider)
        let report = try await engine.runOnce(
            configuration: SyncEngineConfiguration(
                checkpointID: "default",
                calendarID: "cal",
                providerMaxRetryAttempts: 2,
                providerRetryBaseDelayMilliseconds: 1,
            ),
        )

        XCTAssertEqual(report.tasksPushed, 1)
        let upserts = await provider.upsertedEvents
        XCTAssertEqual(upserts.count, 2)

        let retryDiagnostics = report.diagnostics.filter { $0.operation == .pushTaskUpsert }
        XCTAssertFalse(retryDiagnostics.isEmpty)
        XCTAssertEqual(retryDiagnostics.first?.severity, .warning)
        XCTAssertEqual(retryDiagnostics.first?.attempt, 1)
        XCTAssertTrue(retryDiagnostics.first?.providerError?.contains("timeout") == true)
    }

    func testRunOnceDoesNotRetryPermanentUpsertError() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        let task = try Task(stableID: "task-permanent", title: "Permanent failure", updatedAt: Date(timeIntervalSince1970: 100))
        _ = try await store.upsertTask(task)
        await provider.queueUpsertResponse(.failure(CalendarProviderError.permanent(reason: "invalid credentials")))

        let engine = makeEngine(store: store, provider: provider)

        await XCTAssertThrowsErrorAsync(
            try await engine.runOnce(
                configuration: SyncEngineConfiguration(
                    checkpointID: "default",
                    calendarID: "cal",
                    providerMaxRetryAttempts: 5,
                    providerRetryBaseDelayMilliseconds: 0,
                ),
            ),
        )

        let upserts = await provider.upsertedEvents
        XCTAssertEqual(upserts.count, 1)
    }

    func testRunOnceRetriesTransientFetchChangesAndCapturesDiagnostic() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        await provider.queueFetchResult(.failure(CalendarProviderError.transient(reason: "network lost")))
        await provider.queueFetchBatch(CalendarChangeBatch(changes: [], nextToken: "next-token"))

        let engine = makeEngine(store: store, provider: provider)
        let report = try await engine.runOnce(
            configuration: SyncEngineConfiguration(
                checkpointID: "default",
                calendarID: "cal",
                providerMaxRetryAttempts: 2,
                providerRetryBaseDelayMilliseconds: 0,
            ),
        )

        XCTAssertEqual(report.finalCalendarToken, "next-token")
        let calls = await provider.fetchChangesCallCount
        XCTAssertEqual(calls, 2)

        let diagnostics = report.diagnostics.filter { $0.operation == .pullCalendarChanges }
        XCTAssertFalse(diagnostics.isEmpty)
        XCTAssertEqual(diagnostics.first?.severity, .warning)
        XCTAssertEqual(diagnostics.first?.attempt, 1)
    }

    func testRunOnceRetriesForRetryableURLError() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        let task = try Task(stableID: "task-url-retry", title: "URL retry", updatedAt: Date(timeIntervalSince1970: 100))
        _ = try await store.upsertTask(task)

        await provider.queueUpsertResponse(.failure(URLError(.timedOut)))
        let successful = try CalendarEvent(
            eventIdentifier: "evt-url",
            externalIdentifier: "ext-url",
            calendarID: "cal",
            title: "URL retry",
            updatedAt: Date(timeIntervalSince1970: 101),
            sourceStableID: "task-url-retry",
        )
        await provider.queueUpsertResponse(.success(successful))

        let engine = makeEngine(store: store, provider: provider)
        let report = try await engine.runOnce(
            configuration: SyncEngineConfiguration(
                checkpointID: "default",
                calendarID: "cal",
                providerMaxRetryAttempts: 2,
                providerRetryBaseDelayMilliseconds: 0,
            ),
        )

        XCTAssertEqual(report.tasksPushed, 1)
        let upserts = await provider.upsertedEvents
        XCTAssertEqual(upserts.count, 2)
    }

    func testRunOnceDoesNotRetryForNonRetryableURLError() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        let task = try Task(stableID: "task-url-no-retry", title: "URL no retry", updatedAt: Date(timeIntervalSince1970: 100))
        _ = try await store.upsertTask(task)

        await provider.queueUpsertResponse(.failure(URLError(.badURL)))

        let engine = makeEngine(store: store, provider: provider)
        await XCTAssertThrowsErrorAsync(
            try await engine.runOnce(
                configuration: SyncEngineConfiguration(
                    checkpointID: "default",
                    calendarID: "cal",
                    providerMaxRetryAttempts: 3,
                    providerRetryBaseDelayMilliseconds: 0,
                ),
            ),
        )

        let upserts = await provider.upsertedEvents
        XCTAssertEqual(upserts.count, 1)
    }

    func testRunOnceRetriesForRetryableCustomNSErrorInURLDomain() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        let task = try Task(stableID: "task-nserror-retry", title: "NSError retry", updatedAt: Date(timeIntervalSince1970: 100))
        _ = try await store.upsertTask(task)

        await provider.queueUpsertResponse(.failure(CustomURLDomainError(code: URLError.networkConnectionLost.rawValue)))
        let successful = try CalendarEvent(
            eventIdentifier: "evt-ns",
            externalIdentifier: "ext-ns",
            calendarID: "cal",
            title: "NSError retry",
            updatedAt: Date(timeIntervalSince1970: 101),
            sourceStableID: "task-nserror-retry",
        )
        await provider.queueUpsertResponse(.success(successful))

        let engine = makeEngine(store: store, provider: provider)
        let report = try await engine.runOnce(
            configuration: SyncEngineConfiguration(
                checkpointID: "default",
                calendarID: "cal",
                providerMaxRetryAttempts: 2,
                providerRetryBaseDelayMilliseconds: 0,
            ),
        )

        XCTAssertEqual(report.tasksPushed, 1)
        let upserts = await provider.upsertedEvents
        XCTAssertEqual(upserts.count, 2)
    }

    func testRunOnceDoesNotRetryForNonRetryableCustomNSErrorInURLDomain() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        let task = try Task(stableID: "task-nserror-no-retry", title: "NSError no retry", updatedAt: Date(timeIntervalSince1970: 100))
        _ = try await store.upsertTask(task)

        await provider.queueUpsertResponse(.failure(CustomURLDomainError(code: URLError.unsupportedURL.rawValue)))

        let engine = makeEngine(store: store, provider: provider)
        await XCTAssertThrowsErrorAsync(
            try await engine.runOnce(
                configuration: SyncEngineConfiguration(
                    checkpointID: "default",
                    calendarID: "cal",
                    providerMaxRetryAttempts: 3,
                    providerRetryBaseDelayMilliseconds: 0,
                ),
            ),
        )

        let upserts = await provider.upsertedEvents
        XCTAssertEqual(upserts.count, 1)
    }

    func testDeletedTaskWithoutBindingDoesNotCallProviderDelete() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        var task = try Task(stableID: "task-deleted", title: "A", updatedAt: Date(timeIntervalSince1970: 100))
        task = try await store.upsertTask(task)
        try await store.tombstoneTask(id: task.id, at: Date(timeIntervalSince1970: 110))

        let engine = makeEngine(store: store, provider: provider)
        let report = try await engine.runOnce(
            configuration: SyncEngineConfiguration(
                checkpointID: "default",
                calendarID: "cal",
                policy: .calendarPriority,
            ),
        )

        XCTAssertEqual(report.eventsDeletedFromTasks, 0)
        let deleted = await provider.deletedEventIdentifiers
        XCTAssertTrue(deleted.isEmpty)
    }

    func testDeletedTaskWithBindingWithoutEventIdentifierStillTombstonesBinding() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        var task = try Task(stableID: "task-deleted-binding", title: "A", updatedAt: Date(timeIntervalSince1970: 100))
        task = try await store.upsertTask(task)

        try await store.upsertBinding(CalendarBinding(taskID: task.id, calendarID: "cal", eventIdentifier: nil, externalIdentifier: "ext-1"))
        try await store.tombstoneTask(id: task.id, at: Date(timeIntervalSince1970: 110))

        let engine = makeEngine(store: store, provider: provider)
        let report = try await engine.runOnce(configuration: SyncEngineConfiguration(checkpointID: "default", calendarID: "cal"))

        XCTAssertEqual(report.eventsDeletedFromTasks, 1)
        let deleted = await provider.deletedEventIdentifiers
        XCTAssertTrue(deleted.isEmpty)

        let binding = try await store.fetchBinding(taskID: task.id, calendarID: "cal")
        XCTAssertNotNil(binding?.deletedAt)
    }

    func testUpsertEventWithDifferentCalendarIsIgnored() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        let incoming = try CalendarEvent(
            eventIdentifier: "e-1",
            externalIdentifier: "ext-1",
            calendarID: "other-cal",
            title: "Outside",
            updatedAt: Date(timeIntervalSince1970: 120),
        )
        await provider.queueFetchBatch(CalendarChangeBatch(changes: [.upsert(incoming)], nextToken: "next"))

        let engine = makeEngine(store: store, provider: provider)
        let report = try await engine.runOnce(configuration: SyncEngineConfiguration(checkpointID: "default", calendarID: "cal"))

        XCTAssertEqual(report.eventsPulled, 1)
        XCTAssertEqual(report.tasksImported, 0)
        XCTAssertEqual(report.tasksUpdatedFromCalendar, 0)
    }

    func testUpsertWithBindingButMissingTaskIsIgnored() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        let ghostTaskID = UUID()
        try await store.upsertBinding(CalendarBinding(
            taskID: ghostTaskID, calendarID: "cal",
            eventIdentifier: "e-2", externalIdentifier: "ext-2",
        ))

        let incoming = try CalendarEvent(
            eventIdentifier: "e-2",
            externalIdentifier: "ext-2",
            calendarID: "cal",
            title: "Ghost",
            updatedAt: Date(timeIntervalSince1970: 120),
        )
        await provider.queueFetchBatch(CalendarChangeBatch(changes: [.upsert(incoming)], nextToken: "next"))

        let engine = makeEngine(store: store, provider: provider)
        let report = try await engine.runOnce(configuration: SyncEngineConfiguration(checkpointID: "default", calendarID: "cal"))

        XCTAssertEqual(report.tasksImported, 0)
        XCTAssertEqual(report.tasksUpdatedFromCalendar, 0)
    }

    func testRecurrenceExceptionWithoutBindingDoesNotImportTask() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        let exception = try CalendarEvent(
            eventIdentifier: "exception-free",
            externalIdentifier: "ext-series-free",
            calendarID: "cal",
            title: "Detached exception",
            recurrenceExceptionDate: Date(timeIntervalSince1970: 118),
            updatedAt: Date(timeIntervalSince1970: 120),
            sourceStableID: nil,
        )
        await provider.queueFetchBatch(CalendarChangeBatch(changes: [.upsert(exception)], nextToken: "next"))

        let engine = makeEngine(store: store, provider: provider)
        let report = try await engine.runOnce(configuration: SyncEngineConfiguration(checkpointID: "default", calendarID: "cal"))

        XCTAssertEqual(report.tasksImported, 0)
        XCTAssertEqual(report.tasksUpdatedFromCalendar, 0)
    }

    func testRecurrenceExceptionWithBindingUpdatesExistingTask() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        var task = try Task(stableID: "series-task", title: "Series Root", updatedAt: Date(timeIntervalSince1970: 100))
        task = try await store.upsertTask(task)
        try await store.upsertBinding(
            CalendarBinding(
                taskID: task.id,
                calendarID: "cal",
                eventIdentifier: nil,
                externalIdentifier: "ext-series-task",
                lastTaskVersion: task.version,
                lastEventUpdatedAt: Date(timeIntervalSince1970: 101),
                lastSyncedAt: Date(timeIntervalSince1970: 101),
            ),
        )
        try await store.saveCheckpoint(
            SyncCheckpoint(
                id: "default",
                taskVersionCursor: task.version,
                calendarToken: "t1",
                updatedAt: Date(timeIntervalSince1970: 102),
            ),
        )

        let exception = try CalendarEvent(
            eventIdentifier: "event-detached",
            externalIdentifier: "ext-series-task",
            calendarID: "cal",
            title: "Series exception update",
            recurrenceExceptionDate: Date(timeIntervalSince1970: 149),
            updatedAt: Date(timeIntervalSince1970: 150),
            sourceStableID: task.stableID,
        )
        await provider.queueFetchBatch(CalendarChangeBatch(changes: [.upsert(exception)], nextToken: "t2"))

        let engine = makeEngine(store: store, provider: provider)
        let report = try await engine.runOnce(
            configuration: SyncEngineConfiguration(
                checkpointID: "default",
                calendarID: "cal",
                policy: .calendarPriority,
            ),
        )

        XCTAssertEqual(report.tasksUpdatedFromCalendar, 1)
        let updated = try await store.fetchTask(id: task.id)
        XCTAssertEqual(updated?.title, "Series exception update")
    }

    func testTaskWinsConflictRepushesTaskToCalendar() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        var task = try Task(stableID: "task-conflict", title: "Task Wins", updatedAt: Date(timeIntervalSince1970: 300), version: 0)
        task = try await store.upsertTask(task)

        try await store.upsertBinding(
            CalendarBinding(
                taskID: task.id,
                calendarID: "cal",
                eventIdentifier: "e-3",
                externalIdentifier: "ext-3",
                lastTaskVersion: task.version,
                lastEventUpdatedAt: Date(timeIntervalSince1970: 100),
                lastSyncedAt: Date(timeIntervalSince1970: 200),
            ),
        )

        try await store.saveCheckpoint(
            SyncCheckpoint(
                id: "default",
                taskVersionCursor: task.version,
                calendarToken: "token-1",
                updatedAt: Date(timeIntervalSince1970: 301),
            ),
        )

        let incoming = try CalendarEvent(
            eventIdentifier: "e-3",
            externalIdentifier: "ext-3",
            calendarID: "cal",
            title: "Calendar Edit",
            updatedAt: Date(timeIntervalSince1970: 250),
            sourceStableID: task.stableID,
        )
        await provider.queueFetchBatch(CalendarChangeBatch(changes: [.upsert(incoming)], nextToken: "token-2"))

        let engine = makeEngine(store: store, provider: provider)
        let report = try await engine.runOnce(
            configuration: SyncEngineConfiguration(
                checkpointID: "default",
                calendarID: "cal",
                policy: .taskPriority,
            ),
        )

        XCTAssertEqual(report.tasksUpdatedFromCalendar, 0)
        let upserts = await provider.upsertedEvents
        XCTAssertEqual(upserts.count, 1)
        XCTAssertEqual(upserts.first?.title, "Task Wins")
    }

    func testLastWriteWinsTieBreakerTaskRepushesTaskWhenNormalizedTimestampsEqual() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        var task = try Task(stableID: "task-tie-break", title: "Task tie", updatedAt: Date(timeIntervalSince1970: 250.9), version: 0)
        task = try await store.upsertTask(task)

        try await store.upsertBinding(
            CalendarBinding(
                taskID: task.id,
                calendarID: "cal",
                eventIdentifier: "event-tie-break",
                externalIdentifier: "ext-tie-break",
                lastTaskVersion: task.version,
                lastEventUpdatedAt: Date(timeIntervalSince1970: 200),
                lastSyncedAt: Date(timeIntervalSince1970: 200),
            ),
        )
        try await store.saveCheckpoint(
            SyncCheckpoint(
                id: "default",
                taskVersionCursor: task.version,
                calendarToken: "token-1",
                updatedAt: Date(timeIntervalSince1970: 251),
            ),
        )

        let incoming = try CalendarEvent(
            eventIdentifier: "event-tie-break",
            externalIdentifier: "ext-tie-break",
            calendarID: "cal",
            title: "Calendar tie",
            updatedAt: Date(timeIntervalSince1970: 250.2),
            sourceStableID: task.stableID,
        )
        await provider.queueFetchBatch(CalendarChangeBatch(changes: [.upsert(incoming)], nextToken: "token-2"))

        let engine = makeEngine(store: store, provider: provider)
        let report = try await engine.runOnce(
            configuration: SyncEngineConfiguration(
                checkpointID: "default",
                calendarID: "cal",
                policy: .lastWriteWins,
                timestampNormalizationSeconds: 1,
                lastWriteWinsTieBreaker: .task,
            ),
        )

        XCTAssertEqual(report.tasksUpdatedFromCalendar, 0)
        let upserts = await provider.upsertedEvents
        XCTAssertEqual(upserts.count, 1)
        XCTAssertEqual(upserts.first?.title, "Task tie")
    }

    func testFindBindingByExternalIdentifierPath() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        var task = try Task(stableID: "task-ext", title: "Initial", updatedAt: Date(timeIntervalSince1970: 100))
        task = try await store.upsertTask(task)

        try await store.upsertBinding(
            CalendarBinding(
                taskID: task.id,
                calendarID: "cal",
                eventIdentifier: nil,
                externalIdentifier: "ext-lookup",
                lastTaskVersion: task.version,
                lastEventUpdatedAt: Date(timeIntervalSince1970: 110),
                lastSyncedAt: Date(timeIntervalSince1970: 110),
            ),
        )

        try await store.saveCheckpoint(
            SyncCheckpoint(
                id: "default",
                taskVersionCursor: task.version,
                calendarToken: "t1",
                updatedAt: Date(timeIntervalSince1970: 111),
            ),
        )

        let incoming = try CalendarEvent(
            eventIdentifier: nil,
            externalIdentifier: "ext-lookup",
            calendarID: "cal",
            title: "Updated from external",
            updatedAt: Date(timeIntervalSince1970: 160),
            sourceStableID: task.stableID,
        )

        await provider.queueFetchBatch(CalendarChangeBatch(changes: [.upsert(incoming)], nextToken: "t2"))

        let engine = makeEngine(store: store, provider: provider)
        let report = try await engine.runOnce(
            configuration: SyncEngineConfiguration(
                checkpointID: "default",
                calendarID: "cal",
                policy: .calendarPriority,
            ),
        )

        XCTAssertEqual(report.eventsPulled, 1)
        XCTAssertEqual(report.tasksUpdatedFromCalendar, 1)
        let repushed = await provider.upsertedEvents
        XCTAssertTrue(repushed.isEmpty)
        let updated = try await store.fetchTask(id: task.id)
        XCTAssertEqual(updated?.title, "Updated from external")
    }

    func testDeletionByExternalIdentifierTombstonesTask() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        var task = try Task(stableID: "task-del-ext", title: "Delete me", updatedAt: Date(timeIntervalSince1970: 100))
        task = try await store.upsertTask(task)
        try await store.upsertBinding(CalendarBinding(
            taskID: task.id, calendarID: "cal",
            eventIdentifier: nil, externalIdentifier: "ext-del",
        ))

        let deletion = CalendarDeletion(
            eventIdentifier: nil, externalIdentifier: "ext-del",
            calendarID: "cal", deletedAt: Date(timeIntervalSince1970: 200),
        )
        await provider.queueFetchBatch(CalendarChangeBatch(changes: [.delete(deletion)], nextToken: "next"))

        let engine = makeEngine(store: store, provider: provider)
        let report = try await engine.runOnce(configuration: SyncEngineConfiguration(checkpointID: "default", calendarID: "cal"))

        XCTAssertEqual(report.tasksDeletedFromCalendar, 1)
        let tombstoned = try await store.fetchTask(id: task.id)
        XCTAssertNotNil(tombstoned?.deletedAt)
    }

    func testDeletionWithCalendarMismatchIsIgnored() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        let deletion = CalendarDeletion(
            eventIdentifier: "e-mismatch",
            externalIdentifier: nil,
            calendarID: "other-cal",
            deletedAt: Date(timeIntervalSince1970: 200),
        )
        await provider.queueFetchBatch(CalendarChangeBatch(changes: [.delete(deletion)], nextToken: "next"))

        let engine = makeEngine(store: store, provider: provider)
        let report = try await engine.runOnce(
            configuration: SyncEngineConfiguration(checkpointID: "default", calendarID: "cal"),
        )

        XCTAssertEqual(report.eventsPulled, 1)
        XCTAssertEqual(report.tasksDeletedFromCalendar, 0)
    }

    func testDeletionWithoutBindingIsIgnored() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        let deletion = CalendarDeletion(
            eventIdentifier: "missing-event-id",
            externalIdentifier: nil,
            calendarID: "cal",
            deletedAt: Date(timeIntervalSince1970: 200),
        )
        await provider.queueFetchBatch(CalendarChangeBatch(changes: [.delete(deletion)], nextToken: "next"))

        let engine = makeEngine(store: store, provider: provider)
        let report = try await engine.runOnce(
            configuration: SyncEngineConfiguration(checkpointID: "default", calendarID: "cal"),
        )

        XCTAssertEqual(report.eventsPulled, 1)
        XCTAssertEqual(report.tasksDeletedFromCalendar, 0)
    }

    func testDeletedTaskWithBindingAndEventIdentifierCallsProviderDelete() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        var task = try Task(stableID: "task-delete-id", title: "To delete in calendar", updatedAt: Date(timeIntervalSince1970: 100))
        task = try await store.upsertTask(task)
        try await store.upsertBinding(
            CalendarBinding(
                taskID: task.id,
                calendarID: "cal",
                eventIdentifier: "event-123",
                externalIdentifier: "ext-123",
            ),
        )
        try await store.tombstoneTask(id: task.id, at: Date(timeIntervalSince1970: 150))

        let engine = makeEngine(store: store, provider: provider)
        let report = try await engine.runOnce(
            configuration: SyncEngineConfiguration(checkpointID: "default", calendarID: "cal"),
        )

        XCTAssertEqual(report.eventsDeletedFromTasks, 1)
        let deleted = await provider.deletedEventIdentifiers
        XCTAssertEqual(deleted, ["event-123"])
    }

    func testTaskWinsFallbacksToBindingIdentifiersWhenProviderReturnsNilIdentifiers() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        var task = try Task(
            stableID: "task-fallback-taskwins", title: "Prefer task",
            updatedAt: Date(timeIntervalSince1970: 300), version: 0,
        )
        task = try await store.upsertTask(task)
        try await store.upsertBinding(
            CalendarBinding(
                taskID: task.id,
                calendarID: "cal",
                eventIdentifier: "event-fallback",
                externalIdentifier: "ext-fallback",
                lastTaskVersion: task.version,
                lastEventUpdatedAt: Date(timeIntervalSince1970: 100),
                lastSyncedAt: Date(timeIntervalSince1970: 200),
            ),
        )
        try await store.saveCheckpoint(
            SyncCheckpoint(
                id: "default",
                taskVersionCursor: task.version,
                calendarToken: "token-1",
                updatedAt: Date(timeIntervalSince1970: 301),
            ),
        )

        let incoming = try CalendarEvent(
            eventIdentifier: "event-fallback",
            externalIdentifier: "ext-fallback",
            calendarID: "cal",
            title: "Calendar edit",
            updatedAt: Date(timeIntervalSince1970: 250),
            sourceStableID: task.stableID,
        )
        await provider.queueFetchBatch(CalendarChangeBatch(changes: [.upsert(incoming)], nextToken: "token-2"))

        let persistedWithMissingIdentifiers = try CalendarEvent(
            eventIdentifier: nil,
            externalIdentifier: nil,
            calendarID: "cal",
            title: "Persisted",
            updatedAt: Date(timeIntervalSince1970: 350),
            sourceStableID: task.stableID,
        )
        await provider.queueUpsertResponse(.success(persistedWithMissingIdentifiers))

        let engine = makeEngine(store: store, provider: provider)
        _ = try await engine.runOnce(
            configuration: SyncEngineConfiguration(
                checkpointID: "default",
                calendarID: "cal",
                policy: .taskPriority,
            ),
        )

        let binding = try await store.fetchBinding(taskID: task.id, calendarID: "cal")
        XCTAssertEqual(binding?.eventIdentifier, "event-fallback")
        XCTAssertEqual(binding?.externalIdentifier, "ext-fallback")
    }

    func testEventWinsFallsBackToBindingExternalIdentifierWhenIncomingMissingExternal() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        var task = try Task(stableID: "task-fallback-eventwins", title: "Initial", updatedAt: Date(timeIntervalSince1970: 100), version: 0)
        task = try await store.upsertTask(task)
        try await store.upsertBinding(
            CalendarBinding(
                taskID: task.id,
                calendarID: "cal",
                eventIdentifier: "event-evtwins",
                externalIdentifier: "ext-existing",
                lastTaskVersion: task.version,
                lastEventUpdatedAt: Date(timeIntervalSince1970: 110),
                lastSyncedAt: Date(timeIntervalSince1970: 110),
            ),
        )
        try await store.saveCheckpoint(
            SyncCheckpoint(
                id: "default",
                taskVersionCursor: task.version,
                calendarToken: "t1",
                updatedAt: Date(timeIntervalSince1970: 111),
            ),
        )

        let incoming = try CalendarEvent(
            eventIdentifier: "event-evtwins",
            externalIdentifier: nil,
            calendarID: "cal",
            title: "Calendar update",
            updatedAt: Date(timeIntervalSince1970: 160),
            sourceStableID: task.stableID,
        )
        await provider.queueFetchBatch(CalendarChangeBatch(changes: [.upsert(incoming)], nextToken: "t2"))

        let engine = makeEngine(store: store, provider: provider)
        let report = try await engine.runOnce(
            configuration: SyncEngineConfiguration(
                checkpointID: "default",
                calendarID: "cal",
                policy: .calendarPriority,
            ),
        )

        XCTAssertEqual(report.tasksUpdatedFromCalendar, 1)
        let binding = try await store.fetchBinding(taskID: task.id, calendarID: "cal")
        XCTAssertEqual(binding?.externalIdentifier, "ext-existing")
    }

    func testRunOncePushesDatedSyncedNoteAndCreatesBinding() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        var note = Note(
            stableID: "note-push-1",
            title: "Dated note",
            body: "Body",
            dateStart: Date(timeIntervalSince1970: 1_700_010_000),
            dateEnd: Date(timeIntervalSince1970: 1_700_010_900),
            isAllDay: false,
            recurrenceRule: "FREQ=WEEKLY",
            calendarSyncEnabled: true,
            updatedAt: Date(timeIntervalSince1970: 1_700_010_000),
        )
        note = try await store.upsertNote(note)

        let engine = makeEngine(store: store, provider: provider, includeNoteStore: true)
        _ = try await engine.runOnce(configuration: SyncEngineConfiguration(checkpointID: "default", calendarID: "cal"))

        let upserts = await provider.upsertedEvents
        XCTAssertEqual(upserts.count, 1)
        XCTAssertTrue(upserts[0].notes?.contains("entity-type:note") == true)
        XCTAssertTrue(upserts[0].notes?.contains("note-stable-id:note-push-1") == true)

        let binding = try await store.fetchBinding(entityType: .note, entityID: note.id, calendarID: "cal")
        XCTAssertEqual(binding?.entityType, .note)
        XCTAssertNotNil(binding?.eventIdentifier)

        let checkpoint = try await store.fetchCheckpoint(id: "default")
        XCTAssertEqual(checkpoint?.noteVersionCursor, note.version)
    }

    func testRunOnceSkipsUnsyncedOrUndatedNotesButAdvancesCheckpointCursor() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        let undated = try await store.upsertNote(
            Note(
                stableID: "note-skip-undated",
                title: "Undated",
                body: "",
                calendarSyncEnabled: true,
                updatedAt: Date(timeIntervalSince1970: 100),
            ),
        )
        let syncDisabled = try await store.upsertNote(
            Note(
                stableID: "note-skip-sync-disabled",
                title: "Sync disabled",
                body: "",
                dateStart: Date(timeIntervalSince1970: 110),
                calendarSyncEnabled: false,
                updatedAt: Date(timeIntervalSince1970: 110),
            ),
        )

        let engine = makeEngine(store: store, provider: provider, includeNoteStore: true)
        _ = try await engine.runOnce(configuration: SyncEngineConfiguration(checkpointID: "default", calendarID: "cal"))

        let upserts = await provider.upsertedEvents
        XCTAssertTrue(upserts.isEmpty)

        let checkpoint = try await store.fetchCheckpoint(id: "default")
        XCTAssertEqual(checkpoint?.noteVersionCursor, max(undated.version, syncDisabled.version))
    }

    func testRunOnceThrowsWhenNotePushPersistsWithoutEventIdentifier() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        _ = try await store.upsertNote(
            Note(
                stableID: "note-no-event-id",
                title: "Missing event identifier",
                body: "",
                dateStart: Date(timeIntervalSince1970: 100),
                calendarSyncEnabled: true,
                updatedAt: Date(timeIntervalSince1970: 100),
            ),
        )

        let persisted = try CalendarEvent(
            eventIdentifier: nil,
            externalIdentifier: "ext-note-no-id",
            calendarID: "cal",
            title: "Missing event identifier",
            updatedAt: Date(timeIntervalSince1970: 101),
            sourceEntityType: .note,
            sourceStableID: "note-no-event-id",
        )
        await provider.queueUpsertResponse(.success(persisted))

        let engine = makeEngine(store: store, provider: provider, includeNoteStore: true)
        await XCTAssertThrowsErrorAsync(
            try await engine.runOnce(configuration: SyncEngineConfiguration(checkpointID: "default", calendarID: "cal")),
        ) { error in
            guard case .missingEventIdentifier = error as? SyncError else {
                return XCTFail("Expected missingEventIdentifier, got \(error)")
            }
        }
    }

    func testRunOnceDeletedNoteWithoutBindingDoesNotCallProviderDelete() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        var note = try await store.upsertNote(
            Note(
                stableID: "note-delete-unbound",
                title: "Delete unbound",
                body: "",
                updatedAt: Date(timeIntervalSince1970: 100),
            ),
        )
        try await store.tombstoneNote(id: note.id, at: Date(timeIntervalSince1970: 120))
        let fetchedNoteAfterTombstone = try await store.fetchNote(id: note.id)
        note = try XCTUnwrap(fetchedNoteAfterTombstone)

        let engine = makeEngine(store: store, provider: provider, includeNoteStore: true)
        _ = try await engine.runOnce(configuration: SyncEngineConfiguration(checkpointID: "default", calendarID: "cal"))

        let deleted = await provider.deletedEventIdentifiers
        XCTAssertTrue(deleted.isEmpty)

        let checkpoint = try await store.fetchCheckpoint(id: "default")
        XCTAssertEqual(checkpoint?.noteVersionCursor, note.version)
    }

    func testRunOnceDeletedNoteWithBindingWithoutEventIdentifierOnlyTombstonesBinding() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        var note = try await store.upsertNote(
            Note(
                stableID: "note-delete-binding-no-event",
                title: "Delete no event",
                body: "",
                updatedAt: Date(timeIntervalSince1970: 100),
            ),
        )
        try await store.upsertBinding(
            CalendarBinding(
                entityType: .note,
                entityID: note.id,
                calendarID: "cal",
                eventIdentifier: nil,
                externalIdentifier: "ext-note-no-event",
            ),
        )
        try await store.tombstoneNote(id: note.id, at: Date(timeIntervalSince1970: 130))
        let fetchedNoteAfterTombstone = try await store.fetchNote(id: note.id)
        note = try XCTUnwrap(fetchedNoteAfterTombstone)

        let engine = makeEngine(store: store, provider: provider, includeNoteStore: true)
        _ = try await engine.runOnce(configuration: SyncEngineConfiguration(checkpointID: "default", calendarID: "cal"))

        let deleted = await provider.deletedEventIdentifiers
        XCTAssertTrue(deleted.isEmpty)

        let binding = try await store.fetchBinding(entityType: .note, entityID: note.id, calendarID: "cal")
        XCTAssertNotNil(binding?.deletedAt)
    }

    func testRunOnceDeletedNoteWithBindingEventIdentifierDeletesCalendarEvent() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        var note = try await store.upsertNote(
            Note(
                stableID: "note-delete-binding-event",
                title: "Delete event",
                body: "",
                updatedAt: Date(timeIntervalSince1970: 100),
            ),
        )
        try await store.upsertBinding(
            CalendarBinding(
                entityType: .note,
                entityID: note.id,
                calendarID: "cal",
                eventIdentifier: "event-note-delete",
                externalIdentifier: "ext-note-delete",
            ),
        )
        try await store.tombstoneNote(id: note.id, at: Date(timeIntervalSince1970: 130))
        let fetchedNoteAfterTombstone = try await store.fetchNote(id: note.id)
        note = try XCTUnwrap(fetchedNoteAfterTombstone)

        let engine = makeEngine(store: store, provider: provider, includeNoteStore: true)
        _ = try await engine.runOnce(configuration: SyncEngineConfiguration(checkpointID: "default", calendarID: "cal"))

        let deleted = await provider.deletedEventIdentifiers
        XCTAssertEqual(deleted, ["event-note-delete"])

        let binding = try await store.fetchBinding(entityType: .note, entityID: note.id, calendarID: "cal")
        XCTAssertNotNil(binding?.deletedAt)
    }

    func testPullNoteEventWithoutNoteStoreIsSkippedWithDiagnostic() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        let noteEvent = try CalendarEvent(
            eventIdentifier: "event-note-no-store",
            externalIdentifier: "ext-note-no-store",
            calendarID: "cal",
            title: "Note from calendar",
            notes: "entity-type:note\nnote-stable-id:note-external",
            updatedAt: Date(timeIntervalSince1970: 160),
            sourceEntityType: .note,
        )
        await provider.queueFetchBatch(CalendarChangeBatch(changes: [.upsert(noteEvent)], nextToken: "next"))

        let engine = makeEngine(store: store, provider: provider)
        let report = try await engine.runOnce(configuration: SyncEngineConfiguration(checkpointID: "default", calendarID: "cal"))

        XCTAssertEqual(report.tasksImported, 0)
        XCTAssertEqual(report.tasksUpdatedFromCalendar, 0)
        XCTAssertTrue(
            report.diagnostics.contains {
                $0.operation == .pullEventUpsert
                    && $0.entityType == .note
                    && $0.message.contains("note store is unavailable")
            },
        )
    }

    func testPullNoteEventWithMissingBoundNoteIsIgnored() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        let ghostNoteID = UUID()
        try await store.upsertBinding(
            CalendarBinding(
                entityType: .note,
                entityID: ghostNoteID,
                calendarID: "cal",
                eventIdentifier: "event-note-ghost",
                externalIdentifier: "ext-note-ghost",
            ),
        )

        let incoming = try CalendarEvent(
            eventIdentifier: "event-note-ghost",
            externalIdentifier: "ext-note-ghost",
            calendarID: "cal",
            title: "Ghost note",
            updatedAt: Date(timeIntervalSince1970: 160),
            sourceEntityType: .note,
        )
        await provider.queueFetchBatch(CalendarChangeBatch(changes: [.upsert(incoming)], nextToken: "next"))

        let engine = makeEngine(store: store, provider: provider, includeNoteStore: true)
        let report = try await engine.runOnce(configuration: SyncEngineConfiguration(checkpointID: "default", calendarID: "cal"))

        XCTAssertEqual(report.tasksImported, 0)
        XCTAssertEqual(report.tasksUpdatedFromCalendar, 0)
        XCTAssertTrue(
            report.diagnostics.contains {
                $0.operation == .pullEventUpsert
                    && $0.entityType == .note
                    && $0.message.contains("missing or deleted note")
            },
        )
    }

    func testPullNoteEventDetachedExceptionWithoutBindingIsSkipped() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        let incoming = try CalendarEvent(
            eventIdentifier: "event-note-exception",
            externalIdentifier: "ext-note-exception",
            calendarID: "cal",
            title: "Detached note exception",
            recurrenceExceptionDate: Date(timeIntervalSince1970: 155),
            updatedAt: Date(timeIntervalSince1970: 160),
            sourceEntityType: .note,
            sourceStableID: "note-series",
        )
        await provider.queueFetchBatch(CalendarChangeBatch(changes: [.upsert(incoming)], nextToken: "next"))

        let engine = makeEngine(store: store, provider: provider, includeNoteStore: true)
        let report = try await engine.runOnce(configuration: SyncEngineConfiguration(checkpointID: "default", calendarID: "cal"))

        XCTAssertEqual(report.tasksImported, 0)
        XCTAssertEqual(report.tasksUpdatedFromCalendar, 0)
        XCTAssertTrue(
            report.diagnostics.contains {
                $0.operation == .pullEventUpsert
                    && $0.entityType == .note
                    && $0.message.contains("detached recurrence exception")
            },
        )
    }

    func testPullNoteEventImportsNewNoteAndBinding() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        let incoming = try CalendarEvent(
            eventIdentifier: "event-note-import",
            externalIdentifier: "ext-note-import",
            calendarID: "cal",
            title: "Imported note",
            notes: "Imported body\n\nentity-type:note\nnote-stable-id:note-import-stable",
            startDate: Date(timeIntervalSince1970: 170),
            endDate: Date(timeIntervalSince1970: 200),
            isAllDay: true,
            recurrenceRule: "FREQ=DAILY",
            updatedAt: Date(timeIntervalSince1970: 180),
            sourceEntityType: .note,
        )
        await provider.queueFetchBatch(CalendarChangeBatch(changes: [.upsert(incoming)], nextToken: "next"))

        let engine = makeEngine(store: store, provider: provider, includeNoteStore: true)
        let report = try await engine.runOnce(configuration: SyncEngineConfiguration(checkpointID: "default", calendarID: "cal"))

        XCTAssertEqual(report.tasksImported, 1)
        let importedNote = try await store.fetchNoteByStableID("note-import-stable")
        XCTAssertEqual(importedNote?.title, "Imported note")
        XCTAssertEqual(importedNote?.isAllDay, true)
        XCTAssertEqual(importedNote?.calendarSyncEnabled, true)

        let binding = try await store.fetchBinding(entityType: .note, entityID: XCTUnwrap(importedNote?.id), calendarID: "cal")
        XCTAssertEqual(binding?.eventIdentifier, "event-note-import")
    }

    func testNoteConflictStaleEventRepushesLocalNote() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        var note = try await store.upsertNote(
            Note(
                stableID: "note-conflict-stale-event",
                title: "Local note title",
                body: "",
                dateStart: Date(timeIntervalSince1970: 100),
                calendarSyncEnabled: true,
                updatedAt: Date(timeIntervalSince1970: 210),
            ),
        )
        try await store.upsertBinding(
            CalendarBinding(
                entityType: .note,
                entityID: note.id,
                calendarID: "cal",
                eventIdentifier: "event-note-stale",
                externalIdentifier: "ext-note-stale",
                lastEntityVersion: note.version,
                lastEventUpdatedAt: Date(timeIntervalSince1970: 230),
                lastSyncedAt: Date(timeIntervalSince1970: 200),
            ),
        )
        try await store.saveCheckpoint(
            SyncCheckpoint(
                id: "default",
                taskVersionCursor: 0,
                noteVersionCursor: note.version,
                calendarToken: "t1",
                updatedAt: Date(timeIntervalSince1970: 231),
            ),
        )

        let incoming = try CalendarEvent(
            eventIdentifier: "event-note-stale",
            externalIdentifier: "ext-note-stale",
            calendarID: "cal",
            title: "Calendar stale title",
            updatedAt: Date(timeIntervalSince1970: 220),
            sourceEntityType: .note,
        )
        await provider.queueFetchBatch(CalendarChangeBatch(changes: [.upsert(incoming)], nextToken: "t2"))

        let engine = makeEngine(store: store, provider: provider, includeNoteStore: true)
        let report = try await engine.runOnce(configuration: SyncEngineConfiguration(checkpointID: "default", calendarID: "cal"))

        XCTAssertEqual(report.tasksUpdatedFromCalendar, 0)
        let upserts = await provider.upsertedEvents
        XCTAssertEqual(upserts.count, 1)
        let fetchedNote = try await store.fetchNote(id: note.id)
        note = try XCTUnwrap(fetchedNote)
        XCTAssertEqual(note.title, "Local note title")
    }

    func testNoteConflictChangeMatrixCoversSingleSideChanges() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        let unchanged = try await store.upsertNote(
            Note(
                stableID: "note-conflict-unchanged",
                title: "Unchanged local",
                body: "",
                dateStart: Date(timeIntervalSince1970: 100),
                calendarSyncEnabled: true,
                updatedAt: Date(timeIntervalSince1970: 150),
            ),
        )
        let noteOnlyChanged = try await store.upsertNote(
            Note(
                stableID: "note-conflict-note-only",
                title: "Note changed local",
                body: "",
                dateStart: Date(timeIntervalSince1970: 100),
                calendarSyncEnabled: true,
                updatedAt: Date(timeIntervalSince1970: 250),
            ),
        )
        let eventOnlyChanged = try await store.upsertNote(
            Note(
                stableID: "note-conflict-event-only",
                title: "Event changed local",
                body: "",
                dateStart: Date(timeIntervalSince1970: 100),
                calendarSyncEnabled: true,
                updatedAt: Date(timeIntervalSince1970: 150),
            ),
        )

        let unchangedLastSynced = unchanged.updatedAt.addingTimeInterval(10)
        let noteOnlyLastSynced = noteOnlyChanged.updatedAt.addingTimeInterval(-10)
        let eventOnlyLastSynced = eventOnlyChanged.updatedAt.addingTimeInterval(10)

        try await store.upsertBinding(
            CalendarBinding(
                entityType: .note,
                entityID: unchanged.id,
                calendarID: "cal",
                eventIdentifier: "event-note-unchanged",
                externalIdentifier: "ext-note-unchanged",
                lastEntityVersion: unchanged.version,
                lastEventUpdatedAt: unchangedLastSynced.addingTimeInterval(-20),
                lastSyncedAt: unchangedLastSynced,
            ),
        )
        try await store.upsertBinding(
            CalendarBinding(
                entityType: .note,
                entityID: noteOnlyChanged.id,
                calendarID: "cal",
                eventIdentifier: "event-note-note-only",
                externalIdentifier: "ext-note-note-only",
                lastEntityVersion: noteOnlyChanged.version,
                lastEventUpdatedAt: noteOnlyLastSynced.addingTimeInterval(-20),
                lastSyncedAt: noteOnlyLastSynced,
            ),
        )
        try await store.upsertBinding(
            CalendarBinding(
                entityType: .note,
                entityID: eventOnlyChanged.id,
                calendarID: "cal",
                eventIdentifier: "event-note-event-only",
                externalIdentifier: "ext-note-event-only",
                lastEntityVersion: eventOnlyChanged.version,
                lastEventUpdatedAt: eventOnlyLastSynced.addingTimeInterval(-20),
                lastSyncedAt: eventOnlyLastSynced,
            ),
        )

        let maxVersion = max(unchanged.version, max(noteOnlyChanged.version, eventOnlyChanged.version))
        try await store.saveCheckpoint(
            SyncCheckpoint(
                id: "default",
                taskVersionCursor: 0,
                noteVersionCursor: maxVersion,
                calendarToken: "t1",
                updatedAt: Date(timeIntervalSince1970: 201),
            ),
        )

        let unchangedEvent = try CalendarEvent(
            eventIdentifier: "event-note-unchanged",
            externalIdentifier: "ext-note-unchanged",
            calendarID: "cal",
            title: "Unchanged calendar title",
            updatedAt: unchangedLastSynced.addingTimeInterval(-5),
            sourceEntityType: .note,
        )
        let noteOnlyEvent = try CalendarEvent(
            eventIdentifier: "event-note-note-only",
            externalIdentifier: "ext-note-note-only",
            calendarID: "cal",
            title: "Note-only calendar title",
            updatedAt: noteOnlyLastSynced.addingTimeInterval(-5),
            sourceEntityType: .note,
        )
        let eventOnlyEvent = try CalendarEvent(
            eventIdentifier: "event-note-event-only",
            externalIdentifier: "ext-note-event-only",
            calendarID: "cal",
            title: "Event-only calendar title",
            updatedAt: eventOnlyLastSynced.addingTimeInterval(5),
            sourceEntityType: .note,
        )
        await provider.queueFetchBatch(
            CalendarChangeBatch(changes: [.upsert(unchangedEvent), .upsert(noteOnlyEvent), .upsert(eventOnlyEvent)], nextToken: "t2"),
        )

        let engine = makeEngine(store: store, provider: provider, includeNoteStore: true)
        let report = try await engine.runOnce(
            configuration: SyncEngineConfiguration(
                checkpointID: "default",
                calendarID: "cal",
                policy: .lastWriteWins,
            ),
        )

        XCTAssertEqual(report.tasksUpdatedFromCalendar, 1)
        let upserts = await provider.upsertedEvents
        XCTAssertEqual(upserts.count, 2)

        let updated = try await store.fetchNote(id: eventOnlyChanged.id)
        XCTAssertEqual(updated?.title, "Event-only calendar title")
    }

    func testNoteConflictTaskPriorityRepushes() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        var note = try await store.upsertNote(
            Note(
                stableID: "note-conflict-task-priority",
                title: "Local wins",
                body: "",
                dateStart: Date(timeIntervalSince1970: 100),
                calendarSyncEnabled: true,
                updatedAt: Date(timeIntervalSince1970: 250),
            ),
        )
        try await store.upsertBinding(
            CalendarBinding(
                entityType: .note,
                entityID: note.id,
                calendarID: "cal",
                eventIdentifier: "event-note-task-priority",
                externalIdentifier: "ext-note-task-priority",
                lastEntityVersion: note.version,
                lastEventUpdatedAt: Date(timeIntervalSince1970: 190),
                lastSyncedAt: Date(timeIntervalSince1970: 200),
            ),
        )
        try await store.saveCheckpoint(
            SyncCheckpoint(
                id: "default",
                taskVersionCursor: 0,
                noteVersionCursor: note.version,
                calendarToken: "t1",
                updatedAt: Date(timeIntervalSince1970: 201),
            ),
        )

        let incoming = try CalendarEvent(
            eventIdentifier: "event-note-task-priority",
            externalIdentifier: "ext-note-task-priority",
            calendarID: "cal",
            title: "Calendar edit",
            updatedAt: Date(timeIntervalSince1970: 260),
            sourceEntityType: .note,
        )
        await provider.queueFetchBatch(CalendarChangeBatch(changes: [.upsert(incoming)], nextToken: "t2"))

        let engine = makeEngine(store: store, provider: provider, includeNoteStore: true)
        let report = try await engine.runOnce(
            configuration: SyncEngineConfiguration(
                checkpointID: "default",
                calendarID: "cal",
                policy: .taskPriority,
            ),
        )

        XCTAssertEqual(report.tasksUpdatedFromCalendar, 0)
        let upserts = await provider.upsertedEvents
        XCTAssertEqual(upserts.count, 1)
        let fetchedNote = try await store.fetchNote(id: note.id)
        note = try XCTUnwrap(fetchedNote)
        XCTAssertEqual(note.title, "Local wins")
    }

    func testNoteConflictCalendarPriorityAppliesCalendarEdit() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        var note = try await store.upsertNote(
            Note(
                stableID: "note-conflict-calendar-priority",
                title: "Local loses",
                body: "",
                dateStart: Date(timeIntervalSince1970: 100),
                calendarSyncEnabled: true,
                updatedAt: Date(timeIntervalSince1970: 250),
            ),
        )
        try await store.upsertBinding(
            CalendarBinding(
                entityType: .note,
                entityID: note.id,
                calendarID: "cal",
                eventIdentifier: "event-note-calendar-priority",
                externalIdentifier: "ext-note-calendar-priority",
                lastEntityVersion: note.version,
                lastEventUpdatedAt: Date(timeIntervalSince1970: 190),
                lastSyncedAt: Date(timeIntervalSince1970: 200),
            ),
        )
        try await store.saveCheckpoint(
            SyncCheckpoint(
                id: "default",
                taskVersionCursor: 0,
                noteVersionCursor: note.version,
                calendarToken: "t1",
                updatedAt: Date(timeIntervalSince1970: 201),
            ),
        )

        let incoming = try CalendarEvent(
            eventIdentifier: "event-note-calendar-priority",
            externalIdentifier: "ext-note-calendar-priority",
            calendarID: "cal",
            title: "Calendar wins",
            updatedAt: Date(timeIntervalSince1970: 260),
            sourceEntityType: .note,
        )
        await provider.queueFetchBatch(CalendarChangeBatch(changes: [.upsert(incoming)], nextToken: "t2"))

        let engine = makeEngine(store: store, provider: provider, includeNoteStore: true)
        let report = try await engine.runOnce(
            configuration: SyncEngineConfiguration(
                checkpointID: "default",
                calendarID: "cal",
                policy: .calendarPriority,
            ),
        )

        XCTAssertEqual(report.tasksUpdatedFromCalendar, 1)
        let upserts = await provider.upsertedEvents
        XCTAssertTrue(upserts.isEmpty)
        let fetchedNote = try await store.fetchNote(id: note.id)
        note = try XCTUnwrap(fetchedNote)
        XCTAssertEqual(note.title, "Calendar wins")
    }

    func testNoteConflictLastWriteWinsCoversNewerAndTieWithTaskTieBreaker() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        let noteNewer = try await store.upsertNote(
            Note(
                stableID: "note-lww-note-newer",
                title: "Local newer",
                body: "",
                dateStart: Date(timeIntervalSince1970: 100),
                calendarSyncEnabled: true,
                updatedAt: Date(timeIntervalSince1970: 260.9),
            ),
        )
        let eventNewer = try await store.upsertNote(
            Note(
                stableID: "note-lww-event-newer",
                title: "Local older",
                body: "",
                dateStart: Date(timeIntervalSince1970: 100),
                calendarSyncEnabled: true,
                updatedAt: Date(timeIntervalSince1970: 250.1),
            ),
        )
        let tied = try await store.upsertNote(
            Note(
                stableID: "note-lww-tie-task",
                title: "Local tie",
                body: "",
                dateStart: Date(timeIntervalSince1970: 100),
                calendarSyncEnabled: true,
                updatedAt: Date(timeIntervalSince1970: 250.9),
            ),
        )

        try await store.upsertBinding(
            CalendarBinding(
                entityType: .note,
                entityID: noteNewer.id,
                calendarID: "cal",
                eventIdentifier: "event-note-lww-note-newer",
                externalIdentifier: "ext-note-lww-note-newer",
                lastEntityVersion: noteNewer.version,
                lastEventUpdatedAt: noteNewer.updatedAt.addingTimeInterval(-20),
                lastSyncedAt: noteNewer.updatedAt.addingTimeInterval(-10),
            ),
        )
        try await store.upsertBinding(
            CalendarBinding(
                entityType: .note,
                entityID: eventNewer.id,
                calendarID: "cal",
                eventIdentifier: "event-note-lww-event-newer",
                externalIdentifier: "ext-note-lww-event-newer",
                lastEntityVersion: eventNewer.version,
                lastEventUpdatedAt: eventNewer.updatedAt.addingTimeInterval(-20),
                lastSyncedAt: eventNewer.updatedAt.addingTimeInterval(-10),
            ),
        )
        try await store.upsertBinding(
            CalendarBinding(
                entityType: .note,
                entityID: tied.id,
                calendarID: "cal",
                eventIdentifier: "event-note-lww-tie-task",
                externalIdentifier: "ext-note-lww-tie-task",
                lastEntityVersion: tied.version,
                lastEventUpdatedAt: tied.updatedAt.addingTimeInterval(-20),
                lastSyncedAt: tied.updatedAt.addingTimeInterval(-10),
            ),
        )

        let maxVersion = max(noteNewer.version, max(eventNewer.version, tied.version))
        try await store.saveCheckpoint(
            SyncCheckpoint(
                id: "default",
                taskVersionCursor: 0,
                noteVersionCursor: maxVersion,
                calendarToken: "t1",
                updatedAt: Date(timeIntervalSince1970: 201),
            ),
        )

        let incomingNoteNewer = try CalendarEvent(
            eventIdentifier: "event-note-lww-note-newer",
            externalIdentifier: "ext-note-lww-note-newer",
            calendarID: "cal",
            title: "Calendar older",
            updatedAt: noteNewer.updatedAt.addingTimeInterval(-2),
            sourceEntityType: .note,
        )
        let incomingEventNewer = try CalendarEvent(
            eventIdentifier: "event-note-lww-event-newer",
            externalIdentifier: "ext-note-lww-event-newer",
            calendarID: "cal",
            title: "Calendar newer",
            updatedAt: eventNewer.updatedAt.addingTimeInterval(2),
            sourceEntityType: .note,
        )
        let incomingTie = try CalendarEvent(
            eventIdentifier: "event-note-lww-tie-task",
            externalIdentifier: "ext-note-lww-tie-task",
            calendarID: "cal",
            title: "Calendar tie",
            updatedAt: tied.updatedAt,
            sourceEntityType: .note,
        )
        await provider.queueFetchBatch(
            CalendarChangeBatch(changes: [.upsert(incomingNoteNewer), .upsert(incomingEventNewer), .upsert(incomingTie)], nextToken: "t2"),
        )

        let engine = makeEngine(store: store, provider: provider, includeNoteStore: true)
        let report = try await engine.runOnce(
            configuration: SyncEngineConfiguration(
                checkpointID: "default",
                calendarID: "cal",
                policy: .lastWriteWins,
                timestampNormalizationSeconds: 1,
                lastWriteWinsTieBreaker: .task,
            ),
        )

        XCTAssertEqual(report.tasksUpdatedFromCalendar, 1)
        let upserts = await provider.upsertedEvents
        XCTAssertEqual(upserts.count, 2)
        let updatedEventNewer = try await store.fetchNote(id: eventNewer.id)
        XCTAssertEqual(updatedEventNewer?.title, "Calendar newer")
    }

    func testNoteConflictLastWriteWinsTieCalendarTieBreakerAppliesEvent() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        var note = try await store.upsertNote(
            Note(
                stableID: "note-lww-tie-calendar",
                title: "Local tie calendar",
                body: "",
                dateStart: Date(timeIntervalSince1970: 100),
                calendarSyncEnabled: true,
                updatedAt: Date(timeIntervalSince1970: 250.9),
            ),
        )
        try await store.upsertBinding(
            CalendarBinding(
                entityType: .note,
                entityID: note.id,
                calendarID: "cal",
                eventIdentifier: "event-note-lww-tie-calendar",
                externalIdentifier: "ext-note-lww-tie-calendar",
                lastEntityVersion: note.version,
                lastEventUpdatedAt: note.updatedAt.addingTimeInterval(-20),
                lastSyncedAt: note.updatedAt.addingTimeInterval(-10),
            ),
        )
        try await store.saveCheckpoint(
            SyncCheckpoint(
                id: "default",
                taskVersionCursor: 0,
                noteVersionCursor: note.version,
                calendarToken: "t1",
                updatedAt: Date(timeIntervalSince1970: 201),
            ),
        )

        let incoming = try CalendarEvent(
            eventIdentifier: "event-note-lww-tie-calendar",
            externalIdentifier: "ext-note-lww-tie-calendar",
            calendarID: "cal",
            title: "Calendar tie calendar breaker",
            updatedAt: note.updatedAt,
            sourceEntityType: .note,
        )
        await provider.queueFetchBatch(CalendarChangeBatch(changes: [.upsert(incoming)], nextToken: "t2"))

        let engine = makeEngine(store: store, provider: provider, includeNoteStore: true)
        let report = try await engine.runOnce(
            configuration: SyncEngineConfiguration(
                checkpointID: "default",
                calendarID: "cal",
                policy: .lastWriteWins,
                timestampNormalizationSeconds: 1,
                lastWriteWinsTieBreaker: .calendar,
            ),
        )

        XCTAssertEqual(report.tasksUpdatedFromCalendar, 1)
        let upserts = await provider.upsertedEvents
        XCTAssertTrue(upserts.isEmpty)
        let fetchedNote = try await store.fetchNote(id: note.id)
        note = try XCTUnwrap(fetchedNote)
        XCTAssertEqual(note.title, "Calendar tie calendar breaker")
    }

    func testCalendarDeletionForNoteBindingWithoutNoteStoreIsSkipped() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        let noteID = UUID()
        try await store.upsertBinding(
            CalendarBinding(
                entityType: .note,
                entityID: noteID,
                calendarID: "cal",
                eventIdentifier: "event-note-delete-no-store",
                externalIdentifier: "ext-note-delete-no-store",
            ),
        )

        let deletion = CalendarDeletion(
            eventIdentifier: "event-note-delete-no-store",
            externalIdentifier: "ext-note-delete-no-store",
            calendarID: "cal",
            deletedAt: Date(timeIntervalSince1970: 200),
        )
        await provider.queueFetchBatch(CalendarChangeBatch(changes: [.delete(deletion)], nextToken: "next"))

        let engine = makeEngine(store: store, provider: provider)
        let report = try await engine.runOnce(configuration: SyncEngineConfiguration(checkpointID: "default", calendarID: "cal"))

        XCTAssertEqual(report.tasksDeletedFromCalendar, 0)
        XCTAssertTrue(
            report.diagnostics.contains {
                $0.operation == .pullEventDelete
                    && $0.entityType == .note
                    && $0.message.contains("note store is unavailable")
            },
        )
    }

    func testCalendarDeletionForNoteBindingTombstonesNoteAndBinding() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        var note = try await store.upsertNote(
            Note(
                stableID: "note-delete-calendar",
                title: "Delete from calendar",
                body: "",
                updatedAt: Date(timeIntervalSince1970: 100),
            ),
        )
        try await store.upsertBinding(
            CalendarBinding(
                entityType: .note,
                entityID: note.id,
                calendarID: "cal",
                eventIdentifier: "event-note-delete-calendar",
                externalIdentifier: "ext-note-delete-calendar",
            ),
        )

        let deletion = CalendarDeletion(
            eventIdentifier: "event-note-delete-calendar",
            externalIdentifier: "ext-note-delete-calendar",
            calendarID: "cal",
            deletedAt: Date(timeIntervalSince1970: 200),
        )
        await provider.queueFetchBatch(CalendarChangeBatch(changes: [.delete(deletion)], nextToken: "next"))

        let engine = makeEngine(store: store, provider: provider, includeNoteStore: true)
        let report = try await engine.runOnce(configuration: SyncEngineConfiguration(checkpointID: "default", calendarID: "cal"))

        XCTAssertEqual(report.tasksDeletedFromCalendar, 1)
        let fetchedNote = try await store.fetchNote(id: note.id)
        note = try XCTUnwrap(fetchedNote)
        XCTAssertNotNil(note.deletedAt)

        let binding = try await store.fetchBinding(entityType: .note, entityID: note.id, calendarID: "cal")
        XCTAssertNotNil(binding?.deletedAt)
    }

    func testRunOnceUnknownErrorDoesNotRetryProviderOperations() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        let task = try Task(stableID: "task-unknown-error", title: "Unknown error path", updatedAt: Date(timeIntervalSince1970: 100))
        _ = try await store.upsertTask(task)
        await provider.queueUpsertResponse(.failure(NSError(domain: "CustomProviderDomain", code: 42)))

        let engine = makeEngine(store: store, provider: provider)
        await XCTAssertThrowsErrorAsync(
            try await engine.runOnce(
                configuration: SyncEngineConfiguration(
                    checkpointID: "default",
                    calendarID: "cal",
                    providerMaxRetryAttempts: 3,
                    providerRetryBaseDelayMilliseconds: 0,
                ),
            ),
        )

        let upserts = await provider.upsertedEvents
        XCTAssertEqual(upserts.count, 1)
    }

    func testNoCheckpointCreatesAndPersistsDefaultCursor() async throws {
        let store = try makeStore()
        let provider = StubCalendarProvider()

        await provider.queueFetchBatch(CalendarChangeBatch(changes: [], nextToken: "abc"))

        let engine = makeEngine(store: store, provider: provider)
        let report = try await engine.runOnce(configuration: SyncEngineConfiguration(checkpointID: "default", calendarID: "cal"))

        XCTAssertEqual(report.finalTaskVersionCursor, 0)
        XCTAssertEqual(report.finalCalendarToken, "abc")

        let checkpoint = try await store.fetchCheckpoint(id: "default")
        XCTAssertEqual(checkpoint?.calendarToken, "abc")
        XCTAssertEqual(checkpoint?.noteVersionCursor, 0)
    }

    private func makeStore() throws -> SQLiteStore {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-engine-sync-edge-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try SQLiteStore(databaseURL: folder.appendingPathComponent("notes.sqlite"))
    }

    private func makeEngine(
        store: SQLiteStore,
        provider: StubCalendarProvider,
        includeNoteStore: Bool = false,
    ) -> TwoWaySyncEngine {
        TwoWaySyncEngine(
            taskStore: store,
            noteStore: includeNoteStore ? store : nil,
            bindingStore: store,
            checkpointStore: store,
            calendarProvider: provider,
            clock: FixedClock(current: Date(timeIntervalSince1970: 500)),
        )
    }
}

private actor StubCalendarProvider: CalendarProvider {
    private var upsertQueue: [Result<CalendarEvent, Error>] = []
    private var fetchQueue: [Result<CalendarChangeBatch, Error>] = []

    private(set) var upsertedEvents: [CalendarEvent] = []
    private(set) var deletedEventIdentifiers: [String] = []
    private(set) var fetchChangesCallCount: Int = 0

    func queueUpsertResponse(_ response: Result<CalendarEvent, Error>) {
        upsertQueue.append(response)
    }

    func queueFetchBatch(_ batch: CalendarChangeBatch) {
        fetchQueue.append(.success(batch))
    }

    func queueFetchResult(_ result: Result<CalendarChangeBatch, Error>) {
        fetchQueue.append(result)
    }

    func upsertEvent(_ event: CalendarEvent) async throws -> CalendarEvent {
        upsertedEvents.append(event)

        if !upsertQueue.isEmpty {
            let next = upsertQueue.removeFirst()
            switch next {
            case let .success(success):
                return success
            case let .failure(error):
                throw error
            }
        }

        var e = event
        if e.eventIdentifier == nil {
            e.eventIdentifier = UUID().uuidString.lowercased()
        }
        if e.externalIdentifier == nil {
            e.externalIdentifier = e.eventIdentifier
        }
        return e
    }

    func deleteEvent(eventIdentifier: String, calendarID _: String) async throws {
        deletedEventIdentifiers.append(eventIdentifier)
    }

    func fetchChanges(since token: String?, calendarID _: String) async throws -> CalendarChangeBatch {
        fetchChangesCallCount += 1
        if !fetchQueue.isEmpty {
            let result = fetchQueue.removeFirst()
            switch result {
            case let .success(batch):
                return batch
            case let .failure(error):
                throw error
            }
        }
        return CalendarChangeBatch(changes: [], nextToken: token)
    }
}

private struct FixedClock: Clock {
    let current: Date

    func now() -> Date {
        current
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> some Any,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in },
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown. \(message())", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}

private struct CustomURLDomainError: Error, CustomNSError {
    let code: Int

    static var errorDomain: String {
        NSURLErrorDomain
    }

    var errorCode: Int {
        code
    }
}
