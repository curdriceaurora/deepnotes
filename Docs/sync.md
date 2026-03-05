# Sync Architecture

## Overview

The sync layer provides two-way synchronization between the local SQLite store and external calendar providers (EventKit). It's designed for a local-first app where the local store is the source of truth.

## TwoWaySyncEngine

`TwoWaySyncEngine` is a `Sendable` final class with immutable properties. It orchestrates the sync cycle:

### Sync Cycle (`runOnce`)

1. **Pull local delta**: Query tasks changed since last sync checkpoint (using monotonic version cursors)
2. **Push to calendar**: Upsert new/modified tasks as calendar events, delete tombstoned tasks
3. **Pull calendar changes**: Fetch events modified since last sync token
4. **Resolve conflicts**: Apply configured conflict policy
5. **Persist**: Save updated records and new checkpoint

### Conflict Policies

Three built-in policies:
- **`lastWriteWins`**: Most recent `updated_at` timestamp wins
- **`taskPriority`**: Local task data always wins over calendar changes
- **`calendarPriority`**: Calendar event data always wins over local changes

Conflict resolution is deterministic — given the same inputs and policy, the output is always identical. Timestamp normalization ensures consistent comparison across time zones.

## Calendar Providers

### EventKitCalendarProvider (Live)

Wraps Apple's EventKit framework. Handles:
- Reading/writing calendar events
- Incremental change tracking via EventKit tokens
- Both `eventIdentifier` and `externalIdentifier` storage (identifiers can drift)

### InMemoryCalendarProvider (Tests)

In-memory implementation for unit testing. Supports all CalendarProvider protocol methods without touching the file system or requiring calendar permissions.

## Mappers

### TaskCalendarMapper

Converts between `Task` models and calendar event representations:
- Task title → event title
- Task due date → event start/end
- Task priority → event metadata
- Task status → event availability

### NoteCalendarMapper

Similar mapping for note-level calendar bindings.

## Key Design Decisions

### Stable IDs

Tasks use immutable `stableID` for sync binding. This ensures edits/renames don't create duplicate calendar events. The binding table uses `stableID` as the lookup key, not the task's display title.

### Tombstone Deletes

Deleted tasks retain a `deleted_at` timestamp rather than being hard-deleted. When sync runs, it sees the tombstone and deletes the corresponding calendar event. Without tombstones, a delayed sync pull could re-import a deleted task from the calendar.

### Version Cursors

Each sync checkpoint stores the last-seen `task_version` and `note_version`. The next sync cycle queries `WHERE version > ?` to get only changed records. This avoids scanning the entire table on each sync.

### Sync Failure Diagnostics

Sync errors include structured diagnostics: operation type, affected IDs, provider error message, and timestamp. The UI displays these via `SyncDashboardView` (see the `syncDiagnosticsSection`).

## Performance Budgets

- Sync push (500 tasks): ≤ 200ms
- Sync pull (500 events): ≤ 200ms
- Sync round-trip (mixed ops): ≤ 300ms
- Sync conflict resolution: ≤ 250ms
