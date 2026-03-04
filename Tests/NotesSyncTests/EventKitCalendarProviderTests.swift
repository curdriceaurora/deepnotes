#if canImport(EventKit)
import XCTest
import Foundation
@testable import NotesDomain
@testable import NotesSync

final class EventKitCalendarProviderTests: XCTestCase {
    func testUpsertThrowsWhenAccessDenied() async throws {
        let client = FakeEventStoreClient()
        await client.setAuthorization(.other)
        await client.setAccessResult(.success(false))
        await client.addCalendar(id: "cal-1")

        let provider = EventKitCalendarProvider(
            client: client,
            nowProvider: { Date(timeIntervalSince1970: 1000) }
        )

        let event = try CalendarEvent(calendarID: "cal-1", title: "Task", updatedAt: Date(timeIntervalSince1970: 1000))

        await XCTAssertThrowsErrorAsync(try await provider.upsertEvent(event)) { error in
            guard case .unsupportedCalendarChange(let reason) = error as? SyncError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(reason, "Calendar access denied by user")
        }
    }

    func testUpsertThrowsWhenCalendarMissing() async throws {
        let client = FakeEventStoreClient()
        await client.setAuthorization(.fullAccess)

        let provider = EventKitCalendarProvider(client: client, nowProvider: { Date() })
        let event = try CalendarEvent(calendarID: "missing", title: "Task", updatedAt: Date(timeIntervalSince1970: 1000))

        await XCTAssertThrowsErrorAsync(try await provider.upsertEvent(event)) { error in
            guard case .unsupportedCalendarChange(let reason) = error as? SyncError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(reason.contains("Calendar not found"))
        }
    }

    func testUpsertExistingEventAddsRecurrenceMarkerAndPersists() async throws {
        let client = FakeEventStoreClient()
        await client.setAuthorization(.fullAccess)
        await client.addCalendar(id: "cal-1")

        let existing = EventStoreEvent(
            eventIdentifier: "event-1",
            externalIdentifier: "ext-1",
            calendarID: "cal-1",
            title: "Old",
            notes: "already there",
            startDate: nil,
            endDate: nil,
            isAllDay: false,
            lastModifiedDate: Date(timeIntervalSince1970: 1200)
        )
        await client.putEvent(existing)

        let provider = EventKitCalendarProvider(client: client, nowProvider: { Date(timeIntervalSince1970: 1300) })

        let input = try CalendarEvent(
            eventIdentifier: "event-1",
            externalIdentifier: "ext-1",
            calendarID: "cal-1",
            title: "Updated",
            notes: "already there",
            startDate: Date(timeIntervalSince1970: 1300),
            endDate: Date(timeIntervalSince1970: 1600),
            recurrenceRule: "FREQ=WEEKLY",
            isCompleted: false,
            updatedAt: Date(timeIntervalSince1970: 1300)
        )

        let result = try await provider.upsertEvent(input)
        XCTAssertEqual(result.eventIdentifier, "event-1")

        let saved = await client.lastSavedEvent
        XCTAssertEqual(saved?.title, "Updated")
        XCTAssertTrue(saved?.notes?.contains("event-rrule:FREQ=WEEKLY") == true)
    }

    func testUpsertWithoutStartDateCreatesAllDayWindow() async throws {
        let client = FakeEventStoreClient()
        await client.setAuthorization(.fullAccess)
        await client.addCalendar(id: "cal-1")

        let provider = EventKitCalendarProvider(client: client, nowProvider: { Date(timeIntervalSince1970: 1_700_000_000) })

        let input = try CalendarEvent(
            calendarID: "cal-1",
            title: "No Start",
            notes: nil,
            startDate: nil,
            endDate: nil,
            recurrenceRule: nil,
            isCompleted: false,
            updatedAt: Date()
        )

        _ = try await provider.upsertEvent(input)
        guard let saved = await client.lastSavedEvent else {
            return XCTFail("Expected save")
        }

        XCTAssertTrue(saved.isAllDay)
        let interval = (saved.endDate ?? .distantPast).timeIntervalSince(saved.startDate ?? .distantPast)
        XCTAssertEqual(interval, 86400, accuracy: 1)
    }

    func testDeleteNoopWhenEventMissing() async throws {
        let client = FakeEventStoreClient()
        await client.setAuthorization(.fullAccess)
        await client.addCalendar(id: "cal-1")

        let provider = EventKitCalendarProvider(client: client, nowProvider: { Date() })
        try await provider.deleteEvent(eventIdentifier: "missing", calendarID: "cal-1")

        let removeCalls = await client.removeCallCount
        XCTAssertEqual(removeCalls, 1)
    }

    func testDeleteNoopWhenCalendarMismatch() async throws {
        let client = FakeEventStoreClient()
        await client.setAuthorization(.fullAccess)
        await client.addCalendar(id: "cal-1")

        let event = EventStoreEvent(
            eventIdentifier: "event-1",
            externalIdentifier: "ext-1",
            calendarID: "cal-1",
            title: "Task",
            notes: nil,
            startDate: nil,
            endDate: nil,
            isAllDay: false,
            lastModifiedDate: Date()
        )
        await client.putEvent(event)

        let provider = EventKitCalendarProvider(client: client, nowProvider: { Date() })
        try await provider.deleteEvent(eventIdentifier: "event-1", calendarID: "cal-x")

        let removed = await client.removedIdentifiers
        XCTAssertEqual(removed, [])
    }

    func testFetchChangesDetectsUpsertsAndDeletions() async throws {
        let client = FakeEventStoreClient()
        await client.setAuthorization(.fullAccess)
        await client.addCalendar(id: "cal-1")

        let first = EventStoreEvent(
            eventIdentifier: "event-1",
            externalIdentifier: "ext-1",
            calendarID: "cal-1",
            title: "Task",
            notes: "task-stable-id:stable-1\nevent-rrule:FREQ=DAILY",
            startDate: Date(timeIntervalSince1970: 2100),
            endDate: Date(timeIntervalSince1970: 2400),
            isAllDay: false,
            lastModifiedDate: Date(timeIntervalSince1970: 2200)
        )
        await client.setListedEvents([first])

        let provider = EventKitCalendarProvider(client: client, nowProvider: { Date(timeIntervalSince1970: 3000) })

        let firstBatch = try await provider.fetchChanges(since: nil, calendarID: "cal-1")
        XCTAssertEqual(firstBatch.changes.count, 1)

        if case .upsert(let upserted) = firstBatch.changes[0] {
            XCTAssertEqual(upserted.eventIdentifier, "event-1")
            XCTAssertEqual(upserted.recurrenceRule, "FREQ=DAILY")
            XCTAssertEqual(upserted.sourceStableID, "stable-1")
        } else {
            XCTFail("Expected upsert")
        }

        await client.setListedEvents([])
        let secondBatch = try await provider.fetchChanges(since: firstBatch.nextToken, calendarID: "cal-1")

        XCTAssertEqual(secondBatch.changes.count, 1)
        if case .delete(let deletion) = secondBatch.changes[0] {
            XCTAssertEqual(deletion.eventIdentifier, "event-1")
            XCTAssertEqual(deletion.externalIdentifier, "ext-1")
        } else {
            XCTFail("Expected deletion")
        }
    }

    func testFetchChangesReturnsEmptyWhenCalendarMissing() async throws {
        let client = FakeEventStoreClient()
        await client.setAuthorization(.fullAccess)

        let provider = EventKitCalendarProvider(client: client, nowProvider: { Date() })
        let batch = try await provider.fetchChanges(since: "token", calendarID: "missing")

        XCTAssertTrue(batch.changes.isEmpty)
        XCTAssertEqual(batch.nextToken, "token")
    }

    func testFetchChangesDetachedRecurrenceExceptionDoesNotEmitDeletion() async throws {
        let client = FakeEventStoreClient()
        await client.setAuthorization(.fullAccess)
        await client.addCalendar(id: "cal-1")

        let exceptionDate = Date(timeIntervalSince1970: 4100)
        let detached = EventStoreEvent(
            eventIdentifier: "exception-1",
            externalIdentifier: "ext-series-1",
            calendarID: "cal-1",
            title: "Series Exception",
            notes: "task-stable-id:series-1",
            startDate: Date(timeIntervalSince1970: 4200),
            endDate: Date(timeIntervalSince1970: 4500),
            isAllDay: false,
            lastModifiedDate: Date(timeIntervalSince1970: 4300),
            recurrenceExceptionDate: exceptionDate
        )
        await client.setListedEvents([detached])

        let provider = EventKitCalendarProvider(client: client, nowProvider: { Date(timeIntervalSince1970: 5000) })

        let first = try await provider.fetchChanges(since: nil, calendarID: "cal-1")
        XCTAssertEqual(first.changes.count, 1)
        if case .upsert(let upserted) = first.changes[0] {
            XCTAssertEqual(upserted.recurrenceExceptionDate, exceptionDate)
        } else {
            XCTFail("Expected upsert change")
        }

        await client.setListedEvents([])
        let second = try await provider.fetchChanges(since: first.nextToken, calendarID: "cal-1")
        XCTAssertTrue(second.changes.isEmpty)
    }

    func testFetchChangesExtractsRecurrenceExceptionDateFromNotesMarker() async throws {
        let client = FakeEventStoreClient()
        await client.setAuthorization(.fullAccess)
        await client.addCalendar(id: "cal-1")

        let markerDate = Date(timeIntervalSince1970: 6100)
        let event = EventStoreEvent(
            eventIdentifier: "event-marker",
            externalIdentifier: "ext-marker",
            calendarID: "cal-1",
            title: "Marker Event",
            notes: "event-recurrence-exception:\(Int(markerDate.timeIntervalSince1970))",
            startDate: Date(timeIntervalSince1970: 6200),
            endDate: Date(timeIntervalSince1970: 6500),
            isAllDay: false,
            lastModifiedDate: Date(timeIntervalSince1970: 6300)
        )
        await client.setListedEvents([event])

        let provider = EventKitCalendarProvider(client: client, nowProvider: { Date(timeIntervalSince1970: 7000) })
        let batch = try await provider.fetchChanges(since: nil, calendarID: "cal-1")

        XCTAssertEqual(batch.changes.count, 1)
        if case .upsert(let upserted) = batch.changes[0] {
            XCTAssertEqual(upserted.recurrenceExceptionDate, markerDate)
        } else {
            XCTFail("Expected upsert change")
        }
    }
}

private actor FakeEventStoreClient: EventStoreClient {
    private var auth: EventStoreAuthorizationStatus = .other
    private var accessResult: Result<Bool, Error> = .success(true)
    private var calendars: Set<String> = []
    private var events: [String: EventStoreEvent] = [:]
    private var listedEvents: [EventStoreEvent] = []

    private(set) var lastSavedEvent: EventStoreEvent?
    private(set) var removeCallCount: Int = 0
    private(set) var removedIdentifiers: [String] = []

    func setAuthorization(_ status: EventStoreAuthorizationStatus) {
        auth = status
    }

    func setAccessResult(_ result: Result<Bool, Error>) {
        accessResult = result
    }

    func addCalendar(id: String) {
        calendars.insert(id)
    }

    func putEvent(_ event: EventStoreEvent) {
        if let id = event.eventIdentifier {
            events[id] = event
        }
    }

    func setListedEvents(_ events: [EventStoreEvent]) {
        listedEvents = events
    }

    func authorizationStatus() async -> EventStoreAuthorizationStatus {
        auth
    }

    func requestAccess() async throws -> Bool {
        switch accessResult {
        case .success(let granted):
            return granted
        case .failure(let error):
            throw error
        }
    }

    func calendarExists(identifier: String) async -> Bool {
        calendars.contains(identifier)
    }

    func fetchEvent(identifier: String) async -> EventStoreEvent? {
        events[identifier]
    }

    func saveEvent(_ event: EventStoreEvent) async throws -> EventStoreEvent {
        var mutable = event
        if mutable.eventIdentifier == nil {
            mutable.eventIdentifier = UUID().uuidString.lowercased()
        }
        if mutable.externalIdentifier == nil {
            mutable.externalIdentifier = "ext-\(mutable.eventIdentifier!)"
        }
        mutable.lastModifiedDate = mutable.lastModifiedDate ?? Date(timeIntervalSince1970: 9999)
        lastSavedEvent = mutable
        if let id = mutable.eventIdentifier {
            events[id] = mutable
        }
        return mutable
    }

    func removeEvent(identifier: String, calendarID: String) async throws {
        removeCallCount += 1
        guard let existing = events[identifier], existing.calendarID == calendarID else {
            return
        }
        removedIdentifiers.append(identifier)
        events.removeValue(forKey: identifier)
    }

    func fetchEvents(calendarID: String, windowStart: Date, windowEnd: Date) async -> [EventStoreEvent] {
        listedEvents.filter { $0.calendarID == calendarID }
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown. \(message())", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
#endif
