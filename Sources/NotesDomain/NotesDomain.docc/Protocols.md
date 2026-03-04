# Protocols and Interfaces

Abstract contracts that define how domain models are persisted, queried, and synced.

## Overview

All persistence and external communication in `NotesDomain` is defined through protocols. This keeps the domain layer independent of implementation details and makes testing straightforward.

## Store Protocols

### NoteStore

Protocol for querying and mutating notes.

**Methods:**
- `allNotes() async throws -> [Note]` — Fetch all notes
- `note(withID:) async throws -> Note?` — Fetch a single note by ID
- `createNote(title:body:tags:linkedNoteID:) async throws -> Note` — Create a new note
- `updateNote(_:) async throws` — Update an existing note (title, body, tags, linked note)
- `deleteNote(withID:) async throws` — Soft-delete a note (sets deletedAt timestamp)
- `searchNotes(query:mode:) async throws -> [Note]` — Full-text search
- `notesByTag(_:) async throws -> [Note]` — Filter notes by tag
- `backlinks(for:) async throws -> [Note]` — Find notes that link to a given note
- `graphEdges(for:) async throws -> [GraphEdge]` — Get all connections for a note

**Conformers:**
- `SQLiteStore` (production)
- `InMemoryNoteStore` (testing)
- `MockNoteStore` (spies with call tracking)

### TaskStore

Protocol for task CRUD and filtering.

**Methods:**
- `allTasks() async throws -> [Task]` — Fetch all tasks
- `task(withID:) async throws -> Task?` — Fetch a single task
- `listTasks(filter:sortBy:) async throws -> [Task]` — Fetch with filtering and sorting
- `createTask(title:details:priority:dueDate:linkedNoteID:) async throws -> Task` — Create task
- `updateTask(_:) async throws` — Update task properties
- `setTaskStatus(_:to:) async throws` — Update only the status
- `setTaskPriority(_:to:) async throws` — Update only the priority
- `deleteTask(withID:) async throws` — Soft-delete task
- `bulkMoveTasksToStatus(_:to:) async throws` — Concurrently move multiple tasks

**Conformers:**
- `SQLiteStore` (production)
- `MockTaskStore` (testing)

### NoteTemplateStore

Protocol for template management.

**Methods:**
- `allTemplates() async throws -> [NoteTemplate]` — List all templates
- `createTemplate(name:body:) async throws -> NoteTemplate` — Create template
- `updateTemplate(_:) async throws` — Update template
- `deleteTemplate(withID:) async throws` — Delete template
- `templateContent(for:) async throws -> String` — Get template body for use on note creation

**Conformers:**
- `SQLiteStore` (production)
- `MockNoteTemplateStore` (testing)

## Calendar Provider

### CalendarProvider

Protocol for reading from and writing to calendar services.

**Methods:**
- `authorizationStatus() async -> EKAuthorizationStatus` — Check permission status
- `requestAccess() async throws` — Request user permission
- `allEvents() async throws -> [CalendarEvent]` — Fetch all events
- `createEvent(_:) async throws -> CalendarEvent` — Create new calendar event
- `updateEvent(_:) async throws` — Update event
- `deleteEvent(withID:) async throws` — Delete event
- `event(withID:) async throws -> CalendarEvent?` — Fetch single event
- `eventsModifiedSince(_:) async throws -> [CalendarEvent]` — Incremental query (for sync)

**Conformers:**
- `EventKitCalendarProvider` (production, uses Apple Calendar)
- `InMemoryCalendarProvider` (testing)
- `MockCalendarProvider` (spies with call tracking)

## Testing Interfaces

### WorkspaceServiceSpy

A test double for `WorkspaceService` that records all method calls for verification.

**Features:**
- Tracks method invocations with parameters and return values
- Allows assertion on "was method called with X?"
- Provides predefined mock implementations for all service methods

**Usage:**
```swift
let spy = WorkspaceServiceSpy()
spy.createNoteResult = Note(id: UUID(), title: "Test", ...)

await viewModel.createNote("Test")

XCTAssertTrue(spy.createNoteCalled)
XCTAssertEqual(spy.createNoteArguments?.title, "Test")
```

### MockWorkspaceService

A full mock implementation for isolated component testing.

**Features:**
- Conforms to all service protocols
- Returns predictable test data
- No side effects (in-memory only)
- Configurable to simulate different scenarios

**Usage:**
```swift
let mock = MockWorkspaceService()
mock.notes = [testNote1, testNote2]
mock.tasks = [testTask1, testTask2]

let viewModel = AppViewModel(workspace: mock)
// Test view model in isolation
```

## Protocol Design Patterns

### Fail-Fast with Typed Errors

```swift
// ✅ Protocol method signature with specific error types
protocol NoteStore {
    func note(withID: UUID) async throws(NoteError) -> Note?
}

// ❌ Avoid generic Error
protocol NoteStore {
    func note(withID: UUID) async throws -> Note?
}
```

### Async/Await Over Closures

```swift
// ✅ Modern async/await API
protocol TaskStore {
    func allTasks() async throws -> [Task]
}

// ❌ Avoid callback-based API
protocol TaskStore {
    func allTasks(completion: @escaping ([Task]?, Error?) -> Void)
}
```

### Actor-Based Isolation

All store implementations are actors to ensure thread-safe access:

```swift
actor SQLiteStore: NoteStore, TaskStore, NoteTemplateStore {
    // Compiler enforces that all properties are accessed serially
    // All methods must be async and properly isolated
}
```

## Integration Example

```swift
// Create stores
let storage = try await SQLiteStore(at: .applicationSupport)
let calendar = EventKitCalendarProvider()

// Create service with protocol-based dependencies
let workspace = WorkspaceService(
    noteStore: storage,
    taskStore: storage,
    templateStore: storage,
    calendarProvider: calendar
)

// Use service (all methods are async and return typed errors)
do {
    let notes = try await workspace.allNotes()
    let searchResults = try await workspace.search("keyword", mode: .smart)
} catch NoteError.notFound {
    print("Note not found")
}
```
