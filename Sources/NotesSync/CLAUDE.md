# NotesSync

Two-way calendar synchronization engine.

## Key Files

- **TwoWaySyncEngine.swift** — `Sendable` final class orchestrating pull → push → resolve → persist
- **TaskCalendarMapper.swift** — Task ↔ calendar event bidirectional mapping
- **NoteCalendarMapper.swift** — Note ↔ calendar event mapping
- **EventKitCalendarProvider.swift** — Live EventKit implementation
- **InMemoryCalendarProvider.swift** — In-memory test double

## Rules

- `TwoWaySyncEngine` is a **Sendable final class** with immutable properties
- Conflict resolution must be **deterministic** — same inputs + policy = same output
- Always use `stableID` (immutable) for sync bindings, never display title
- Store both `eventIdentifier` and `externalIdentifier` (EventKit IDs can drift)
- Sync errors must include structured diagnostics (operation, IDs, provider error, timestamp)
- Use `{ Date() }` closure form for `@Sendable` date providers, not `Date.init`

## Dependencies

**Allowed imports**: Foundation, NotesDomain, NotesStorage
**Forbidden**: NotesFeatures, NotesUI, NotesApp

## Details

See `Docs/sync.md` for the full sync algorithm, conflict policies, and performance budgets.

## Testing

Mirror target: `NotesSyncTests` — push/import/delete round-trips, conflict resolution, deterministic behavior.
