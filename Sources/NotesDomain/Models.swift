import Foundation

/// Represents the execution status of a task in a kanban workflow.
///
/// Tasks progress through these states: `backlog` → `next` → `doing` → `waiting` → `done`.
/// The `waiting` state represents tasks blocked on external dependencies (e.g., awaiting feedback).
///
/// See also: ``KanbanColumn``, ``Task/status``
public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    /// Task is not yet prioritized (backlog column in kanban board)
    case backlog
    /// Task is ready to start (next/ready column)
    case next
    /// Task is currently in progress (doing/in-progress column)
    case doing
    /// Task is blocked waiting for external input (waiting column)
    case waiting
    /// Task is completed (done column)
    case done
}

/// Defines the sort order for displaying tasks in lists and kanban boards.
///
/// Users can sort tasks by any of these criteria. The `title` property returns a user-friendly
/// display name suitable for UI menus and settings.
public enum TaskSortOrder: String, CaseIterable, Codable, Sendable {
    /// Sort by task due date (earliest first), with null values sorted last
    case dueDate
    /// Sort by task priority (0 = highest, 5 = lowest)
    case priority
    /// Sort by task title in alphabetical order (case-insensitive)
    case title
    /// Sort by task creation date (newest first)
    case creationDate

    /// User-friendly display name for this sort order.
    ///
    /// - Returns: Localized string suitable for UI display (e.g., "Due Date", "Priority")
    public var title: String {
        switch self {
        case .dueDate: "Due Date"
        case .priority: "Priority"
        case .title: "Title"
        case .creationDate: "Date Added"
        }
    }
}

/// A note document containing markdown-formatted text and optional calendar metadata.
///
/// Notes support wiki-style `[[wikilinks]]` for cross-references, hashtags `#tag` for categorization,
/// and optional synchronization with Apple Calendar.
///
/// ### Soft Deletion
/// Notes are soft-deleted by setting `deletedAt`. Hard deletes never occur. This prevents ghost
/// re-creation if sync is delayed.
///
/// ### Versioning
/// Each note tracks `version` (incremented on write) and `updatedAt` (timestamp of last change).
/// The sync engine uses these to query only changed records since the last sync.
///
/// ### Calendar Sync
/// If `calendarSyncEnabled` is true, the note creates a calendar event with title and dateStart/dateEnd.
/// Use `stableID` (immutable UUID string) to maintain event identity across edits/renames.
///
/// See also: ``NoteListItem``, ``NoteTemplate``, ``WikiLinkParser``
public struct Note: Codable, Equatable, Sendable {
    /// Unique identifier for this note (UUID)
    public var id: UUID
    /// Immutable stable ID for sync purposes (UUID string, never changes on rename/edit)
    public var stableID: String
    /// User-visible title of the note
    public var title: String
    /// Markdown-formatted body text; supports `[[wikilinks]]` and `#tags`
    public var body: String
    /// Hashtags extracted from the note body (lowercase, without `#`)
    public var tags: [String]
    /// Optional calendar event start date
    public var dateStart: Date?
    /// Optional calendar event end date
    public var dateEnd: Date?
    /// True if the calendar event is all-day
    public var isAllDay: Bool
    /// iCalendar RRULE for recurrence (RFC 5545 format)
    public var recurrenceRule: String?
    /// True if this note is synced with Apple Calendar
    public var calendarSyncEnabled: Bool
    /// Timestamp of last modification (used for sync versioning)
    public var updatedAt: Date
    /// Monotonic version number (incremented on each write)
    public var version: Int64
    /// Timestamp when soft-deleted (nil = not deleted)
    public var deletedAt: Date?

    /// Creates a new note.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (default: random UUID)
    ///   - stableID: Immutable sync ID (default: random UUID string)
    ///   - title: User-visible title (required)
    ///   - body: Markdown body text (required)
    ///   - tags: Hashtags found in body (default: empty)
    ///   - dateStart: Calendar event start date (default: nil)
    ///   - dateEnd: Calendar event end date (default: nil); if after dateStart, will be clamped
    ///   - isAllDay: True for all-day calendar events (default: false)
    ///   - recurrenceRule: iCalendar RRULE string (default: nil)
    ///   - calendarSyncEnabled: True to sync with Apple Calendar (default: false)
    ///   - updatedAt: Timestamp of creation (required)
    ///   - version: Version number (default: 0)
    ///   - deletedAt: Soft-delete timestamp, nil if active (default: nil)
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
        deletedAt: Date? = nil,
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

/// Search mode for querying notes by text content.
///
/// Determines how search queries are matched against note titles and bodies.
/// Results are ranked by relevance and paginated in chunks of 50.
public enum NoteSearchMode: String, Codable, CaseIterable, Sendable {
    /// Balanced search: matches keywords with fuzzy ranking (prefix > contains > fuzzy)
    case smart
    /// Phrase search: exact phrase match in title or body
    case phrase
    /// Prefix search: matches beginning of words only
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
        hits: [NoteSearchHit],
    ) {
        self.query = query
        self.mode = mode
        self.offset = max(0, offset)
        self.limit = max(1, limit)
        self.totalCount = max(0, totalCount)
        self.hits = hits
    }
}

/// A to-do item with scheduling, priority, status, and optional calendar synchronization.
///
/// Tasks are organized by `status` in a kanban board and can be filtered by due date or
/// priority. Each task has a `stableID` (immutable UUID string) used for calendar event binding,
/// ensuring edits/renames do not create duplicate calendar entries.
///
/// ### Priority Levels
/// Priority is an integer from 0 (highest) to 5 (lowest). Invalid ranges throw ``DomainValidationError/invalidPriority(_:)``.
///
/// ### Subtasks
/// Tasks can contain 1-N subtasks. Completing all subtasks optionally auto-completes the parent.
///
/// ### Calendar Sync
/// If linked to a calendar event via binding, the task syncs its title, due dates, and completion status.
/// `stableID` is immutable to maintain event identity.
///
/// ### Soft Deletion
/// Soft-deleted by setting `deletedAt`. Hard deletes never occur.
///
/// See also: ``TaskStatus``, ``TaskLabel``, ``Subtask``, ``CalendarBinding``
public struct Task: Identifiable, Codable, Equatable, Sendable {
    /// Unique identifier for this task (UUID)
    public var id: UUID
    /// Optional ID of the linked note (if this task is in a note's context)
    public var noteID: UUID?
    /// Immutable stable ID for calendar sync (never changes on rename/edit)
    public var stableID: String
    /// User-visible task title
    public var title: String
    /// Extended description or details
    public var details: String
    /// Optional due date start (for range-based due dates)
    public var dueStart: Date?
    /// Optional due date end (for range-based due dates)
    public var dueEnd: Date?
    /// Current execution status in kanban workflow (backlog, next, doing, waiting, done)
    public var status: TaskStatus
    /// Priority level 0-5 (0 = highest, 5 = lowest)
    public var priority: Int
    /// iCalendar RRULE for recurrence (RFC 5545 format)
    public var recurrenceRule: String?
    /// Ordering key for kanban columns (not strictly sequential)
    public var kanbanOrder: Double
    /// Timestamp when task was marked complete (nil = not completed)
    public var completedAt: Date?
    /// Timestamp of last modification (used for sync versioning)
    public var updatedAt: Date
    /// Monotonic version number (incremented on each write)
    public var version: Int64
    /// Timestamp when soft-deleted (nil = not deleted)
    public var deletedAt: Date?
    /// Color-coded labels for categorization
    public var labels: [TaskLabel]
    /// ID of the custom kanban column this task belongs to (nil = uses status column)
    public var kanbanColumnID: UUID?
    /// Subtasks (1-N nested to-do items); completing all can auto-complete parent
    public var subtasks: [Subtask]

    /// Creates a new task with validation.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (default: random UUID)
    ///   - noteID: Optional linked note (default: nil)
    ///   - stableID: Immutable sync ID (required)
    ///   - title: User-visible title (required)
    ///   - details: Extended description (default: empty)
    ///   - dueStart: Due date start (default: nil)
    ///   - dueEnd: Due date end (default: nil); must not be before dueStart
    ///   - status: Kanban status (default: .backlog)
    ///   - priority: Priority 0-5 (default: 3)
    ///   - recurrenceRule: iCalendar RRULE (default: nil)
    ///   - kanbanOrder: Ordering key (default: 0)
    ///   - completedAt: Completion timestamp (default: nil)
    ///   - updatedAt: Last modification timestamp (required)
    ///   - version: Version number (default: 0)
    ///   - deletedAt: Soft-delete timestamp (default: nil)
    ///   - labels: Color-coded labels (default: empty)
    ///   - kanbanColumnID: Custom column ID (default: nil)
    ///   - subtasks: Nested to-do items (default: empty)
    /// - Throws: ``DomainValidationError/invalidPriority(_:)`` if priority not in 0-5
    /// - Throws: ``DomainValidationError/invalidDateRange`` if dueEnd before dueStart
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
        deletedAt: Date? = nil,
        labels: [TaskLabel] = [],
        kanbanColumnID: UUID? = nil,
        subtasks: [Subtask] = [],
    ) throws {
        guard (0 ... 5).contains(priority) else {
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
        self.labels = labels
        self.kanbanColumnID = kanbanColumnID
        self.subtasks = subtasks
    }
}

/// A calendar event imported from Apple Calendar or created from a synchronized task/note.
///
/// Calendar events maintain bidirectional sync with their source tasks or notes via a
/// ``CalendarBinding``. The `eventIdentifier` and `externalIdentifier` are stored to handle
/// identifier drift during sync conflicts.
///
/// See also: ``CalendarBinding``, ``ConflictResolutionPolicy``
public struct CalendarEvent: Codable, Equatable, Sendable {
    /// Event ID from Apple Calendar (nil if created locally)
    public var eventIdentifier: String?
    /// External event ID from calendar provider (fallback identifier for conflict resolution)
    public var externalIdentifier: String?
    /// ID of the calendar this event belongs to
    public var calendarID: String
    /// Event title
    public var title: String
    /// Event notes/description
    public var notes: String?
    /// Event start date (nil for all-day events with dateOnly semantics)
    public var startDate: Date?
    /// Event end date (must not be before startDate)
    public var endDate: Date?
    /// True if this is an all-day event
    public var isAllDay: Bool
    /// iCalendar RRULE for recurrence (RFC 5545 format)
    public var recurrenceRule: String?
    /// Date of a recurrence exception (for "This Occurrence" edits)
    public var recurrenceExceptionDate: Date?
    /// True if event is marked as completed/done
    public var isCompleted: Bool
    /// Timestamp of last modification
    public var updatedAt: Date
    /// Type of source entity (task or note)
    public var sourceEntityType: CalendarBindingEntityType?
    /// Stable ID of the source entity (immutable sync ID)
    public var sourceStableID: String?

    /// Creates a new calendar event with validation.
    ///
    /// - Parameters:
    ///   - eventIdentifier: Apple Calendar event ID (default: nil)
    ///   - externalIdentifier: External provider event ID (default: nil)
    ///   - calendarID: Calendar ID (required)
    ///   - title: Event title (required)
    ///   - notes: Event description (default: nil)
    ///   - startDate: Start date (default: nil)
    ///   - endDate: End date (default: nil); must not be before startDate
    ///   - isAllDay: True for all-day events (default: false)
    ///   - recurrenceRule: iCalendar RRULE string (default: nil)
    ///   - recurrenceExceptionDate: Date of exception (default: nil)
    ///   - isCompleted: True if done (default: false)
    ///   - updatedAt: Last modification timestamp (required)
    ///   - sourceEntityType: Task or note origin (default: nil)
    ///   - sourceStableID: Source entity's immutable ID (default: nil)
    /// - Throws: ``DomainValidationError/invalidDateRange`` if endDate before startDate
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
        sourceStableID: String? = nil,
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
        deletedAt: Date,
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

/// Maps a task or note to its synchronized calendar event.
///
/// Bindings enable bidirectional sync: local changes push to calendar, and calendar changes
/// are pulled and reconciled. Version tracking (`lastEntityVersion`, `lastEventUpdatedAt`) and
/// timestamps enable incremental sync without full re-downloads.
///
/// ### Identifiers
/// Both `eventIdentifier` (from Apple Calendar) and `externalIdentifier` (from provider) are
/// stored to handle identifier drift during sync conflicts.
///
/// See also: ``CalendarEvent``, ``ConflictResolutionPolicy``, ``SyncCheckpoint``
public struct CalendarBinding: Codable, Equatable, Sendable {
    /// Type of entity being synced (task or note)
    public var entityType: CalendarBindingEntityType
    /// ID of the synced entity (task or note)
    public var entityID: UUID
    /// Calendar ID the event belongs to
    public var calendarID: String
    /// Event ID from Apple Calendar (nil if not yet synced)
    public var eventIdentifier: String?
    /// External event ID (fallback for conflict resolution)
    public var externalIdentifier: String?
    /// Version number of entity at last sync
    public var lastEntityVersion: Int64
    /// Timestamp of event at last sync
    public var lastEventUpdatedAt: Date?
    /// Timestamp of last successful sync
    public var lastSyncedAt: Date?
    /// Soft-delete timestamp (nil = binding active)
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
        deletedAt: Date? = nil,
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
        deletedAt: Date? = nil,
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
            deletedAt: deletedAt,
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
        updatedAt: Date,
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

public struct TaskLabel: Codable, Equatable, Sendable, Hashable {
    public var name: String
    public var colorHex: String

    public init(name: String, colorHex: String) {
        self.name = name
        self.colorHex = colorHex
    }
}

/// A nested to-do item within a parent task.
///
/// Subtasks are stored as JSON in the parent `Task` and support completion tracking.
/// When all subtasks of a parent task are marked complete, the parent task can optionally
/// be auto-completed.
///
/// See also: ``Task/subtasks``
public struct Subtask: Identifiable, Codable, Equatable, Sendable {
    /// Unique identifier for this subtask
    public var id: UUID
    /// Subtask title/description
    public var title: String
    /// True if this subtask is completed
    public var isCompleted: Bool
    /// Ordering position within the parent task's subtask list
    public var order: Int

    /// Creates a new subtask.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (default: random UUID)
    ///   - title: Subtask title (required)
    ///   - isCompleted: True if done (default: false)
    ///   - order: Ordering position (required)
    public init(id: UUID = UUID(), title: String, isCompleted: Bool = false, order: Int) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.order = order
    }
}

public struct KanbanColumn: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var builtInStatus: TaskStatus?
    public var position: Int
    public var wipLimit: Int?
    public var colorHex: String?

    public init(
        id: UUID = UUID(),
        title: String,
        builtInStatus: TaskStatus? = nil,
        position: Int,
        wipLimit: Int? = nil,
        colorHex: String? = nil,
    ) {
        self.id = id
        self.title = title
        self.builtInStatus = builtInStatus
        self.position = position
        self.wipLimit = wipLimit
        self.colorHex = colorHex
    }
}

public enum KanbanGrouping: String, CaseIterable, Codable, Sendable {
    case none
    case priority
    case note
    case label
}
