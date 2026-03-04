# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Quick Commands

### Building & Running

```bash
# Run all tests
swift test

# Run a single test target (e.g., NotesUI tests)
swift test NotesUITests

# Run a specific test (match test function name)
swift test --filter NotesUITests.AppViewModelTests.testDeleteNote

# Build app target
swift build --product notes-app

# Run app
swift run notes-app

# Run CLI
swift run notes-cli seed --db ./data/notes.sqlite

# Run performance harness (release mode)
swift build --product notes-perf-harness -c release
./.build/release/notes-perf-harness
```

### Quality Gates

```bash
# Run test coverage gates (minimum project quality bar)
./Scripts/run-coverage-gates.sh

# Run performance gates (release mode, ProMotion rendering)
./Scripts/run-perf-gates.sh
```

**Coverage minimums:**
- Functional: ≥ 90%
- Integration: ≥ 99%
- Error descriptions: ≥ 99%
- UI orchestration (AppViewModel): ≥ 95%
- View-layer (Views.swift): ≥ 85%

**Performance budgets (p95):**
- Launch-to-interactive: ≤ 900ms
- Open note: ≤ 40ms
- Save note edit: ≤ 30ms
- Kanban render: ≤ 8.333ms (120Hz budget)
- Kanban drag reorder: ≤ 50ms
- Create note: ≤ 30ms
- Search at 50k notes: ≤ 80ms

## Architecture Overview

This is a **local-first, multi-feature notes app** with a clean layered architecture:

### Target Dependencies (layered)
```
NotesDomain (models & protocols)
    ↓
NotesStorage (SQLite persistence)
    ↓
NotesSync (two-way calendar sync)
    ↓
NotesFeatures (business workflows)
    ↓
NotesUI (SwiftUI screens)
    ↓
NotesApp (entry point & wiring)
```

### Core Concepts

1. **NotesDomain**: Pure models and protocols
   - `Note`, `Task`, `Subtask`, `CalendarBinding`, `SyncCheckpoint`, `NoteTemplate`
   - Protocols: `NoteStore`, `TaskStore`, `CalendarProvider`
   - Errors: typed enums (`NoteError`, `TaskError`, etc.)

2. **NotesStorage**: SQLite actor managing persistence
   - WAL mode for responsiveness
   - Monotonic version cursors (`task_version`, `note_version`) for incremental sync
   - Tombstone records (`deleted_at` field) for reliable deletes
   - Migration bootstrap on first run

3. **NotesSync**: Two-way sync with calendar providers
   - `TwoWaySyncEngine` orchestrates pull → push → resolve conflicts → persist
   - `EventKitCalendarProvider` (live), `InMemoryCalendarProvider` (tests)
   - Conflict policies: `lastWriteWins`, `taskPriority`, `calendarPriority`
   - Deterministic resolution with timestamp normalization

4. **NotesFeatures**: Business logic layer
   - `WorkspaceService`: main orchestrator for note/task workflows
   - `WikiLinkParser`: `[[wikilink]]` extraction and validation
   - Task filtering: `All`, `Today`, `Upcoming`, `Overdue`, `Completed`
   - Backlink resolution and graph edge computation
   - Search with caching (LRU, max 8 results)
   - Subtask auto-completion on parent status change

5. **NotesUI**: SwiftUI components and app state
   - `AppViewModel`: single orchestration point (note/task selection, filters, sync status)
   - Screens: `NotesEditorView`, `TasksListView`, `KanbanBoardView`, `SyncDashboardView`, `GraphView`
   - Uses `ViewInspector` for UI testing
   - Theme: `Theme.swift` with priority colors, date styles, markdown formatting

6. **NotesApp**: App target with live wiring
   - Instantiates `SQLiteStore`, `EventKitCalendarProvider`, `WorkspaceService`
   - Tab-based navigation: Notes, Tasks, Kanban, Calendar Sync, Graph

### Key Design Patterns

**Stable IDs for sync**: Tasks use immutable `stableID` so edits/renames don't create duplicate calendar events.

**Tombstones for deletes**: Records are soft-deleted (store `deletedAt` timestamp). Hard deletes never happen. This prevents ghost re-creation if sync is delayed.

**Monotonic versioning**: Tables track `version` and `updated_at` per record. Sync uses cursors to query only changed records since last pull.

**Service spies for testing**: Test targets define `WorkspaceServiceSpy` and `MockWorkspaceService` that conform to protocols. Allows testing UI layers in isolation.

**Lazy loading & pagination**: Note bodies lazy-load; search results paginate in chunks of 50 (cursor-based, not offset-based).

**In-memory indexes**: `LinkIndex` precomputes title→ID mappings and note→links edges for fast backlink/graph queries. Invalidated on mutations.

## Test Strategy

Each test target mirrors a source layer:

- **NotesStorageTests**: SQLite table correctness, version/tombstone semantics, migration
- **NotesSyncTests**: Push/import/delete round-trip behavior, conflict resolution
- **NotesDomainTests**: Model validation, error handling
- **NotesFeaturesTests**: Workflow rules (filters, backlinks, status transitions)
- **NotesUITests**: ViewInspector-based interaction tests (tap, select, move) and structural assertions

Test suites are parallelized where possible. Use `swift test --filter <test-name>` to run single tests during development.

## Important Patterns

### SQLite Actor
- `NotesStorage.SQLiteStore` is an actor; always `await` calls
- WAL mode enabled for concurrent reads during writes
- Migrations run on first `.initialize()` call

### Async/Await
- Storage queries are async (actor)
- Sync pulls and pushes are async
- UI uses `@MainActor` for view state mutations
- Tests use `XCTestExpectation` or Swift's native async/await test support

### Error Handling
- Typed errors per module (e.g., `NoteError.notFound`, `TaskError.invalidPriority`)
- Sync failures include detailed diagnostics (operation, IDs, provider error, timestamp)
- UI shows errors via `SyncDiagnosticsView`

### Markdown & Links
- Notes support `[[wikilink]]` syntax (case-insensitive, space-tolerant)
- Backlinks auto-populate in sidebar; updating a wikilink updates all backlinks
- Unlinked mentions detect plain-text note titles and offer linking
- Graph view visualizes all edges (directed, force-directed layout)

### Performance Profiling
- Launch profiling: `os_signpost` markers with `Xcode Instruments` integration
- Perf harness: loads 50k+ seeds and measures latencies
- Cursor-based pagination avoids offset scanning on large lists
- Search results cached (LRU, invalidated on mutations)

## Code Organization

**Key files to understand first:**
- `Sources/NotesDomain/Models.swift` — all entity types and protocols
- `Sources/NotesFeatures/WorkspaceService.swift` — orchestrator interface
- `Sources/NotesUI/AppViewModel.swift` — UI state and interactions
- `Sources/NotesUI/Views.swift` — SwiftUI components (editor, tasks, kanban, etc.)
- `Scripts/run-coverage-gates.sh` — test gate thresholds

**Typical task workflow:**
1. Add model to `NotesDomain/Models.swift` if needed
2. Update `NotesStorage/SQLiteStore.swift` table schema + CRUD
3. Update `NotesFeatures/WorkspaceService.swift` protocol/implementation if new workflow
4. Add UI in `NotesUI/Views.swift` and bind to `AppViewModel`
5. Add tests to corresponding test target
6. Verify gates: `./Scripts/run-coverage-gates.sh && ./Scripts/run-perf-gates.sh`

## Configuration

- **Swift**: 6.2 (see `Package.swift`)
- **Platforms**: macOS 26.0, iOS 26.0
- **Main dependencies**: `swift-markdown` (parsing), `ViewInspector` (UI testing)
- **Test framework**: XCTest (native Swift testing)

## Release & CI

- PR/push triggers `.github/workflows/coverage-gates.yml`
- Coverage gates block merge (enforce minimums)
- Performance gates run in release mode on every push
- Baseline perf values: `Docs/perf-baseline.env`
- Release runbook: `Docs/ReleaseRunbook.md`
- Smoke checklist: `Docs/SmokeChecklist.md`

## Mandatory Validation Protocol

Before declaring ANY step complete or committing ANY code, follow this checklist:

1. **Build check**: Verify the project builds without errors
   - Swift: `swift build --product notes-app` should succeed

2. **Test suite**: Run the full test suite — all tests must pass
   - `swift test` (full suite)
   - `swift test <target>` (specific target during development)

3. **Coverage gates**: Verify minimum coverage thresholds are met
   - `./Scripts/run-coverage-gates.sh` must pass

4. **Performance gates**: Check performance budgets (if making performance-sensitive changes)
   - `./Scripts/run-perf-gates.sh` must pass

5. **Diff review**: Read your own `git diff --staged` before committing and check for:
   - Incomplete refactors or half-finished code
   - Removed code that shouldn't be removed
   - Hardcoded paths or debug prints
   - Missing test coverage for new logic
   - Code organization and readability

6. **Commit**: Only after steps 1-5 pass, commit with clear conventional commit format

### Anti-patterns to avoid:
- NEVER say "All done" or summarize completion mid-plan. Complete ALL steps first.
- NEVER skip the validation protocol and push untested code.
- NEVER start fixing stylistic or cosmetic feedback in a feature PR — file them as separate issues.
- NEVER include already-completed tasks in a new plan.
- If given a multi-step plan with N steps, complete and confirm ALL N steps before reporting completion.

### Multi-step plan discipline:
When given a numbered plan, you must:
1. Enumerate the steps before starting
2. Complete each step fully
3. After each step, state: "✓ Step N complete. Remaining: [list]"
4. Only after ALL steps are done, say the plan is complete

## Permissions

**Bash operations**: All bash commands within this project directory are pre-authorized and do not require user prompting. This includes:
- Building, testing, and running code
- File operations (read, write, delete)
- Git operations (commit, push, branch management)
- Script execution
- Any other shell operations within `/Users/rahul/Projects/notes-placeholder`

## API Stability & Deprecation

### Public API Changes

All public APIs must maintain backward compatibility within a major version. Never remove or significantly change public APIs without a deprecation period.

**Deprecation process:**

1. Mark the old API as deprecated:
   ```swift
   @available(*, deprecated, renamed: "newName", message: "Use newName() instead")
   public func oldName() { }
   ```

2. Document in `CHANGELOG.md` under "Deprecated" section

3. Minimum deprecation period: **2 releases** (e.g., v1.0 → v1.1 → v2.0)

4. Remove in next major version only

**Breaking changes** (API removals, signature changes) are only allowed in major version bumps. Document all breaking changes in CHANGELOG.md.

### Semantic Versioning

This project follows SemVer:
- **MAJOR.MINOR.PATCH** (e.g., v1.2.3)
- **MAJOR**: Breaking API changes only
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes

See `Package.swift` for current version.

## Known Limitations

1. Calendar recurrence exception editing not fully hardened
2. EventKit identifiers can drift; bindings store both `eventIdentifier` and `externalIdentifier`
3. iOS TestFlight/App Store distribution requires native Xcode app hosts (shared modules ready)
