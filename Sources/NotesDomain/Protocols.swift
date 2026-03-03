import Foundation

public protocol Clock: Sendable {
    func now() -> Date
}

public struct SystemClock: Clock {
    public init() {}

    public func now() -> Date {
        Date()
    }
}

public protocol TaskStore: Sendable {
    func upsertTask(_ task: Task) async throws -> Task
    func fetchTask(id: UUID) async throws -> Task?
    func fetchTaskByStableID(_ stableID: String) async throws -> Task?
    func fetchTasks(includeDeleted: Bool) async throws -> [Task]
    func fetchTasksUpdated(afterVersion version: Int64, limit: Int) async throws -> [Task]
    func tombstoneTask(id: UUID, at date: Date) async throws
}

public protocol NoteStore: Sendable {
    func upsertNote(_ note: Note) async throws -> Note
    func fetchNote(id: UUID) async throws -> Note?
    func fetchNoteByStableID(_ stableID: String) async throws -> Note?
    func fetchNoteByTitle(_ title: String) async throws -> Note?
    func fetchNotes(includeDeleted: Bool) async throws -> [Note]
    func fetchNotesUpdated(afterVersion version: Int64, limit: Int) async throws -> [Note]
    func searchNotes(query: String, limit: Int) async throws -> [Note]
    func searchNotes(query: String, mode: NoteSearchMode, limit: Int, offset: Int) async throws -> NoteSearchPage
    func fetchNotesByTag(_ tag: String) async throws -> [Note]
    func fetchNoteListItems(includeDeleted: Bool) async throws -> [NoteListItem]
    func fetchNoteListItemsByTag(_ tag: String) async throws -> [NoteListItem]
    func tombstoneNote(id: UUID, at date: Date) async throws
}

public protocol CalendarBindingStore: Sendable {
    func upsertBinding(_ binding: CalendarBinding) async throws
    func fetchBinding(entityType: CalendarBindingEntityType, entityID: UUID, calendarID: String) async throws -> CalendarBinding?
    func fetchBinding(taskID: UUID, calendarID: String) async throws -> CalendarBinding?
    func fetchBinding(eventIdentifier: String, calendarID: String) async throws -> CalendarBinding?
    func fetchBinding(externalIdentifier: String, calendarID: String) async throws -> CalendarBinding?
    func tombstoneBinding(entityType: CalendarBindingEntityType, entityID: UUID, calendarID: String, at date: Date) async throws
    func tombstoneBinding(taskID: UUID, calendarID: String, at date: Date) async throws
}

public protocol SyncCheckpointStore: Sendable {
    func fetchCheckpoint(id: String) async throws -> SyncCheckpoint?
    func saveCheckpoint(_ checkpoint: SyncCheckpoint) async throws
}

public protocol CalendarProvider: Sendable {
    func upsertEvent(_ event: CalendarEvent) async throws -> CalendarEvent
    func deleteEvent(eventIdentifier: String, calendarID: String) async throws
    func fetchChanges(since token: String?, calendarID: String) async throws -> CalendarChangeBatch
}

public protocol TemplateStore: Sendable {
    func fetchTemplates() async throws -> [NoteTemplate]
    func upsertTemplate(_ template: NoteTemplate) async throws -> NoteTemplate
    func deleteTemplate(id: UUID) async throws
}
