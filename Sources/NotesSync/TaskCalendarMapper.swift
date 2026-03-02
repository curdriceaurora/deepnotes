import Foundation
import NotesDomain

public struct TaskCalendarMapper: Sendable {
    public init() {}

    public func event(from task: Task, calendarID: String, existing: CalendarBinding?) throws -> CalendarEvent {
        var notes = task.details
        let entityMarker = "entity-type:task"
        let marker = "task-stable-id:\(task.stableID)"
        if notes.isEmpty {
            notes = entityMarker + "\n" + marker
        } else {
            if !notes.contains(entityMarker) {
                notes += "\n\n\(entityMarker)"
            }
            if !notes.contains(marker) {
                notes += "\n\(marker)"
            }
        }

        return try CalendarEvent(
            eventIdentifier: existing?.eventIdentifier,
            externalIdentifier: existing?.externalIdentifier,
            calendarID: calendarID,
            title: task.title,
            notes: notes,
            startDate: task.dueStart,
            endDate: task.dueEnd,
            isAllDay: false,
            recurrenceRule: task.recurrenceRule,
            recurrenceExceptionDate: nil,
            isCompleted: task.completedAt != nil || task.status == .done,
            updatedAt: task.updatedAt,
            sourceEntityType: .task,
            sourceStableID: task.stableID
        )
    }

    public func task(from event: CalendarEvent, existingTask: Task?) throws -> Task {
        let stableID = event.sourceStableID ?? extractStableID(from: event.notes) ?? existingTask?.stableID ?? UUID().uuidString.lowercased()

        let completedAt = event.isCompleted ? event.updatedAt : nil
        let status: TaskStatus = event.isCompleted ? .done : (existingTask?.status ?? .next)
        let resolvedRecurrenceRule: String? = {
            if event.recurrenceExceptionDate != nil {
                return existingTask?.recurrenceRule ?? event.recurrenceRule
            }
            return event.recurrenceRule
        }()

        return try Task(
            id: existingTask?.id ?? UUID(),
            noteID: existingTask?.noteID,
            stableID: stableID,
            title: event.title,
            details: stripStableIDMarker(from: event.notes ?? ""),
            dueStart: event.startDate,
            dueEnd: event.endDate,
            status: status,
            priority: existingTask?.priority ?? 3,
            recurrenceRule: resolvedRecurrenceRule,
            completedAt: completedAt,
            updatedAt: event.updatedAt,
            version: existingTask?.version ?? 0,
            deletedAt: nil
        )
    }

    public func resolve(
        task: Task,
        event: CalendarEvent,
        binding: CalendarBinding?,
        policy: ConflictResolutionPolicy,
        timestampNormalizationSeconds: TimeInterval = 1,
        lastWriteWinsTieBreaker: ConflictSource = .calendar
    ) throws -> ResolvedPair {
        guard let binding else {
            return .eventWins(try self.task(from: event, existingTask: task))
        }

        if let lastEventUpdatedAt = binding.lastEventUpdatedAt,
           event.updatedAt <= lastEventUpdatedAt {
            return .keepTask
        }

        let lastSynced = binding.lastSyncedAt ?? .distantPast
        let taskChanged = task.updatedAt > lastSynced
        let eventChanged = event.updatedAt > lastSynced

        switch (taskChanged, eventChanged) {
        case (false, false):
            return .keepTask
        case (true, false):
            return .taskWins(task)
        case (false, true):
            return .eventWins(try self.task(from: event, existingTask: task))
        case (true, true):
            switch policy {
            case .taskPriority:
                return .taskWins(task)
            case .calendarPriority:
                return .eventWins(try self.task(from: event, existingTask: task))
            case .lastWriteWins:
                let normalizedTaskTime = normalizedTimestamp(task.updatedAt, granularitySeconds: timestampNormalizationSeconds)
                let normalizedEventTime = normalizedTimestamp(event.updatedAt, granularitySeconds: timestampNormalizationSeconds)

                if normalizedEventTime > normalizedTaskTime {
                    return .eventWins(try self.task(from: event, existingTask: task))
                }
                if normalizedTaskTime > normalizedEventTime {
                    return .taskWins(task)
                }

                switch lastWriteWinsTieBreaker {
                case .calendar:
                    return .eventWins(try self.task(from: event, existingTask: task))
                case .task:
                    return .taskWins(task)
                }
            }
        }
    }

    private func normalizedTimestamp(_ date: Date, granularitySeconds: TimeInterval) -> Date {
        let safeGranularity = max(0.001, granularitySeconds)
        let interval = date.timeIntervalSince1970
        let normalizedInterval = floor(interval / safeGranularity) * safeGranularity
        return Date(timeIntervalSince1970: normalizedInterval)
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
                guard parts[0].trimmingCharacters(in: .whitespaces) == "task-stable-id" else { return nil }
                return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .first
    }

    private func stripStableIDMarker(from notes: String) -> String {
        notes
            .split(separator: "\n")
            .filter {
                let line = $0.trimmingCharacters(in: .whitespaces)
                return !line.hasPrefix("task-stable-id:") && line != "entity-type:task"
            }
            .map(String.init)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum ResolvedPair: Sendable {
    case keepTask
    case taskWins(Task)
    case eventWins(Task)
}
