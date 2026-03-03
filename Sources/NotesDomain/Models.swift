import Foundation

public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case backlog
    case next
    case doing
    case waiting
    case done
}

public struct Note: Codable, Equatable, Sendable {
    public var id: UUID
    public var stableID: String
    public var title: String
    public var body: String
    public var tags: [String]
    public var dateStart: Date?
    public var dateEnd: Date?
    public var isAllDay: Bool
    public var recurrenceRule: String?
    public var calendarSyncEnabled: Bool
    public var updatedAt: Date
    public var version: Int64
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        stableID: String = UUID().uuidString.lowercased(),
        title: String,
        body: String,
        tags: [String] = [],
        dateStart: Date? = nil,
        dateEnd: Date? = nil,
        isAllDay: Bool = false,
        recurrenceRule: String? = nil,
        calendarSyncEnabled: Bool = false,
        updatedAt: Date,
        version: Int64 = 0,
        deletedAt: Date? = nil
    ) {
        if let dateStart, let dateEnd, dateEnd < dateStart {
            // Keep Notes init non-throwing to preserve call-site ergonomics.
            self.dateStart = dateStart
            self.dateEnd = dateStart
        } else {
            self.dateStart = dateStart
            self.dateEnd = dateEnd
        }
        self.id = id
        self.stableID = stableID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? UUID().uuidString.lowercased()
            : stableID
        self.title = title
        self.body = body
        self.tags = tags
        self.isAllDay = isAllDay
        self.recurrenceRule = recurrenceRule
        self.calendarSyncEnabled = calendarSyncEnabled
        self.updatedAt = updatedAt
        self.version = version
        self.deletedAt = deletedAt
    }

    public var listItem: NoteListItem {
        NoteListItem(id: id, stableID: stableID, title: title, tags: tags, updatedAt: updatedAt)
    }
}

public struct NoteListItem: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var stableID: String
    public var title: String
    public var tags: [String]
    public var updatedAt: Date

    public init(id: UUID, stableID: String, title: String, tags: [String], updatedAt: Date) {
        self.id = id
        self.stableID = stableID
        self.title = title
        self.tags = tags
        self.updatedAt = updatedAt
    }
}

public struct NoteListItemPage: Equatable, Sendable {
    public var offset: Int
    public var limit: Int
    public var totalCount: Int
    public var items: [NoteListItem]

    public var nextOffset: Int? {
        guard !items.isEmpty else { return nil }
        let candidate = offset + items.count
        return candidate < totalCount ? candidate : nil
    }

    public init(offset: Int, limit: Int, totalCount: Int, items: [NoteListItem]) {
        self.offset = max(0, offset)
        self.limit = max(1, limit)
        self.totalCount = max(0, totalCount)
        self.items = items
    }
}

public enum NoteSearchMode: String, Codable, CaseIterable, Sendable {
    case smart
    case phrase
    case prefix
}

public struct NoteSearchHit: Codable, Equatable, Sendable {
    public var note: Note
    public var snippet: String?
    public var rank: Double

    public init(note: Note, snippet: String?, rank: Double) {
        self.note = note
        self.snippet = snippet
        self.rank = rank
    }
}

public struct NoteSearchPage: Codable, Equatable, Sendable {
    public var query: String
    public var mode: NoteSearchMode
    public var offset: Int
    public var limit: Int
    public var totalCount: Int
    public var hits: [NoteSearchHit]

    public var nextOffset: Int? {
        let candidate = offset + hits.count
        return candidate < totalCount ? candidate : nil
    }

    public init(
        query: String,
        mode: NoteSearchMode,
        offset: Int,
        limit: Int,
        totalCount: Int,
        hits: [NoteSearchHit]
    ) {
        self.query = query
        self.mode = mode
        self.offset = max(0, offset)
        self.limit = max(1, limit)
        self.totalCount = max(0, totalCount)
        self.hits = hits
    }
}

public struct Task: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var noteID: UUID?
    public var stableID: String
    public var title: String
    public var details: String
    public var dueStart: Date?
    public var dueEnd: Date?
    public var status: TaskStatus
    public var priority: Int
    public var recurrenceRule: String?
    public var kanbanOrder: Double
    public var completedAt: Date?
    public var updatedAt: Date
    public var version: Int64
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        noteID: UUID? = nil,
        stableID: String,
        title: String,
        details: String = "",
        dueStart: Date? = nil,
        dueEnd: Date? = nil,
        status: TaskStatus = .backlog,
        priority: Int = 3,
        recurrenceRule: String? = nil,
        kanbanOrder: Double = 0,
        completedAt: Date? = nil,
        updatedAt: Date,
        version: Int64 = 0,
        deletedAt: Date? = nil
    ) throws {
        guard (0...5).contains(priority) else {
            throw DomainValidationError.invalidPriority(priority)
        }
        if let dueStart, let dueEnd, dueEnd < dueStart {
            throw DomainValidationError.invalidDateRange
        }
        self.id = id
        self.noteID = noteID
        self.stableID = stableID
        self.title = title
        self.details = details
        self.dueStart = dueStart
        self.dueEnd = dueEnd
        self.status = status
        self.priority = priority
        self.recurrenceRule = recurrenceRule
        self.kanbanOrder = kanbanOrder
        self.completedAt = completedAt
        self.updatedAt = updatedAt
        self.version = version
        self.deletedAt = deletedAt
    }
}

public struct CalendarEvent: Codable, Equatable, Sendable {
    public var eventIdentifier: String?
    public var externalIdentifier: String?
    public var calendarID: String
    public var title: String
    public var notes: String?
    public var startDate: Date?
    public var endDate: Date?
    public var isAllDay: Bool
    public var recurrenceRule: String?
    public var recurrenceExceptionDate: Date?
    public var isCompleted: Bool
    public var updatedAt: Date
    public var sourceEntityType: CalendarBindingEntityType?
    public var sourceStableID: String?

    public init(
        eventIdentifier: String? = nil,
        externalIdentifier: String? = nil,
        calendarID: String,
        title: String,
        notes: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        isAllDay: Bool = false,
        recurrenceRule: String? = nil,
        recurrenceExceptionDate: Date? = nil,
        isCompleted: Bool = false,
        updatedAt: Date,
        sourceEntityType: CalendarBindingEntityType? = nil,
        sourceStableID: String? = nil
    ) throws {
        if let startDate, let endDate, endDate < startDate {
            throw DomainValidationError.invalidDateRange
        }
        self.eventIdentifier = eventIdentifier
        self.externalIdentifier = externalIdentifier
        self.calendarID = calendarID
        self.title = title
        self.notes = notes
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.recurrenceRule = recurrenceRule
        self.recurrenceExceptionDate = recurrenceExceptionDate
        self.isCompleted = isCompleted
        self.updatedAt = updatedAt
        self.sourceEntityType = sourceEntityType
        self.sourceStableID = sourceStableID
    }
}

public struct CalendarDeletion: Equatable, Sendable {
    public var eventIdentifier: String?
    public var externalIdentifier: String?
    public var calendarID: String
    public var deletedAt: Date

    public init(
        eventIdentifier: String? = nil,
        externalIdentifier: String? = nil,
        calendarID: String,
        deletedAt: Date
    ) {
        self.eventIdentifier = eventIdentifier
        self.externalIdentifier = externalIdentifier
        self.calendarID = calendarID
        self.deletedAt = deletedAt
    }
}

public enum CalendarChange: Equatable, Sendable {
    case upsert(CalendarEvent)
    case delete(CalendarDeletion)
}

public struct CalendarChangeBatch: Equatable, Sendable {
    public var changes: [CalendarChange]
    public var nextToken: String?

    public init(changes: [CalendarChange], nextToken: String?) {
        self.changes = changes
        self.nextToken = nextToken
    }
}

public struct CalendarBinding: Codable, Equatable, Sendable {
    public var entityType: CalendarBindingEntityType
    public var entityID: UUID
    public var calendarID: String
    public var eventIdentifier: String?
    public var externalIdentifier: String?
    public var lastEntityVersion: Int64
    public var lastEventUpdatedAt: Date?
    public var lastSyncedAt: Date?
    public var deletedAt: Date?

    public var taskID: UUID {
        get { entityID }
        set { entityID = newValue }
    }

    public var lastTaskVersion: Int64 {
        get { lastEntityVersion }
        set { lastEntityVersion = newValue }
    }

    public init(
        entityType: CalendarBindingEntityType,
        entityID: UUID,
        calendarID: String,
        eventIdentifier: String? = nil,
        externalIdentifier: String? = nil,
        lastEntityVersion: Int64 = 0,
        lastEventUpdatedAt: Date? = nil,
        lastSyncedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.entityType = entityType
        self.entityID = entityID
        self.calendarID = calendarID
        self.eventIdentifier = eventIdentifier
        self.externalIdentifier = externalIdentifier
        self.lastEntityVersion = lastEntityVersion
        self.lastEventUpdatedAt = lastEventUpdatedAt
        self.lastSyncedAt = lastSyncedAt
        self.deletedAt = deletedAt
    }

    public init(
        taskID: UUID,
        calendarID: String,
        eventIdentifier: String? = nil,
        externalIdentifier: String? = nil,
        lastTaskVersion: Int64 = 0,
        lastEventUpdatedAt: Date? = nil,
        lastSyncedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.init(
            entityType: .task,
            entityID: taskID,
            calendarID: calendarID,
            eventIdentifier: eventIdentifier,
            externalIdentifier: externalIdentifier,
            lastEntityVersion: lastTaskVersion,
            lastEventUpdatedAt: lastEventUpdatedAt,
            lastSyncedAt: lastSyncedAt,
            deletedAt: deletedAt
        )
    }
}

public enum CalendarBindingEntityType: String, Codable, Sendable {
    case task
    case note
}

public struct SyncCheckpoint: Codable, Equatable, Sendable {
    public var id: String
    public var taskVersionCursor: Int64
    public var noteVersionCursor: Int64
    public var calendarToken: String?
    public var updatedAt: Date

    public init(
        id: String,
        taskVersionCursor: Int64,
        noteVersionCursor: Int64 = 0,
        calendarToken: String?,
        updatedAt: Date
    ) {
        self.id = id
        self.taskVersionCursor = taskVersionCursor
        self.noteVersionCursor = noteVersionCursor
        self.calendarToken = calendarToken
        self.updatedAt = updatedAt
    }
}

public enum ConflictResolutionPolicy: Sendable {
    case lastWriteWins
    case calendarPriority
    case taskPriority
}

public enum ConflictSource: Sendable {
    case task
    case calendar
}

public struct NoteTemplate: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var body: String
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, body: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.body = body
        self.createdAt = createdAt
    }
}

public struct GraphNode: Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var tagCount: Int

    public init(id: UUID, title: String, tagCount: Int) {
        self.id = id
        self.title = title
        self.tagCount = tagCount
    }
}

public struct GraphEdge: Equatable, Sendable {
    public var fromID: UUID
    public var toID: UUID

    public init(fromID: UUID, toID: UUID) {
        self.fromID = fromID
        self.toID = toID
    }
}
