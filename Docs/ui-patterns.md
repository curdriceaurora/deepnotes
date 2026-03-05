# UI Patterns

## Architecture

### AppViewModel — Single Orchestration Point

`AppViewModel` is the sole `@MainActor`-isolated view model. All UI state flows through it:
- Note selection, editing, saving
- Task creation, filtering, status transitions
- Kanban board state (drag reorder, column transitions)
- Calendar sync execution and status reporting
- Search with debounce (300ms) and LRU caching
- Template management and daily note creation

**No other view models exist.** Views bind directly to `AppViewModel` properties.

### Views.swift — All SwiftUI Components

All views live in a single file for cohesion:
- `NotesEditorView` — markdown editor with wikilink support
- `TasksListView` — filtered task list with status toggles
- `KanbanBoardView` — drag-and-drop kanban with priority badges
- `SyncDashboardView` — sync status, diagnostics, manual trigger
- `GraphView` — force-directed knowledge graph visualization
- `KanbanCardDetailSheet` — modal for editing task details

### Theme.swift — Visual Constants

Centralized design tokens:
- `PriorityDisplay` enum: labels, colors, visibility per priority level (P0-P5, P5 hidden)
- `DueDateStyle`: color coding for overdue/today/upcoming
- Markdown formatting styles
- Spacing, corner radius, and layout constants

### MarkdownRenderer.swift

Converts markdown text to `AttributedString` for display in the editor. Uses `swift-markdown` for parsing.

## SwiftUI Patterns

### @MainActor Isolation

All views and `AppViewModel` are `@MainActor`-isolated (Swift 6 requirement). State mutations must happen on the main actor. Async operations use `Task { @MainActor in ... }` or are called from already-isolated contexts.

### Lazy Loading

Note bodies are lazy-loaded — the note list shows only titles/metadata. Full body content loads when a note is selected. This keeps list scrolling performant with large note counts.

### Optimistic UI

UI updates immediately on user actions (e.g., task status toggle), then persists to storage asynchronously. If persistence fails, the UI reverts.

### Pagination

Note lists use offset-based pagination (pages of 50) via `NoteListItemPage.offset` and `fetchNoteListItems(limit:offset:)`. The `.onAppear` modifier on the last visible item triggers loading the next page.

## Testing with ViewInspector

### What Works

- Structural assertions: verify views contain expected subviews
- State management: verify AppViewModel property changes
- Event handling: simulate taps, text input, selection
- View rendering: verify views don't crash during construction

### Known Limitations

ViewInspector's `find(viewWithAccessibilityIdentifier:)` works in many cases but can be unreliable in certain view hierarchies. See `memory/gotchas.md` for details on which patterns fail and workarounds.

### Test Setup

```swift
@MainActor
func makeTestAppViewModel() -> AppViewModel {
    // Uses WorkspaceServiceSpy — see Tests/NotesUITests/TestHelpers.swift
}
```

Test helpers are consolidated in `Tests/NotesUITests/TestHelpers.swift`:
- `makeTestAppViewModel()` — unified factory
- `waitUntil()` — async polling helper
- `flushAsyncActions()` — async flush

### Service Spies

`WorkspaceServiceSpy` and `MockWorkspaceService` conform to `WorkspaceServicing`. They record calls and return configurable responses, allowing UI tests to run without SQLite or EventKit.
