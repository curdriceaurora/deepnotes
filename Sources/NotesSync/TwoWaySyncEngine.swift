import Foundation
import NotesDomain

public struct SyncEngineConfiguration: Sendable {
    public var checkpointID: String
    public var calendarID: String
    public var taskBatchSize: Int
    public var policy: ConflictResolutionPolicy
    public var timestampNormalizationSeconds: TimeInterval
    public var lastWriteWinsTieBreaker: ConflictSource
    public var providerMaxRetryAttempts: Int
    public var providerRetryBaseDelayMilliseconds: UInt64
    public var providerRetryMaxDelayMilliseconds: UInt64

    public init(
        checkpointID: String,
        calendarID: String,
        taskBatchSize: Int = 500,
        policy: ConflictResolutionPolicy = .lastWriteWins,
        timestampNormalizationSeconds: TimeInterval = 1,
        lastWriteWinsTieBreaker: ConflictSource = .calendar,
        providerMaxRetryAttempts: Int = 3,
        providerRetryBaseDelayMilliseconds: UInt64 = 150,
        providerRetryMaxDelayMilliseconds: UInt64 = 2000,
    ) {
        self.checkpointID = checkpointID
        self.calendarID = calendarID
        self.taskBatchSize = max(1, taskBatchSize)
        self.policy = policy
        self.timestampNormalizationSeconds = max(0.001, timestampNormalizationSeconds)
        self.lastWriteWinsTieBreaker = lastWriteWinsTieBreaker
        self.providerMaxRetryAttempts = max(1, providerMaxRetryAttempts)
        self.providerRetryBaseDelayMilliseconds = providerRetryBaseDelayMilliseconds
        self.providerRetryMaxDelayMilliseconds = max(providerRetryBaseDelayMilliseconds, providerRetryMaxDelayMilliseconds)
    }
}

public enum SyncDiagnosticSeverity: String, Sendable {
    case info
    case warning
    case error
}

public enum SyncDiagnosticOperation: String, Sendable {
    case pullCalendarChanges
    case pullEventUpsert
    case pullEventDelete
    case pushTaskUpsert
    case pushTaskDelete
    case pushNoteUpsert
    case pushNoteDelete
}

public struct SyncDiagnosticEntry: Sendable {
    public var operation: SyncDiagnosticOperation
    public var severity: SyncDiagnosticSeverity
    public var message: String
    public var entityType: CalendarBindingEntityType?
    public var entityID: UUID?
    public var taskID: UUID?
    public var eventIdentifier: String?
    public var externalIdentifier: String?
    public var calendarID: String
    public var providerError: String?
    public var timestamp: Date
    public var attempt: Int?

    public init(
        operation: SyncDiagnosticOperation,
        severity: SyncDiagnosticSeverity,
        message: String,
        entityType: CalendarBindingEntityType? = nil,
        entityID: UUID? = nil,
        taskID: UUID? = nil,
        eventIdentifier: String? = nil,
        externalIdentifier: String? = nil,
        calendarID: String,
        providerError: String? = nil,
        timestamp: Date,
        attempt: Int? = nil,
    ) {
        self.operation = operation
        self.severity = severity
        self.message = message
        self.entityType = entityType
        self.entityID = entityID
        self.taskID = taskID
        self.eventIdentifier = eventIdentifier
        self.externalIdentifier = externalIdentifier
        self.calendarID = calendarID
        self.providerError = providerError
        self.timestamp = timestamp
        self.attempt = attempt
    }
}

public struct SyncRunReport: Sendable {
    public var tasksPushed: Int = 0
    public var eventsPulled: Int = 0
    public var tasksImported: Int = 0
    public var tasksUpdatedFromCalendar: Int = 0
    public var tasksDeletedFromCalendar: Int = 0
    public var eventsDeletedFromTasks: Int = 0
    public var finalTaskVersionCursor: Int64 = 0
    public var finalCalendarToken: String?
    public var diagnostics: [SyncDiagnosticEntry] = []

    public init() {}
}

public final class TwoWaySyncEngine: Sendable {
    private let taskStore: TaskStore
    private let noteStore: NoteStore?
    private let bindingStore: CalendarBindingStore
    private let checkpointStore: SyncCheckpointStore
    private let calendarProvider: CalendarProvider
    private let taskMapper: TaskCalendarMapper
    private let noteMapper: NoteCalendarMapper
    private let clock: Clock

    public init(
        taskStore: TaskStore,
        noteStore: NoteStore? = nil,
        bindingStore: CalendarBindingStore,
        checkpointStore: SyncCheckpointStore,
        calendarProvider: CalendarProvider,
        mapper: TaskCalendarMapper = TaskCalendarMapper(),
        noteMapper: NoteCalendarMapper = NoteCalendarMapper(),
        clock: Clock = SystemClock(),
    ) {
        self.taskStore = taskStore
        self.noteStore = noteStore
        self.bindingStore = bindingStore
        self.checkpointStore = checkpointStore
        self.calendarProvider = calendarProvider
        self.taskMapper = mapper
        self.noteMapper = noteMapper
        self.clock = clock
    }

    public func runOnce(configuration: SyncEngineConfiguration) async throws -> SyncRunReport {
        let now = clock.now()
        let existingCheckpoint = try await checkpointStore.fetchCheckpoint(id: configuration.checkpointID)
        var checkpoint = existingCheckpoint ?? SyncCheckpoint(
            id: configuration.checkpointID,
            taskVersionCursor: 0,
            noteVersionCursor: 0,
            calendarToken: nil,
            updatedAt: now,
        )

        let accumulator = SyncRunAccumulator()

        let changedTasks = try await taskStore.fetchTasksUpdated(
            afterVersion: checkpoint.taskVersionCursor,
            limit: configuration.taskBatchSize,
        )

        var highestTaskVersion = checkpoint.taskVersionCursor

        for task in changedTasks {
            highestTaskVersion = max(highestTaskVersion, task.version)
            if task.deletedAt != nil {
                let deleted = try await pushTaskDeletion(
                    task,
                    configuration: configuration,
                    now: now,
                    accumulator: accumulator,
                )
                if deleted {
                    accumulator.eventsDeletedFromTasks += 1
                }
                continue
            }

            let binding = try await bindingStore.fetchBinding(
                entityType: .task,
                entityID: task.id,
                calendarID: configuration.calendarID,
            )
            let outgoingEvent = try taskMapper.event(from: task, calendarID: configuration.calendarID, existing: binding)
            let persistedEvent = try await performProviderOperation(
                operation: .pushTaskUpsert,
                entityType: .task,
                entityID: task.id,
                taskID: task.id,
                eventIdentifier: outgoingEvent.eventIdentifier,
                externalIdentifier: outgoingEvent.externalIdentifier,
                calendarID: configuration.calendarID,
                configuration: configuration,
                accumulator: accumulator,
            ) {
                try await calendarProvider.upsertEvent(outgoingEvent)
            }

            guard let eventIdentifier = persistedEvent.eventIdentifier else {
                throw SyncError.missingEventIdentifier
            }

            let updatedBinding = CalendarBinding(
                entityType: .task,
                entityID: task.id,
                calendarID: configuration.calendarID,
                eventIdentifier: eventIdentifier,
                externalIdentifier: persistedEvent.externalIdentifier,
                lastEntityVersion: task.version,
                lastEventUpdatedAt: persistedEvent.updatedAt,
                lastSyncedAt: now,
                deletedAt: nil,
            )

            try await bindingStore.upsertBinding(updatedBinding)
            accumulator.tasksPushed += 1
        }

        var highestNoteVersion = checkpoint.noteVersionCursor
        if let noteStore {
            let changedNotes = try await noteStore.fetchNotesUpdated(
                afterVersion: checkpoint.noteVersionCursor,
                limit: configuration.taskBatchSize,
            )

            for note in changedNotes {
                highestNoteVersion = max(highestNoteVersion, note.version)
                if note.deletedAt != nil {
                    _ = try await pushNoteDeletion(
                        note,
                        configuration: configuration,
                        now: now,
                        accumulator: accumulator,
                    )
                    continue
                }
                if !note.calendarSyncEnabled || note.dateStart == nil {
                    continue
                }

                let binding = try await bindingStore.fetchBinding(
                    entityType: .note,
                    entityID: note.id,
                    calendarID: configuration.calendarID,
                )
                let outgoingEvent = try noteMapper.event(from: note, calendarID: configuration.calendarID, existing: binding)
                let persistedEvent = try await performProviderOperation(
                    operation: .pushNoteUpsert,
                    entityType: .note,
                    entityID: note.id,
                    eventIdentifier: outgoingEvent.eventIdentifier,
                    externalIdentifier: outgoingEvent.externalIdentifier,
                    calendarID: configuration.calendarID,
                    configuration: configuration,
                    accumulator: accumulator,
                ) {
                    try await calendarProvider.upsertEvent(outgoingEvent)
                }

                guard let eventIdentifier = persistedEvent.eventIdentifier else {
                    throw SyncError.missingEventIdentifier
                }

                let updatedBinding = CalendarBinding(
                    entityType: .note,
                    entityID: note.id,
                    calendarID: configuration.calendarID,
                    eventIdentifier: eventIdentifier,
                    externalIdentifier: persistedEvent.externalIdentifier,
                    lastEntityVersion: note.version,
                    lastEventUpdatedAt: persistedEvent.updatedAt,
                    lastSyncedAt: now,
                    deletedAt: nil,
                )
                try await bindingStore.upsertBinding(updatedBinding)
            }
        }

        let batch = try await performProviderOperation(
            operation: .pullCalendarChanges,
            calendarID: configuration.calendarID,
            configuration: configuration,
            accumulator: accumulator,
        ) {
            try await calendarProvider.fetchChanges(
                since: checkpoint.calendarToken,
                calendarID: configuration.calendarID,
            )
        }

        for change in batch.changes {
            accumulator.eventsPulled += 1
            switch change {
            case let .upsert(event):
                let result = try await pullEventUpsert(
                    event,
                    configuration: configuration,
                    now: now,
                    accumulator: accumulator,
                )
                accumulator.tasksImported += result.imported
                accumulator.tasksUpdatedFromCalendar += result.updated

            case let .delete(deletion):
                if try await pullEventDeletion(
                    deletion,
                    configuration: configuration,
                    now: now,
                    accumulator: accumulator,
                ) {
                    accumulator.tasksDeletedFromCalendar += 1
                }
            }
        }

        checkpoint.taskVersionCursor = highestTaskVersion
        checkpoint.noteVersionCursor = highestNoteVersion
        checkpoint.calendarToken = batch.nextToken
        checkpoint.updatedAt = now
        try await checkpointStore.saveCheckpoint(checkpoint)

        var report = accumulator.makeReport()
        report.finalTaskVersionCursor = checkpoint.taskVersionCursor
        report.finalCalendarToken = checkpoint.calendarToken
        return report
    }

    private func pullEventUpsert(
        _ event: CalendarEvent,
        configuration: SyncEngineConfiguration,
        now: Date,
        accumulator: SyncRunAccumulator,
    ) async throws -> (imported: Int, updated: Int) {
        guard event.calendarID == configuration.calendarID else {
            recordDiagnostic(
                accumulator: accumulator,
                operation: .pullEventUpsert,
                severity: .info,
                message: "Ignored event because calendar ID does not match sync target.",
                taskID: nil,
                eventIdentifier: event.eventIdentifier,
                externalIdentifier: event.externalIdentifier,
                calendarID: configuration.calendarID,
            )
            return (0, 0)
        }

        let binding = try await findBinding(for: event, calendarID: configuration.calendarID)
        let shouldTreatAsNote = noteMapper.isNoteEvent(event) || binding?.entityType == .note

        if shouldTreatAsNote {
            guard let noteStore else {
                recordDiagnostic(
                    accumulator: accumulator,
                    operation: .pullEventUpsert,
                    severity: .warning,
                    message: "Skipped note event because note store is unavailable in sync engine.",
                    entityType: .note,
                    entityID: binding?.entityID,
                    eventIdentifier: event.eventIdentifier,
                    externalIdentifier: event.externalIdentifier,
                    calendarID: configuration.calendarID,
                )
                return (0, 0)
            }

            if let binding {
                guard var currentNote = try await noteStore.fetchNote(id: binding.entityID), currentNote.deletedAt == nil else {
                    recordDiagnostic(
                        accumulator: accumulator,
                        operation: .pullEventUpsert,
                        severity: .warning,
                        message: "Ignored note event upsert because binding points to missing or deleted note.",
                        entityType: .note,
                        entityID: binding.entityID,
                        eventIdentifier: event.eventIdentifier,
                        externalIdentifier: event.externalIdentifier,
                        calendarID: configuration.calendarID,
                    )
                    return (0, 0)
                }

                let noteWins = shouldNoteWinConflict(
                    note: currentNote,
                    event: event,
                    binding: binding,
                    policy: configuration.policy,
                    timestampNormalizationSeconds: configuration.timestampNormalizationSeconds,
                    lastWriteWinsTieBreaker: configuration.lastWriteWinsTieBreaker,
                )

                if noteWins {
                    let outgoing = try noteMapper.event(from: currentNote, calendarID: configuration.calendarID, existing: binding)
                    let persistedEvent = try await performProviderOperation(
                        operation: .pushNoteUpsert,
                        entityType: .note,
                        entityID: currentNote.id,
                        eventIdentifier: outgoing.eventIdentifier,
                        externalIdentifier: outgoing.externalIdentifier,
                        calendarID: configuration.calendarID,
                        configuration: configuration,
                        accumulator: accumulator,
                    ) {
                        try await calendarProvider.upsertEvent(outgoing)
                    }
                    let updatedBinding = CalendarBinding(
                        entityType: .note,
                        entityID: currentNote.id,
                        calendarID: configuration.calendarID,
                        eventIdentifier: persistedEvent.eventIdentifier ?? binding.eventIdentifier,
                        externalIdentifier: persistedEvent.externalIdentifier ?? binding.externalIdentifier,
                        lastEntityVersion: currentNote.version,
                        lastEventUpdatedAt: persistedEvent.updatedAt,
                        lastSyncedAt: now,
                        deletedAt: nil,
                    )
                    try await bindingStore.upsertBinding(updatedBinding)
                    return (0, 0)
                }

                let noteFromEvent = noteMapper.note(from: event, existing: currentNote)
                currentNote = try await noteStore.upsertNote(noteFromEvent)
                let updatedBinding = CalendarBinding(
                    entityType: .note,
                    entityID: currentNote.id,
                    calendarID: configuration.calendarID,
                    eventIdentifier: event.eventIdentifier ?? binding.eventIdentifier,
                    externalIdentifier: event.externalIdentifier ?? binding.externalIdentifier,
                    lastEntityVersion: currentNote.version,
                    lastEventUpdatedAt: event.updatedAt,
                    lastSyncedAt: now,
                    deletedAt: nil,
                )
                try await bindingStore.upsertBinding(updatedBinding)
                return (0, 1)
            }

            if event.recurrenceExceptionDate != nil {
                recordDiagnostic(
                    accumulator: accumulator,
                    operation: .pullEventUpsert,
                    severity: .info,
                    message: "Skipped detached recurrence exception without an existing note binding.",
                    entityType: .note,
                    entityID: nil,
                    eventIdentifier: event.eventIdentifier,
                    externalIdentifier: event.externalIdentifier,
                    calendarID: configuration.calendarID,
                )
                return (0, 0)
            }

            let importedNote = noteMapper.note(from: event, existing: nil)
            let persistedNote = try await noteStore.upsertNote(importedNote)
            let noteBinding = CalendarBinding(
                entityType: .note,
                entityID: persistedNote.id,
                calendarID: configuration.calendarID,
                eventIdentifier: event.eventIdentifier,
                externalIdentifier: event.externalIdentifier,
                lastEntityVersion: persistedNote.version,
                lastEventUpdatedAt: event.updatedAt,
                lastSyncedAt: now,
                deletedAt: nil,
            )
            try await bindingStore.upsertBinding(noteBinding)
            return (1, 0)
        }

        if let binding {
            guard let currentTask = try await taskStore.fetchTask(id: binding.taskID), currentTask.deletedAt == nil else {
                recordDiagnostic(
                    accumulator: accumulator,
                    operation: .pullEventUpsert,
                    severity: .warning,
                    message: "Ignored event upsert because binding points to missing or deleted task.",
                    entityType: .task,
                    entityID: binding.entityID,
                    taskID: binding.taskID,
                    eventIdentifier: event.eventIdentifier,
                    externalIdentifier: event.externalIdentifier,
                    calendarID: configuration.calendarID,
                )
                return (0, 0)
            }

            let resolution = try taskMapper.resolve(
                task: currentTask,
                event: event,
                binding: binding,
                policy: configuration.policy,
                timestampNormalizationSeconds: configuration.timestampNormalizationSeconds,
                lastWriteWinsTieBreaker: configuration.lastWriteWinsTieBreaker,
            )

            switch resolution {
            case .keepTask:
                return (0, 0)

            case let .taskWins(task):
                let outgoing = try taskMapper.event(from: task, calendarID: configuration.calendarID, existing: binding)
                let persistedEvent = try await performProviderOperation(
                    operation: .pushTaskUpsert,
                    entityType: .task,
                    entityID: task.id,
                    taskID: task.id,
                    eventIdentifier: outgoing.eventIdentifier,
                    externalIdentifier: outgoing.externalIdentifier,
                    calendarID: configuration.calendarID,
                    configuration: configuration,
                    accumulator: accumulator,
                ) {
                    try await calendarProvider.upsertEvent(outgoing)
                }

                let updatedBinding = CalendarBinding(
                    entityType: .task,
                    entityID: task.id,
                    calendarID: configuration.calendarID,
                    eventIdentifier: persistedEvent.eventIdentifier ?? binding.eventIdentifier,
                    externalIdentifier: persistedEvent.externalIdentifier ?? binding.externalIdentifier,
                    lastEntityVersion: task.version,
                    lastEventUpdatedAt: persistedEvent.updatedAt,
                    lastSyncedAt: now,
                    deletedAt: nil,
                )
                try await bindingStore.upsertBinding(updatedBinding)
                return (0, 0)

            case let .eventWins(taskFromEvent):
                let persistedTask = try await taskStore.upsertTask(taskFromEvent)
                let resolvedEventID = event.eventIdentifier ?? binding.eventIdentifier
                let updatedBinding = CalendarBinding(
                    entityType: .task,
                    entityID: persistedTask.id,
                    calendarID: configuration.calendarID,
                    eventIdentifier: resolvedEventID,
                    externalIdentifier: event.externalIdentifier ?? binding.externalIdentifier,
                    lastEntityVersion: persistedTask.version,
                    lastEventUpdatedAt: event.updatedAt,
                    lastSyncedAt: now,
                    deletedAt: nil,
                )
                try await bindingStore.upsertBinding(updatedBinding)
                return (0, 1)
            }
        }

        // Detached recurrence instances should not create standalone tasks.
        if event.recurrenceExceptionDate != nil {
            recordDiagnostic(
                accumulator: accumulator,
                operation: .pullEventUpsert,
                severity: .info,
                message: "Skipped detached recurrence exception without an existing task binding.",
                entityType: .task,
                entityID: nil,
                taskID: nil,
                eventIdentifier: event.eventIdentifier,
                externalIdentifier: event.externalIdentifier,
                calendarID: configuration.calendarID,
            )
            return (0, 0)
        }

        let importedTask = try taskMapper.task(from: event, existingTask: nil)
        let persistedTask = try await taskStore.upsertTask(importedTask)

        let bindingToSave = CalendarBinding(
            entityType: .task,
            entityID: persistedTask.id,
            calendarID: configuration.calendarID,
            eventIdentifier: event.eventIdentifier,
            externalIdentifier: event.externalIdentifier,
            lastEntityVersion: persistedTask.version,
            lastEventUpdatedAt: event.updatedAt,
            lastSyncedAt: now,
            deletedAt: nil,
        )
        try await bindingStore.upsertBinding(bindingToSave)

        return (1, 0)
    }

    private func pullEventDeletion(
        _ deletion: CalendarDeletion,
        configuration: SyncEngineConfiguration,
        now: Date,
        accumulator: SyncRunAccumulator,
    ) async throws -> Bool {
        guard deletion.calendarID == configuration.calendarID else {
            recordDiagnostic(
                accumulator: accumulator,
                operation: .pullEventDelete,
                severity: .info,
                message: "Ignored deletion because calendar ID does not match sync target.",
                taskID: nil,
                eventIdentifier: deletion.eventIdentifier,
                externalIdentifier: deletion.externalIdentifier,
                calendarID: configuration.calendarID,
            )
            return false
        }

        guard let binding = try await findBinding(for: deletion, calendarID: configuration.calendarID) else {
            recordDiagnostic(
                accumulator: accumulator,
                operation: .pullEventDelete,
                severity: .warning,
                message: "Ignored deletion because no binding was found.",
                taskID: nil,
                eventIdentifier: deletion.eventIdentifier,
                externalIdentifier: deletion.externalIdentifier,
                calendarID: configuration.calendarID,
            )
            return false
        }

        switch binding.entityType {
        case .task:
            try await taskStore.tombstoneTask(id: binding.entityID, at: deletion.deletedAt)
            try await bindingStore.tombstoneBinding(entityType: .task, entityID: binding.entityID, calendarID: configuration.calendarID, at: now)
        case .note:
            guard let noteStore else {
                recordDiagnostic(
                    accumulator: accumulator,
                    operation: .pullEventDelete,
                    severity: .warning,
                    message: "Skipped note deletion tombstone because note store is unavailable.",
                    entityType: .note,
                    entityID: binding.entityID,
                    eventIdentifier: deletion.eventIdentifier,
                    externalIdentifier: deletion.externalIdentifier,
                    calendarID: configuration.calendarID,
                )
                return false
            }
            try await noteStore.tombstoneNote(id: binding.entityID, at: deletion.deletedAt)
            try await bindingStore.tombstoneBinding(entityType: .note, entityID: binding.entityID, calendarID: configuration.calendarID, at: now)
        }
        return true
    }

    private func pushTaskDeletion(
        _ task: Task,
        configuration: SyncEngineConfiguration,
        now: Date,
        accumulator: SyncRunAccumulator,
    ) async throws -> Bool {
        guard let binding = try await bindingStore.fetchBinding(entityType: .task, entityID: task.id, calendarID: configuration.calendarID) else {
            recordDiagnostic(
                accumulator: accumulator,
                operation: .pushTaskDelete,
                severity: .info,
                message: "Skipped task deletion push because no calendar binding exists.",
                entityType: .task,
                entityID: task.id,
                taskID: task.id,
                eventIdentifier: nil,
                externalIdentifier: nil,
                calendarID: configuration.calendarID,
            )
            return false
        }

        if let eventIdentifier = binding.eventIdentifier {
            _ = try await performProviderOperation(
                operation: .pushTaskDelete,
                entityType: .task,
                entityID: task.id,
                taskID: task.id,
                eventIdentifier: eventIdentifier,
                externalIdentifier: binding.externalIdentifier,
                calendarID: configuration.calendarID,
                configuration: configuration,
                accumulator: accumulator,
            ) {
                try await calendarProvider.deleteEvent(eventIdentifier: eventIdentifier, calendarID: configuration.calendarID)
            }
        } else {
            recordDiagnostic(
                accumulator: accumulator,
                operation: .pushTaskDelete,
                severity: .warning,
                message: "Binding has no event identifier; tombstoning local binding only.",
                entityType: .task,
                entityID: task.id,
                taskID: task.id,
                eventIdentifier: nil,
                externalIdentifier: binding.externalIdentifier,
                calendarID: configuration.calendarID,
            )
        }

        try await bindingStore.tombstoneBinding(entityType: .task, entityID: task.id, calendarID: configuration.calendarID, at: now)
        return true
    }

    private func pushNoteDeletion(
        _ note: Note,
        configuration: SyncEngineConfiguration,
        now: Date,
        accumulator: SyncRunAccumulator,
    ) async throws -> Bool {
        guard let binding = try await bindingStore.fetchBinding(entityType: .note, entityID: note.id, calendarID: configuration.calendarID) else {
            return false
        }

        if let eventIdentifier = binding.eventIdentifier {
            _ = try await performProviderOperation(
                operation: .pushNoteDelete,
                entityType: .note,
                entityID: note.id,
                eventIdentifier: eventIdentifier,
                externalIdentifier: binding.externalIdentifier,
                calendarID: configuration.calendarID,
                configuration: configuration,
                accumulator: accumulator,
            ) {
                try await calendarProvider.deleteEvent(eventIdentifier: eventIdentifier, calendarID: configuration.calendarID)
            }
        }

        try await bindingStore.tombstoneBinding(entityType: .note, entityID: note.id, calendarID: configuration.calendarID, at: now)
        return true
    }

    private func shouldNoteWinConflict(
        note: Note,
        event: CalendarEvent,
        binding: CalendarBinding,
        policy: ConflictResolutionPolicy,
        timestampNormalizationSeconds: TimeInterval,
        lastWriteWinsTieBreaker: ConflictSource,
    ) -> Bool {
        if let lastEventUpdatedAt = binding.lastEventUpdatedAt,
           event.updatedAt <= lastEventUpdatedAt
        {
            return true
        }

        let lastSynced = binding.lastSyncedAt ?? .distantPast
        let noteChanged = note.updatedAt > lastSynced
        let eventChanged = event.updatedAt > lastSynced

        switch (noteChanged, eventChanged) {
        case (false, false):
            return true
        case (true, false):
            return true
        case (false, true):
            return false
        case (true, true):
            switch policy {
            case .taskPriority:
                return true
            case .calendarPriority:
                return false
            case .lastWriteWins:
                let normalizedNoteTime = normalizedTimestamp(note.updatedAt, granularitySeconds: timestampNormalizationSeconds)
                let normalizedEventTime = normalizedTimestamp(event.updatedAt, granularitySeconds: timestampNormalizationSeconds)
                if normalizedNoteTime > normalizedEventTime {
                    return true
                }
                if normalizedEventTime > normalizedNoteTime {
                    return false
                }
                return lastWriteWinsTieBreaker == .task
            }
        }
    }

    private func normalizedTimestamp(_ date: Date, granularitySeconds: TimeInterval) -> Date {
        let safeGranularity = max(0.001, granularitySeconds)
        let interval = date.timeIntervalSince1970
        let normalizedInterval = floor(interval / safeGranularity) * safeGranularity
        return Date(timeIntervalSince1970: normalizedInterval)
    }

    private func findBinding(for event: CalendarEvent, calendarID: String) async throws -> CalendarBinding? {
        if let eventIdentifier = event.eventIdentifier,
           let binding = try await bindingStore.fetchBinding(eventIdentifier: eventIdentifier, calendarID: calendarID)
        {
            return binding
        }

        if let externalIdentifier = event.externalIdentifier,
           let binding = try await bindingStore.fetchBinding(externalIdentifier: externalIdentifier, calendarID: calendarID)
        {
            return binding
        }

        return nil
    }

    private func findBinding(for deletion: CalendarDeletion, calendarID: String) async throws -> CalendarBinding? {
        if let eventIdentifier = deletion.eventIdentifier,
           let binding = try await bindingStore.fetchBinding(eventIdentifier: eventIdentifier, calendarID: calendarID)
        {
            return binding
        }

        if let externalIdentifier = deletion.externalIdentifier,
           let binding = try await bindingStore.fetchBinding(externalIdentifier: externalIdentifier, calendarID: calendarID)
        {
            return binding
        }

        return nil
    }

    private func performProviderOperation<T>(
        operation: SyncDiagnosticOperation,
        entityType: CalendarBindingEntityType? = nil,
        entityID: UUID? = nil,
        taskID: UUID? = nil,
        eventIdentifier: String? = nil,
        externalIdentifier: String? = nil,
        calendarID: String,
        configuration: SyncEngineConfiguration,
        accumulator: SyncRunAccumulator,
        _ operationBlock: () async throws -> T,
    ) async throws -> T {
        var attempt = 1
        while true {
            do {
                return try await operationBlock()
            } catch {
                let retryable = shouldRetry(error)
                let willRetry = retryable && attempt < configuration.providerMaxRetryAttempts

                let message = willRetry
                    ? "Provider operation failed; retry scheduled."
                    : "Provider operation failed; no more retries."

                recordDiagnostic(
                    accumulator: accumulator,
                    operation: operation,
                    severity: willRetry ? .warning : .error,
                    message: message,
                    entityType: entityType,
                    entityID: entityID,
                    taskID: taskID,
                    eventIdentifier: eventIdentifier,
                    externalIdentifier: externalIdentifier,
                    calendarID: calendarID,
                    providerError: error.localizedDescription,
                    attempt: attempt,
                )

                guard willRetry else {
                    throw error
                }

                let delay = retryDelayNanoseconds(
                    attempt: attempt,
                    baseDelayMilliseconds: configuration.providerRetryBaseDelayMilliseconds,
                    maxDelayMilliseconds: configuration.providerRetryMaxDelayMilliseconds,
                )
                if delay > 0 {
                    try await _Concurrency.Task.sleep(nanoseconds: delay)
                }
                attempt += 1
            }
        }
    }

    private func retryDelayNanoseconds(
        attempt: Int,
        baseDelayMilliseconds: UInt64,
        maxDelayMilliseconds: UInt64,
    ) -> UInt64 {
        guard baseDelayMilliseconds > 0 else {
            return 0
        }
        let multiplier = pow(2, Double(max(0, attempt - 1)))
        let rawDelay = Double(baseDelayMilliseconds) * multiplier
        let cappedDelay = min(Double(maxDelayMilliseconds), rawDelay)
        return UInt64(cappedDelay * 1_000_000)
    }

    private func shouldRetry(_ error: Error) -> Bool {
        if let providerError = error as? CalendarProviderError {
            return providerError.isRetryable
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            let code = URLError.Code(rawValue: nsError.code)
            switch code {
            case .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }

        return false
    }

    private func recordDiagnostic(
        accumulator: SyncRunAccumulator,
        operation: SyncDiagnosticOperation,
        severity: SyncDiagnosticSeverity,
        message: String,
        entityType: CalendarBindingEntityType? = nil,
        entityID: UUID? = nil,
        taskID: UUID? = nil,
        eventIdentifier: String?,
        externalIdentifier: String?,
        calendarID: String,
        providerError: String? = nil,
        attempt: Int? = nil,
    ) {
        accumulator.diagnostics.append(
            SyncDiagnosticEntry(
                operation: operation,
                severity: severity,
                message: message,
                entityType: entityType,
                entityID: entityID,
                taskID: taskID,
                eventIdentifier: eventIdentifier,
                externalIdentifier: externalIdentifier,
                calendarID: calendarID,
                providerError: providerError,
                timestamp: clock.now(),
                attempt: attempt,
            ),
        )
    }
}

private final class SyncRunAccumulator: @unchecked Sendable {
    var tasksPushed: Int = 0
    var eventsPulled: Int = 0
    var tasksImported: Int = 0
    var tasksUpdatedFromCalendar: Int = 0
    var tasksDeletedFromCalendar: Int = 0
    var eventsDeletedFromTasks: Int = 0
    var diagnostics: [SyncDiagnosticEntry] = []

    func makeReport() -> SyncRunReport {
        var report = SyncRunReport()
        report.tasksPushed = tasksPushed
        report.eventsPulled = eventsPulled
        report.tasksImported = tasksImported
        report.tasksUpdatedFromCalendar = tasksUpdatedFromCalendar
        report.tasksDeletedFromCalendar = tasksDeletedFromCalendar
        report.eventsDeletedFromTasks = eventsDeletedFromTasks
        report.diagnostics = diagnostics
        return report
    }
}
