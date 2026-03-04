import Foundation
import XCTest
@testable import NotesDomain
@testable import NotesSync

final class TaskCalendarMapperTests: XCTestCase {
    private let mapper = TaskCalendarMapper()

    func testEventFromTaskAddsStableIDMarkerWhenDetailsEmpty() throws {
        let task = try Task(stableID: "stable-1", title: "Task", details: "", updatedAt: Date())
        let event = try mapper.event(from: task, calendarID: "cal", existing: nil)

        XCTAssertEqual(event.notes, "entity-type:task\ntask-stable-id:stable-1")
    }

    func testEventFromTaskAppendsStableIDMarkerWhenMissing() throws {
        let task = try Task(stableID: "stable-2", title: "Task", details: "line1", updatedAt: Date())
        let event = try mapper.event(from: task, calendarID: "cal", existing: nil)

        XCTAssertTrue(event.notes?.contains("line1") == true)
        XCTAssertTrue(event.notes?.contains("task-stable-id:stable-2") == true)
    }

    func testEventFromTaskDoesNotDuplicateStableIDMarker() throws {
        let task = try Task(
            stableID: "stable-3",
            title: "Task",
            details: "note\ntask-stable-id:stable-3",
            updatedAt: Date(),
        )
        let event = try mapper.event(from: task, calendarID: "cal", existing: nil)

        let markerCount = event.notes?.components(separatedBy: "task-stable-id:stable-3").count ?? 0
        XCTAssertEqual(markerCount, 2)
    }

    func testTaskFromEventUsesSourceStableIDFirst() throws {
        let event = try CalendarEvent(
            calendarID: "cal",
            title: "E",
            notes: "task-stable-id:other",
            updatedAt: Date(),
            sourceStableID: "preferred",
        )
        let task = try mapper.task(from: event, existingTask: nil)

        XCTAssertEqual(task.stableID, "preferred")
    }

    func testTaskFromEventUsesMarkerIfSourceMissing() throws {
        let event = try CalendarEvent(
            calendarID: "cal",
            title: "E",
            notes: "hello\ntask-stable-id:from-marker",
            updatedAt: Date(),
            sourceStableID: nil,
        )
        let task = try mapper.task(from: event, existingTask: nil)

        XCTAssertEqual(task.stableID, "from-marker")
        XCTAssertEqual(task.details, "hello")
    }

    func testTaskFromEventIgnoresNonStableIDMarkerPrefix() throws {
        let event = try CalendarEvent(
            calendarID: "cal",
            title: "E",
            notes: "not-a-stable-id:wrong\ntask-stable-id:from-marker",
            updatedAt: Date(),
            sourceStableID: nil,
        )
        let task = try mapper.task(from: event, existingTask: nil)

        XCTAssertEqual(task.stableID, "from-marker")
    }

    func testTaskFromEventFallsBackToExistingTaskStableID() throws {
        let existing = try Task(stableID: "existing", title: "Old", updatedAt: Date())
        let event = try CalendarEvent(calendarID: "cal", title: "E", notes: nil, updatedAt: Date())
        let task = try mapper.task(from: event, existingTask: existing)

        XCTAssertEqual(task.stableID, "existing")
    }

    func testTaskFromEventCreatesGeneratedStableID() throws {
        let event = try CalendarEvent(calendarID: "cal", title: "E", notes: nil, updatedAt: Date())
        let task = try mapper.task(from: event, existingTask: nil)

        XCTAssertFalse(task.stableID.isEmpty)
    }

    func testTaskFromEventMarksCompletedState() throws {
        let event = try CalendarEvent(
            calendarID: "cal",
            title: "E",
            notes: nil,
            isCompleted: true,
            updatedAt: Date(timeIntervalSince1970: 100),
        )

        let task = try mapper.task(from: event, existingTask: nil)

        XCTAssertEqual(task.status, .done)
        XCTAssertEqual(task.completedAt, Date(timeIntervalSince1970: 100))
    }

    func testTaskFromRecurrenceExceptionPreservesExistingRecurrenceRule() throws {
        let existing = try Task(
            stableID: "recurring-1",
            title: "Series",
            recurrenceRule: "FREQ=WEEKLY",
            updatedAt: Date(timeIntervalSince1970: 100),
        )

        let event = try CalendarEvent(
            calendarID: "cal",
            title: "Series exception",
            recurrenceRule: nil,
            recurrenceExceptionDate: Date(timeIntervalSince1970: 120),
            updatedAt: Date(timeIntervalSince1970: 120),
            sourceStableID: "recurring-1",
        )

        let task = try mapper.task(from: event, existingTask: existing)
        XCTAssertEqual(task.recurrenceRule, "FREQ=WEEKLY")
    }

    func testEventFromTaskPropagatesRecurrenceExceptionDateMarker() throws {
        let exceptionTimestamp = 1_700_000_123
        let task = try Task(
            stableID: "recurring-2",
            title: "Detached occurrence",
            details: "event-recurrence-exception:\(exceptionTimestamp)",
            recurrenceRule: "FREQ=DAILY",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )

        let event = try mapper.event(from: task, calendarID: "cal", existing: nil)

        XCTAssertEqual(event.recurrenceExceptionDate, Date(timeIntervalSince1970: TimeInterval(exceptionTimestamp)))
    }

    func testRemovingRecurrenceExceptionMarkerStripsOnlyExceptionLine() {
        let details = """
        Prepare launch update
        event-recurrence-exception:1700000123
        Keep this line
        """

        let stripped = TaskCalendarMapper.removingRecurrenceExceptionMarker(from: details)

        XCTAssertEqual(stripped, "Prepare launch update\nKeep this line")
        XCTAssertNil(TaskCalendarMapper.recurrenceExceptionDate(in: stripped))
    }

    func testResolveWithoutBindingReturnsEventWins() throws {
        let task = try makeTask(updatedAt: 100, stableID: "s", title: "task")
        let event = try makeEvent(updatedAt: 100, sourceStableID: "s", title: "event")

        let result = try mapper.resolve(task: task, event: event, binding: nil, policy: .lastWriteWins)

        guard case let .eventWins(merged) = result else {
            return XCTFail("Expected eventWins")
        }
        XCTAssertEqual(merged.title, "event")
    }

    func testResolveSkipsWhenEventAlreadySeen() throws {
        let task = try makeTask(updatedAt: 100, stableID: "s", title: "task")
        let event = try makeEvent(updatedAt: 100, sourceStableID: "s", title: "event")
        let binding = CalendarBinding(
            taskID: task.id,
            calendarID: "cal",
            lastTaskVersion: task.version,
            lastEventUpdatedAt: Date(timeIntervalSince1970: 150),
            lastSyncedAt: Date(timeIntervalSince1970: 90),
        )

        let result = try mapper.resolve(task: task, event: event, binding: binding, policy: .lastWriteWins)

        guard case .keepTask = result else {
            return XCTFail("Expected keepTask")
        }
    }

    func testResolveReturnsKeepTaskWhenNeitherChanged() throws {
        let task = try makeTask(updatedAt: 100, stableID: "s", title: "task")
        let event = try makeEvent(updatedAt: 100, sourceStableID: "s", title: "event")
        let binding = CalendarBinding(
            taskID: task.id,
            calendarID: "cal",
            lastTaskVersion: task.version,
            lastEventUpdatedAt: Date(timeIntervalSince1970: 50),
            lastSyncedAt: Date(timeIntervalSince1970: 200),
        )

        let result = try mapper.resolve(task: task, event: event, binding: binding, policy: .lastWriteWins)

        guard case .keepTask = result else {
            return XCTFail("Expected keepTask")
        }
    }

    func testResolveReturnsTaskWinsWhenOnlyTaskChanged() throws {
        let task = try makeTask(updatedAt: 300, stableID: "s", title: "task")
        let event = try makeEvent(updatedAt: 100, sourceStableID: "s", title: "event")
        let binding = CalendarBinding(
            taskID: task.id,
            calendarID: "cal",
            lastTaskVersion: task.version,
            lastEventUpdatedAt: Date(timeIntervalSince1970: 50),
            lastSyncedAt: Date(timeIntervalSince1970: 200),
        )

        let result = try mapper.resolve(task: task, event: event, binding: binding, policy: .lastWriteWins)

        guard case let .taskWins(returnedTask) = result else {
            return XCTFail("Expected taskWins")
        }
        XCTAssertEqual(returnedTask.id, task.id)
    }

    func testResolveReturnsEventWinsWhenOnlyEventChanged() throws {
        let task = try makeTask(updatedAt: 100, stableID: "s", title: "task")
        let event = try makeEvent(updatedAt: 300, sourceStableID: "s", title: "event")
        let binding = CalendarBinding(
            taskID: task.id,
            calendarID: "cal",
            lastTaskVersion: task.version,
            lastEventUpdatedAt: Date(timeIntervalSince1970: 50),
            lastSyncedAt: Date(timeIntervalSince1970: 200),
        )

        let result = try mapper.resolve(task: task, event: event, binding: binding, policy: .lastWriteWins)

        guard case let .eventWins(merged) = result else {
            return XCTFail("Expected eventWins")
        }
        XCTAssertEqual(merged.title, "event")
    }

    func testResolvePolicyTaskPriority() throws {
        let task = try makeTask(updatedAt: 250, stableID: "s", title: "task")
        let event = try makeEvent(updatedAt: 260, sourceStableID: "s", title: "event")
        let binding = CalendarBinding(
            taskID: task.id,
            calendarID: "cal",
            lastTaskVersion: task.version,
            lastEventUpdatedAt: Date(timeIntervalSince1970: 50),
            lastSyncedAt: Date(timeIntervalSince1970: 200),
        )

        let result = try mapper.resolve(task: task, event: event, binding: binding, policy: .taskPriority)

        guard case .taskWins = result else {
            return XCTFail("Expected taskWins")
        }
    }

    func testResolvePolicyCalendarPriority() throws {
        let task = try makeTask(updatedAt: 260, stableID: "s", title: "task")
        let event = try makeEvent(updatedAt: 250, sourceStableID: "s", title: "event")
        let binding = CalendarBinding(
            taskID: task.id,
            calendarID: "cal",
            lastTaskVersion: task.version,
            lastEventUpdatedAt: Date(timeIntervalSince1970: 50),
            lastSyncedAt: Date(timeIntervalSince1970: 200),
        )

        let result = try mapper.resolve(task: task, event: event, binding: binding, policy: .calendarPriority)

        guard case .eventWins = result else {
            return XCTFail("Expected eventWins")
        }
    }

    func testResolvePolicyLastWriteWinsWhenEventNewer() throws {
        let task = try makeTask(updatedAt: 250, stableID: "s", title: "task")
        let event = try makeEvent(updatedAt: 260, sourceStableID: "s", title: "event")
        let binding = CalendarBinding(
            taskID: task.id,
            calendarID: "cal",
            lastTaskVersion: task.version,
            lastEventUpdatedAt: Date(timeIntervalSince1970: 50),
            lastSyncedAt: Date(timeIntervalSince1970: 200),
        )

        let result = try mapper.resolve(task: task, event: event, binding: binding, policy: .lastWriteWins)

        guard case .eventWins = result else {
            return XCTFail("Expected eventWins")
        }
    }

    func testResolvePolicyLastWriteWinsWhenTaskNewer() throws {
        let task = try makeTask(updatedAt: 260, stableID: "s", title: "task")
        let event = try makeEvent(updatedAt: 250, sourceStableID: "s", title: "event")
        let binding = CalendarBinding(
            taskID: task.id,
            calendarID: "cal",
            lastTaskVersion: task.version,
            lastEventUpdatedAt: Date(timeIntervalSince1970: 50),
            lastSyncedAt: Date(timeIntervalSince1970: 200),
        )

        let result = try mapper.resolve(task: task, event: event, binding: binding, policy: .lastWriteWins)

        guard case .taskWins = result else {
            return XCTFail("Expected taskWins")
        }
    }

    func testResolvePolicyLastWriteWinsUsesTaskTieBreakerAfterNormalization() throws {
        let task = try makeTask(updatedAt: 260.8, stableID: "s", title: "task")
        let event = try makeEvent(updatedAt: 260.2, sourceStableID: "s", title: "event")
        let binding = CalendarBinding(
            taskID: task.id,
            calendarID: "cal",
            lastTaskVersion: task.version,
            lastEventUpdatedAt: Date(timeIntervalSince1970: 200),
            lastSyncedAt: Date(timeIntervalSince1970: 250),
        )

        let result = try mapper.resolve(
            task: task,
            event: event,
            binding: binding,
            policy: .lastWriteWins,
            timestampNormalizationSeconds: 1,
            lastWriteWinsTieBreaker: .task,
        )

        guard case .taskWins = result else {
            return XCTFail("Expected taskWins from tie-breaker")
        }
    }

    func testResolvePolicyLastWriteWinsUsesCalendarTieBreakerAfterNormalization() throws {
        let task = try makeTask(updatedAt: 360.8, stableID: "s", title: "task")
        let event = try makeEvent(updatedAt: 360.2, sourceStableID: "s", title: "event")
        let binding = CalendarBinding(
            taskID: task.id,
            calendarID: "cal",
            lastTaskVersion: task.version,
            lastEventUpdatedAt: Date(timeIntervalSince1970: 300),
            lastSyncedAt: Date(timeIntervalSince1970: 350),
        )

        let result = try mapper.resolve(
            task: task,
            event: event,
            binding: binding,
            policy: .lastWriteWins,
            timestampNormalizationSeconds: 1,
            lastWriteWinsTieBreaker: .calendar,
        )

        guard case .eventWins = result else {
            return XCTFail("Expected eventWins from tie-breaker")
        }
    }

    func testResolveUsesDistantPastWhenLastSyncedMissing() throws {
        let task = try makeTask(updatedAt: 10, stableID: "s", title: "task")
        let event = try makeEvent(updatedAt: 11, sourceStableID: "s", title: "event")
        let binding = CalendarBinding(
            taskID: task.id,
            calendarID: "cal",
            eventIdentifier: "e",
            externalIdentifier: "x",
            lastTaskVersion: task.version,
            lastEventUpdatedAt: nil,
            lastSyncedAt: nil,
        )

        let result = try mapper.resolve(task: task, event: event, binding: binding, policy: .lastWriteWins)
        guard case .eventWins = result else {
            return XCTFail("Expected eventWins when both changes are after distantPast")
        }
    }

    private func makeTask(updatedAt: TimeInterval, stableID: String, title: String) throws -> Task {
        try Task(
            stableID: stableID,
            title: title,
            updatedAt: Date(timeIntervalSince1970: updatedAt),
        )
    }

    private func makeEvent(updatedAt: TimeInterval, sourceStableID: String?, title: String) throws -> CalendarEvent {
        try CalendarEvent(
            calendarID: "cal",
            title: title,
            notes: nil,
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            sourceStableID: sourceStableID,
        )
    }
}
