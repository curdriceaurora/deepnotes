# Models

Core domain entities for notes, tasks, and calendar integration.

## Core Document Types

### Note

A markdown-formatted document with support for wiki-style linking and tagging.

**Key Features:**
- Markdown body with `[[wikilink]]` references
- Automatic `#tag` extraction
- Soft deletion (never hard-deleted; uses `deletedAt` timestamp)
- Optional calendar sync binding
- Versioning for incremental sync

**Usage:**
```swift
let note = Note(
    id: UUID(),
    title: "Meeting Notes",
    body: "Discussed [[Project A]] with #project-planning team",
    tags: ["project-planning"],
    linkedNoteID: nil,
    createdAt: Date(),
    updatedAt: Date(),
    deletedAt: nil,
    calendarBinding: nil,
    noteVersion: 1
)
```

### Task

A work item with priority, due date, status, and optional calendar sync.

**Key Features:**
- Priority levels (0-5, where 0 is critical)
- Subtasks with independent completion
- Linked note for reference
- Calendar event binding (stableID prevents duplicate creation)
- Kanban column assignment and ordering
- Optional labels/tags

**Status Flow:**
1. **Backlog** — Not yet scheduled
2. **Next** — Ready to work on
3. **Doing** — In progress
4. **Waiting** — Blocked or awaiting feedback
5. **Done** — Completed

**Usage:**
```swift
let task = Task(
    id: UUID(),
    stableID: UUID(), // immutable, used for calendar sync
    title: "Implement feature",
    details: "Add support for [[Feature X]]",
    status: .next,
    priority: .high, // .critical, .high, .normal, .low, .veryLow, .minimum
    dueDate: Date().addingTimeInterval(86400 * 3), // 3 days
    subtasks: [],
    linkedNoteID: nil,
    labels: [],
    kanbanColumnID: nil,
    kanbanOrder: 0,
    createdAt: Date(),
    updatedAt: Date(),
    completedAt: nil,
    deletedAt: nil,
    calendarBinding: nil,
    taskVersion: 1
)
```

### Subtask

A child item of a task with completion tracking and auto-completion logic.

**Key Features:**
- Independent completion status
- Order field for display ordering
- Parent auto-completes when all subtasks marked done
- One-way logic (parent incomplete does not uncomplete child)

**Usage:**
```swift
var task = Task(...)
task.subtasks.append(Subtask(
    id: UUID(),
    title: "Design wireframes",
    isCompleted: false,
    order: 0
))
task.subtasks.append(Subtask(
    id: UUID(),
    title: "Implement UI",
    isCompleted: false,
    order: 1
))
// When both subtasks completed:
// task.toggleStatus() → automatically sets task status to .done
```

## Calendar Integration

### CalendarEvent

Represents an event in Apple Calendar with sync metadata.

**Key Features:**
- EventKit identifier and external identifier (handles drift)
- Title, description, and time
- Recurrence rule (ICS format)
- Exception handling for modified occurrences
- Conflict resolution metadata

### CalendarBinding

Links a task or note to a calendar event with versioning.

**Key Features:**
- `stableID` ensures one event per task (prevents duplicates on re-sync)
- Version tracking for incremental sync
- Timestamp for conflict resolution
- Sync provider context

### SyncCheckpoint

Tracks the cursor position in a sync operation for resumability.

**Key Features:**
- Monotonic version per table (task_version, note_version)
- Timestamp of last successful sync
- Resume support for interrupted syncs

## Customization and Organization

### NoteTemplate

User-defined starter content for note creation.

**Key Features:**
- Reusable body template
- Name uniqueness constraint
- Optional default tags

### TaskLabel

User-defined label for tasks with color coding.

**Key Features:**
- Name and hex color
- Optional emoji icon
- Used for swimlane grouping and filtering

### KanbanColumn

Customizable kanban board column (built-in or user-defined).

**Key Features:**
- Wraps TaskStatus (built-in columns) or custom column UUID
- Optional WIP limit
- Position ordering
- Color styling

## Search and Discovery

### GraphNode and GraphEdge

Represent connections between notes for graph visualization.

**Features:**
- Nodes: Note title and ID
- Edges: Directed, labeled (e.g., "wiki link", "mention")
- Used by graph view and backlink discovery
