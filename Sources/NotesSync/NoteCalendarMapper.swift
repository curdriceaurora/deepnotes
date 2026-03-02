import Foundation
import NotesDomain

public struct NoteCalendarMapper: Sendable {
    public init() {}

    public func event(from note: Note, calendarID: String, existing: CalendarBinding?) throws -> CalendarEvent {
        var details = note.body
        let markers = [
            "entity-type:note",
            "note-stable-id:\(note.stableID)"
        ]
        for marker in markers where !details.contains(marker) {
            details += details.isEmpty ? marker : "\n\n\(marker)"
        }

        return try CalendarEvent(
            eventIdentifier: existing?.eventIdentifier,
            externalIdentifier: existing?.externalIdentifier,
            calendarID: calendarID,
            title: note.title,
            notes: details,
            startDate: note.dateStart,
            endDate: note.dateEnd,
            isAllDay: note.isAllDay,
            recurrenceRule: note.recurrenceRule,
            recurrenceExceptionDate: nil,
            isCompleted: false,
            updatedAt: note.updatedAt,
            sourceEntityType: .note,
            sourceStableID: note.stableID
        )
    }

    public func note(from event: CalendarEvent, existing: Note?) -> Note {
        let stableID = event.sourceStableID
            ?? extractStableID(from: event.notes)
            ?? existing?.stableID
            ?? UUID().uuidString.lowercased()

        let recurrenceRule: String? = {
            if event.recurrenceExceptionDate != nil {
                return existing?.recurrenceRule ?? event.recurrenceRule
            }
            return event.recurrenceRule
        }()

        return Note(
            id: existing?.id ?? UUID(),
            stableID: stableID,
            title: event.title,
            body: stripMarkers(from: event.notes ?? ""),
            dateStart: event.startDate,
            dateEnd: event.endDate,
            isAllDay: event.isAllDay,
            recurrenceRule: recurrenceRule,
            calendarSyncEnabled: true,
            updatedAt: event.updatedAt,
            version: existing?.version ?? 0,
            deletedAt: nil
        )
    }

    public func isNoteEvent(_ event: CalendarEvent) -> Bool {
        if event.sourceEntityType == .note {
            return true
        }
        guard let notes = event.notes else {
            return false
        }
        return notes.contains("entity-type:note") || notes.contains("note-stable-id:")
    }

    private func extractStableID(from notes: String?) -> String? {
        guard let notes else {
            return nil
        }
        return notes
            .split(separator: "\n")
            .compactMap { line -> String? in
                let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                guard parts[0].trimmingCharacters(in: .whitespaces) == "note-stable-id" else { return nil }
                return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .first
    }

    private func stripMarkers(from notes: String) -> String {
        notes
            .split(separator: "\n")
            .filter {
                let line = $0.trimmingCharacters(in: .whitespaces)
                return !line.hasPrefix("note-stable-id:") && line != "entity-type:note"
            }
            .map(String.init)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
