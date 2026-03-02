import Foundation
import NotesDomain

public actor InMemoryCalendarProvider: CalendarProvider {
    private var eventsByCalendar: [String: [String: CalendarEvent]] = [:]
    private var changeLogByCalendar: [String: [CalendarChange]] = [:]

    public init() {}

    public func upsertEvent(_ event: CalendarEvent) async throws -> CalendarEvent {
        var mutable = event

        let eventID = mutable.eventIdentifier ?? UUID().uuidString.lowercased()
        let externalID = mutable.externalIdentifier ?? eventID
        mutable.eventIdentifier = eventID
        mutable.externalIdentifier = externalID
        mutable.updatedAt = max(event.updatedAt, Date())

        var events = eventsByCalendar[mutable.calendarID, default: [:]]
        events[eventID] = mutable
        eventsByCalendar[mutable.calendarID] = events

        changeLogByCalendar[mutable.calendarID, default: []].append(.upsert(mutable))
        return mutable
    }

    public func deleteEvent(eventIdentifier: String, calendarID: String) async throws {
        var events = eventsByCalendar[calendarID, default: [:]]
        guard let existing = events.removeValue(forKey: eventIdentifier) else {
            return
        }

        eventsByCalendar[calendarID] = events

        let deletion = CalendarDeletion(
            eventIdentifier: eventIdentifier,
            externalIdentifier: existing.externalIdentifier,
            calendarID: calendarID,
            deletedAt: Date()
        )

        changeLogByCalendar[calendarID, default: []].append(.delete(deletion))
    }

    public func fetchChanges(since token: String?, calendarID: String) async throws -> CalendarChangeBatch {
        let allChanges = changeLogByCalendar[calendarID, default: []]
        let startIndex: Int

        if let token, let parsed = Int(token) {
            startIndex = max(0, min(parsed, allChanges.count))
        } else {
            startIndex = 0
        }

        let delta = Array(allChanges[startIndex...])
        return CalendarChangeBatch(changes: delta, nextToken: String(allChanges.count))
    }

    public func seed(event: CalendarEvent) async {
        var events = eventsByCalendar[event.calendarID, default: [:]]
        let eventID = event.eventIdentifier ?? UUID().uuidString.lowercased()
        var persisted = event
        persisted.eventIdentifier = eventID
        persisted.externalIdentifier = event.externalIdentifier ?? eventID
        events[eventID] = persisted
        eventsByCalendar[event.calendarID] = events
        changeLogByCalendar[event.calendarID, default: []].append(.upsert(persisted))
    }

    public func allEvents(calendarID: String) async -> [CalendarEvent] {
        Array(eventsByCalendar[calendarID, default: [:]].values)
    }

    public func eventCount(calendarID: String) async -> Int {
        eventsByCalendar[calendarID, default: [:]].count
    }
}
