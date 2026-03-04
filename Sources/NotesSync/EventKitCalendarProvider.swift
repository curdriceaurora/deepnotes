#if canImport(EventKit)
    import EventKit
    import Foundation
    import NotesDomain

    enum EventStoreAuthorizationStatus {
        case fullAccess
        case writeOnly
        case other
    }

    struct EventStoreEvent: Equatable {
        var eventIdentifier: String?
        var externalIdentifier: String?
        var calendarID: String
        var title: String
        var notes: String?
        var startDate: Date?
        var endDate: Date?
        var isAllDay: Bool
        var lastModifiedDate: Date?
        var recurrenceExceptionDate: Date?
    }

    protocol EventStoreClient: Sendable {
        func authorizationStatus() async -> EventStoreAuthorizationStatus
        func requestAccess() async throws -> Bool
        func calendarExists(identifier: String) async -> Bool
        func fetchEvent(identifier: String) async -> EventStoreEvent?
        func saveEvent(_ event: EventStoreEvent) async throws -> EventStoreEvent
        func removeEvent(identifier: String, calendarID: String) async throws
        func fetchEvents(calendarID: String, windowStart: Date, windowEnd: Date) async -> [EventStoreEvent]
    }

    public actor EventKitCalendarProvider: CalendarProvider {
        private struct EventFingerprint: Equatable {
            var title: String
            var startDate: Date?
            var endDate: Date?
            var notes: String?
            var isCompleted: Bool
            var updatedAt: Date
            var externalIdentifier: String?
            var recurrenceExceptionDate: Date?
        }

        private let client: any EventStoreClient
        private let nowProvider: @Sendable () -> Date
        private var snapshotByCalendar: [String: [String: EventFingerprint]]

        public init(
            eventStore: EKEventStore = EKEventStore(),
            authorizationStatusProvider: @escaping @Sendable () -> EKAuthorizationStatus
                = { EKEventStore.authorizationStatus(for: .event) },
            nowProvider: @escaping @Sendable () -> Date = { Date() },
        ) {
            self.client = EventKitStoreClient(
                eventStore: eventStore,
                authorizationStatusProvider: authorizationStatusProvider,
            )
            self.nowProvider = nowProvider
            self.snapshotByCalendar = [:]
        }

        init(client: any EventStoreClient, nowProvider: @escaping @Sendable () -> Date = { Date() }) {
            self.client = client
            self.nowProvider = nowProvider
            self.snapshotByCalendar = [:]
        }

        public func upsertEvent(_ event: CalendarEvent) async throws -> CalendarEvent {
            try await requestAccessIfNeeded()

            guard await client.calendarExists(identifier: event.calendarID) else {
                throw SyncError.unsupportedCalendarChange(reason: "Calendar not found: \(event.calendarID)")
            }

            var resolved = if let identifier = event.eventIdentifier,
                              let existing = await client.fetchEvent(identifier: identifier)
            {
                existing
            } else {
                EventStoreEvent(
                    eventIdentifier: event.eventIdentifier,
                    externalIdentifier: event.externalIdentifier,
                    calendarID: event.calendarID,
                    title: event.title,
                    notes: event.notes,
                    startDate: event.startDate,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay,
                    lastModifiedDate: nil,
                    recurrenceExceptionDate: event.recurrenceExceptionDate,
                )
            }

            resolved.calendarID = event.calendarID
            resolved.title = event.title
            resolved.notes = event.notes

            if let startDate = event.startDate {
                resolved.startDate = startDate
                if event.isAllDay {
                    let dayStart = Calendar.current.startOfDay(for: startDate)
                    resolved.startDate = dayStart
                    resolved.endDate = event.endDate ?? dayStart.addingTimeInterval(86400)
                    resolved.isAllDay = true
                } else {
                    resolved.endDate = event.endDate ?? startDate.addingTimeInterval(3600)
                    resolved.isAllDay = false
                }
            } else {
                let dayStart = Calendar.current.startOfDay(for: nowProvider())
                resolved.startDate = dayStart
                resolved.endDate = dayStart.addingTimeInterval(86400)
                resolved.isAllDay = true
            }

            if let recurrence = event.recurrenceRule {
                let marker = "event-rrule:\(recurrence)"
                if resolved.notes?.contains(marker) == false {
                    let notes = resolved.notes ?? ""
                    resolved.notes = notes.isEmpty ? marker : notes + "\n\n" + marker
                }
            }

            if let recurrenceExceptionDate = event.recurrenceExceptionDate {
                let marker = recurrenceExceptionMarker(for: recurrenceExceptionDate)
                if resolved.notes?.contains(marker) == false {
                    let notes = resolved.notes ?? ""
                    resolved.notes = notes.isEmpty ? marker : notes + "\n\n" + marker
                }
            }

            let saved = try await client.saveEvent(resolved)

            return try CalendarEvent(
                eventIdentifier: saved.eventIdentifier,
                externalIdentifier: saved.externalIdentifier,
                calendarID: saved.calendarID,
                title: saved.title,
                notes: saved.notes,
                startDate: saved.startDate,
                endDate: saved.endDate,
                isAllDay: saved.isAllDay,
                recurrenceRule: event.recurrenceRule,
                recurrenceExceptionDate: event.recurrenceExceptionDate,
                isCompleted: event.isCompleted,
                updatedAt: saved.lastModifiedDate ?? nowProvider(),
                sourceEntityType: event.sourceEntityType,
                sourceStableID: event.sourceStableID,
            )
        }

        public func deleteEvent(eventIdentifier: String, calendarID: String) async throws {
            try await requestAccessIfNeeded()
            try await client.removeEvent(identifier: eventIdentifier, calendarID: calendarID)
        }

        public func fetchChanges(since token: String?, calendarID: String) async throws -> CalendarChangeBatch {
            try await requestAccessIfNeeded()

            guard await client.calendarExists(identifier: calendarID) else {
                return CalendarChangeBatch(changes: [], nextToken: token)
            }

            let windowStart = Calendar.current.date(byAdding: .year, value: -1, to: nowProvider()) ?? Date.distantPast
            let windowEnd = Calendar.current.date(byAdding: .year, value: 2, to: nowProvider()) ?? Date.distantFuture

            let events = await client.fetchEvents(calendarID: calendarID, windowStart: windowStart, windowEnd: windowEnd)
            var currentSnapshot: [String: EventFingerprint] = [:]
            var changes: [CalendarChange] = []

            let previousSnapshot = snapshotByCalendar[calendarID, default: [:]]

            for event in events {
                guard let identifier = event.eventIdentifier else {
                    continue
                }

                let fingerprint = EventFingerprint(
                    title: event.title,
                    startDate: event.startDate,
                    endDate: event.endDate,
                    notes: event.notes,
                    isCompleted: false,
                    updatedAt: event.lastModifiedDate ?? nowProvider(),
                    externalIdentifier: event.externalIdentifier,
                    recurrenceExceptionDate: event.recurrenceExceptionDate,
                )
                currentSnapshot[identifier] = fingerprint

                if previousSnapshot[identifier] != fingerprint || token == nil {
                    let mapped = try CalendarEvent(
                        eventIdentifier: identifier,
                        externalIdentifier: event.externalIdentifier,
                        calendarID: calendarID,
                        title: event.title,
                        notes: event.notes,
                        startDate: event.startDate,
                        endDate: event.endDate,
                        isAllDay: event.isAllDay,
                        recurrenceRule: extractRecurrenceRule(from: event.notes),
                        recurrenceExceptionDate: event.recurrenceExceptionDate ?? extractRecurrenceExceptionDate(from: event.notes),
                        isCompleted: false,
                        updatedAt: event.lastModifiedDate ?? nowProvider(),
                        sourceEntityType: extractEntityType(from: event.notes),
                        sourceStableID: extractStableID(from: event.notes),
                    )
                    changes.append(.upsert(mapped))
                }
            }

            for (identifier, previous) in previousSnapshot where currentSnapshot[identifier] == nil {
                if previous.recurrenceExceptionDate != nil {
                    continue
                }
                let deletion = CalendarDeletion(
                    eventIdentifier: identifier,
                    externalIdentifier: previous.externalIdentifier,
                    calendarID: calendarID,
                    deletedAt: nowProvider(),
                )
                changes.append(.delete(deletion))
            }

            snapshotByCalendar[calendarID] = currentSnapshot
            let nextToken = String(Int(nowProvider().timeIntervalSince1970))
            return CalendarChangeBatch(changes: changes, nextToken: nextToken)
        }

        private func requestAccessIfNeeded() async throws {
            let currentStatus = await client.authorizationStatus()
            if currentStatus == .fullAccess || currentStatus == .writeOnly {
                return
            }

            let granted = try await client.requestAccess()
            guard granted else {
                throw SyncError.unsupportedCalendarChange(reason: "Calendar access denied by user")
            }
        }

        private func extractRecurrenceRule(from notes: String?) -> String? {
            guard let notes else {
                return nil
            }

            return notes
                .split(separator: "\n")
                .compactMap { line -> String? in
                    let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                    guard parts.count == 2 else {
                        return nil
                    }
                    guard parts[0].trimmingCharacters(in: .whitespaces) == "event-rrule" else {
                        return nil
                    }
                    return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .first
        }

        private func recurrenceExceptionMarker(for date: Date) -> String {
            "event-recurrence-exception:\(Int(date.timeIntervalSince1970))"
        }

        private func extractRecurrenceExceptionDate(from notes: String?) -> Date? {
            guard let notes else {
                return nil
            }

            return notes
                .split(separator: "\n")
                .compactMap { line -> Date? in
                    let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                    guard parts.count == 2 else {
                        return nil
                    }
                    guard parts[0].trimmingCharacters(in: .whitespaces) == "event-recurrence-exception" else {
                        return nil
                    }
                    guard let timestamp = TimeInterval(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) else {
                        return nil
                    }
                    return Date(timeIntervalSince1970: timestamp)
                }
                .first
        }

        private func extractStableID(from notes: String?) -> String? {
            guard let notes else {
                return nil
            }

            return notes
                .split(separator: "\n")
                .compactMap { line -> String? in
                    let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                    guard parts.count == 2 else {
                        return nil
                    }
                    let key = parts[0].trimmingCharacters(in: .whitespaces)
                    guard key == "task-stable-id" || key == "note-stable-id" else {
                        return nil
                    }
                    return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .first
        }

        private func extractEntityType(from notes: String?) -> CalendarBindingEntityType? {
            guard let notes else {
                return nil
            }

            return notes
                .split(separator: "\n")
                .compactMap { line -> CalendarBindingEntityType? in
                    let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                    guard parts.count == 2 else {
                        return nil
                    }
                    guard parts[0].trimmingCharacters(in: .whitespaces) == "entity-type" else {
                        return nil
                    }
                    return CalendarBindingEntityType(rawValue: parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .first
        }
    }

    private final class EventKitStoreClient: @unchecked Sendable, EventStoreClient {
        private let eventStore: EKEventStore
        private let authorizationStatusProvider: @Sendable () -> EKAuthorizationStatus

        init(eventStore: EKEventStore, authorizationStatusProvider: @escaping @Sendable () -> EKAuthorizationStatus) {
            self.eventStore = eventStore
            self.authorizationStatusProvider = authorizationStatusProvider
        }

        func authorizationStatus() async -> EventStoreAuthorizationStatus {
            switch authorizationStatusProvider() {
            case .fullAccess:
                .fullAccess
            case .writeOnly:
                .writeOnly
            default:
                .other
            }
        }

        func requestAccess() async throws -> Bool {
            try await eventStore.requestFullAccessToEvents()
        }

        func calendarExists(identifier: String) async -> Bool {
            eventStore.calendar(withIdentifier: identifier) != nil
        }

        func fetchEvent(identifier: String) async -> EventStoreEvent? {
            guard let event = eventStore.event(withIdentifier: identifier) else {
                return nil
            }
            return map(event)
        }

        func saveEvent(_ event: EventStoreEvent) async throws -> EventStoreEvent {
            guard let calendar = eventStore.calendar(withIdentifier: event.calendarID) else {
                throw SyncError.unsupportedCalendarChange(reason: "Calendar not found: \(event.calendarID)")
            }

            let ekEvent: EKEvent
            if let identifier = event.eventIdentifier,
               let existing = eventStore.event(withIdentifier: identifier)
            {
                ekEvent = existing
            } else {
                ekEvent = EKEvent(eventStore: eventStore)
                ekEvent.calendar = calendar
            }

            ekEvent.calendar = calendar
            ekEvent.title = event.title
            ekEvent.notes = event.notes
            ekEvent.startDate = event.startDate
            ekEvent.endDate = event.endDate
            ekEvent.isAllDay = event.isAllDay

            try eventStore.save(ekEvent, span: .thisEvent, commit: true)
            return map(ekEvent)
        }

        func removeEvent(identifier: String, calendarID: String) async throws {
            guard let event = eventStore.event(withIdentifier: identifier),
                  event.calendar.calendarIdentifier == calendarID
            else {
                return
            }

            try eventStore.remove(event, span: .thisEvent, commit: true)
        }

        func fetchEvents(calendarID: String, windowStart: Date, windowEnd: Date) async -> [EventStoreEvent] {
            guard let calendar = eventStore.calendar(withIdentifier: calendarID) else {
                return []
            }

            let predicate = eventStore.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: [calendar])
            return eventStore.events(matching: predicate).map(map)
        }

        private func map(_ event: EKEvent) -> EventStoreEvent {
            EventStoreEvent(
                eventIdentifier: event.eventIdentifier,
                externalIdentifier: event.calendarItemExternalIdentifier,
                calendarID: event.calendar.calendarIdentifier,
                title: event.title,
                notes: event.notes,
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                lastModifiedDate: event.lastModifiedDate,
                recurrenceExceptionDate: event.isDetached ? event.occurrenceDate : nil,
            )
        }
    }
#endif
