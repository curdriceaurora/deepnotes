# NotesEngine

A local-first Swift codebase for a single notes + tasks + kanban + calendar-sync app.

Current state as of March 1, 2026:

- Functional SwiftUI app target (`notes-app`) with tabs for Notes, Tasks, Kanban, and Calendar Sync
- Two-way sync engine with Apple Calendar provider (`EventKitCalendarProvider`)
- SQLite-backed persistence for notes/tasks/bindings/checkpoints
- Working test suite covering persistence, sync logic, feature logic, and UI interactions

## Why this architecture

1. Local-first storage for speed
- SQLite + WAL mode keeps note/task editing responsive and deterministic.
- Sync can fail/retry without blocking writing.

2. Stable IDs for two-way sync
- Tasks use immutable `stableID` so edits/renames do not create duplicate calendar events.

3. Tombstones for reliable deletes
- `deletedAt` is stored instead of hard-deleting records, preventing ghost re-creation during delayed sync.

4. Separation of concerns
- `NotesDomain`: pure models/protocols
- `NotesStorage`: SQLite actor
- `NotesSync`: two-way sync + provider adapters
- `NotesFeatures`: business workflows (filters, backlinks, status transitions)
- `NotesUI`: SwiftUI screens + app view model
- `NotesApp`: app entrypoint and live wiring

## Feature parity mapping

- Apple Notes speed: local-first notes/tasks writes via SQLite actor
- Obsidian writing/linking: Markdown notes + `[[wikilinks]]` + backlink resolution
- Notion kanban: status-column board with move-left/move-right controls
- TickTick tasks: filters (`All`, `Today`, `Upcoming`, `Overdue`, `Completed`) + completion workflow
- Apple Calendar two-way sync: task/event binding map + conflict policy + tombstones

## Run

### Run tests

```bash
swift test
```

### Run coverage gates (minimum project quality bar)

```bash
./Scripts/run-coverage-gates.sh
```

This command runs test coverage and enforces these minimums:

- Functional coverage: `>= 90%`
- Integration coverage: `>= 99%`
- Error description assertion coverage: `>= 99%`
- UI interaction coverage: `>= 95%` (interaction orchestration in `Sources/NotesUI/AppViewModel.swift`)
- UI view-layer coverage: `>= 85%` (`Sources/NotesUI/Views.swift`)

### Run performance gates (release, with ProMotion rendering gate)

```bash
./Scripts/run-perf-gates.sh
```

This command runs the release perf harness and enforces:

- Launch-to-interactive p95 gate at `<= 900ms`
- Open-note p95 gate at `<= 40ms`
- Save-note-edit p95 gate at `<= 30ms`
- Wiki-link/backlinks refresh p95 gate at `<= 50ms`
- Kanban render p95 frame-time gate at `<= 8.333ms` (120Hz budget)
- Kanban p95 FPS gate at `>= 120`
- Kanban drag reorder commit p95 gate at `<= 50ms`
- Create-note p95 gate at `<= 30ms`
- Search-at-50k-notes p95 gate at `<= 80ms`
- Regression rule: measured p95 values must remain within `+10%` of the baseline in [Docs/perf-baseline.env](/Users/rahul/Projects/notes-placeholder/Docs/perf-baseline.env)

### Build app target

```bash
swift build --product notes-app
```

### Launch app

```bash
swift run notes-app
```

### CLI utilities

```bash
swift run notes-cli seed --db ./data/notes.sqlite
swift run notes-cli list-calendars
swift run notes-cli sync-eventkit --db ./data/notes.sqlite --calendar <calendar-id>
```

## Test suite

- Storage tests: [Tests/NotesStorageTests/SQLiteStoreTests.swift](/Users/rahul/Projects/notes-placeholder/Tests/NotesStorageTests/SQLiteStoreTests.swift)
  - note/task upsert, dedupe by stable ID, tombstones, includeDeleted behavior
- Sync tests: [Tests/NotesSyncTests/TwoWaySyncEngineTests.swift](/Users/rahul/Projects/notes-placeholder/Tests/NotesSyncTests/TwoWaySyncEngineTests.swift)
  - push/import/delete round-trip behavior
- Feature tests: [Tests/NotesFeaturesTests/WorkspaceServiceTests.swift](/Users/rahul/Projects/notes-placeholder/Tests/NotesFeaturesTests/WorkspaceServiceTests.swift)
  - wikilink parsing, backlinks, filters, status transitions, seeding behavior
- UI tests: [Tests/NotesUITests/NotesViewsTests.swift](/Users/rahul/Projects/notes-placeholder/Tests/NotesUITests/NotesViewsTests.swift)
  - user interactions (tap/select/move/sync states) via ViewInspector

Coverage gate scripts:

- [Scripts/coverage-gates.sh](/Users/rahul/Projects/notes-placeholder/Scripts/coverage-gates.sh)
- [Scripts/run-coverage-gates.sh](/Users/rahul/Projects/notes-placeholder/Scripts/run-coverage-gates.sh)
- [Scripts/perf-gates.sh](/Users/rahul/Projects/notes-placeholder/Scripts/perf-gates.sh)
- [Scripts/run-perf-gates.sh](/Users/rahul/Projects/notes-placeholder/Scripts/run-perf-gates.sh)
- CI workflow: [.github/workflows/coverage-gates.yml](/Users/rahul/Projects/notes-placeholder/.github/workflows/coverage-gates.yml)

Total passing tests: 157.

## Important gotchas

1. Calendar recurrence support
- RRULE persistence is implemented, but full exception editing parity with Calendar app still needs hardening.

2. EventKit identifiers
- `eventIdentifier` can change; binding stores both `eventIdentifier` and `externalIdentifier` to mitigate drift.

3. iOS packaging
- UI and features are cross-platform, but this repo currently ships as Swift Package targets.
- If you want TestFlight/App Store distribution, add an Xcode iOS app host target that links `NotesUI`.

## Next implementation tranche

The active delivery plan and acceptance checklist are tracked in:

- [Docs/DeliveryChecklist.md](/Users/rahul/Projects/notes-placeholder/Docs/DeliveryChecklist.md)
