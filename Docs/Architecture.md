# Architecture

## Layers

1. `NotesDomain`
- Entities (`Note`, `Task`, `CalendarBinding`, `SyncCheckpoint`)
- Protocols (`TaskStore`, `NoteStore`, `CalendarProvider`, etc.)
- Validation and typed errors

2. `NotesStorage`
- `SQLiteStore` actor
- Schema + migration bootstrap
- Monotonic version cursors (`task_version`, `note_version`)
- Tombstone persistence

3. `NotesSync`
- `TaskCalendarMapper`
- `TwoWaySyncEngine`
- `EventKitCalendarProvider` (live)
- `InMemoryCalendarProvider` (tests)

4. `NotesFeatures`
- `WorkspaceService` (task/note workflows)
- `WikiLinkParser`
- Task filtering and backlink resolution

5. `NotesUI`
- `AppViewModel`
- SwiftUI screens:
  - `NotesEditorView`
  - `TasksListView`
  - `KanbanBoardView`
  - `SyncDashboardView`

6. `NotesApp`
- App entrypoint wiring storage, service, and calendar provider

## Persistence model

### Notes table
- `id`, `title` (case-insensitive unique), `body`, `updated_at`, `version`, `deleted_at`

### Tasks table
- `id`, `note_id`, `stable_id` (unique), scheduling fields, status, recurrence, version, tombstone

### Calendar bindings
- `task_id + calendar_id` composite key
- stores event/external IDs + sync markers

### Checkpoints
- cursor state for incremental sync loops

## Sync algorithm

`TwoWaySyncEngine.runOnce`:

1. Pull local task delta by task version cursor
2. Push upserts/deletes to calendar
3. Pull calendar changes since token
4. Resolve conflicts using configured policy
5. Persist updated checkpoint

Conflict policies:
- `lastWriteWins`
- `taskPriority`
- `calendarPriority`

## UI model

`AppViewModel` is the single orchestration point for tabs:
- Note selection/edit/save
- quick task creation from note context
- task filter application
- kanban state transitions
- calendar sync execution and status reporting

## Test strategy

- Storage: table correctness + version/tombstone semantics
- Sync: round-trip behavior across upsert/import/delete paths
- Features: workflow-level rules (filters, backlinks, status transitions)
- UI: structural assertions and key control presence via ViewInspector

## Known limitations

1. Recurrence exception handling is not fully complete.
2. EventKit incremental deltas are approximated by provider-level change tracking.
3. Packaging for App Store/TestFlight requires adding native Xcode app hosts, while shared modules are already ready.
