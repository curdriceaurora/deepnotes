# Project Map

## Repository Structure

```
notes-placeholder/
├── CLAUDE.md                          # Root instructions (concise, pointers to docs)
├── Package.swift                      # Swift 6.2, macOS 26.0 / iOS 26.0
├── Sources/
│   ├── NotesDomain/                   # Pure models, protocols, errors
│   │   ├── Models.swift               # Note, Task, Subtask, CalendarBinding, SyncCheckpoint, NoteTemplate
│   │   ├── Protocols.swift            # NoteStore, TaskStore, CalendarProvider, TemplateStore
│   │   ├── Errors.swift               # NoteError, TaskError, SyncError, etc.
│   │   └── NotesDomain.docc/          # DocC documentation
│   ├── NotesStorage/                  # SQLite persistence layer
│   │   └── SQLiteStore.swift          # Actor-isolated SQLite with WAL, migrations, tombstones
│   ├── NotesSync/                     # Two-way calendar sync
│   │   ├── TwoWaySyncEngine.swift     # Pull → push → resolve → persist orchestrator
│   │   ├── TaskCalendarMapper.swift   # Task ↔ calendar event mapping
│   │   ├── NoteCalendarMapper.swift   # Note ↔ calendar event mapping
│   │   ├── EventKitCalendarProvider.swift  # Live EventKit implementation
│   │   └── InMemoryCalendarProvider.swift  # Test double
│   ├── NotesFeatures/                 # Business logic layer
│   │   ├── WorkspaceService.swift     # Main orchestrator (notes, tasks, search, templates)
│   │   ├── WikiLinkParser.swift       # [[wikilink]] extraction and validation
│   │   ├── TagParser.swift            # Tag extraction from note content
│   │   ├── FuzzyMatcher.swift         # Fuzzy search matching
│   │   └── NotificationScheduler.swift # Due date notifications
│   ├── NotesUI/                       # SwiftUI components
│   │   ├── AppViewModel.swift         # Single orchestration point for all UI state
│   │   ├── Views.swift                # All SwiftUI views (editor, tasks, kanban, sync, graph)
│   │   ├── Theme.swift                # Colors, priority display, date styles, markdown formatting
│   │   └── MarkdownRenderer.swift     # Markdown → AttributedString rendering
│   ├── NotesApp/                      # App entry point
│   │   └── NotesApplication.swift     # Live wiring: SQLiteStore + EventKit + WorkspaceService
│   ├── NotesCLI/                      # CLI tool
│   │   └── NotesCLI.swift             # Seed database, manage notes from terminal
│   └── NotesPerfHarness/              # Performance benchmarks
│       └── NotesPerfHarness.swift     # 50k+ seed load, latency measurements
├── Tests/
│   ├── NotesDomainTests/              # Model validation, error handling
│   ├── NotesStorageTests/             # SQLite correctness, versions, tombstones, migrations
│   ├── NotesSyncTests/                # Push/import/delete round-trips, conflict resolution
│   ├── NotesFeaturesTests/            # Workflow rules, filters, backlinks, status transitions
│   └── NotesUITests/                  # ViewInspector interaction + structural tests
├── Scripts/
│   ├── run-coverage-gates.sh          # Test coverage minimums enforcement
│   ├── run-perf-gates.sh              # Performance budget enforcement
│   ├── run-lint.sh                    # SwiftLint + SwiftFormat + Periphery
│   ├── run-format.sh                  # Apply SwiftFormat
│   └── install-git-hooks.sh           # Pre-commit hook setup
├── Docs/                              # Detailed documentation
│   ├── Architecture.md                # Layered architecture, persistence model, sync algorithm
│   ├── CONCURRENCY_ARCHITECTURE.md    # Swift 6 concurrency compliance
│   ├── project-map.md                 # This file — repo structure reference
│   ├── persistence.md                 # SQLite actor, WAL, migrations, tombstones
│   ├── sync.md                        # TwoWaySyncEngine, conflict policies, EventKit
│   ├── ui-patterns.md                 # SwiftUI patterns, Theme, ViewInspector
│   ├── testing.md                     # Test strategy, coverage gates, validation protocol
│   ├── debugging.md                   # Performance profiling, os_signpost, perf harness
│   ├── LINTING.md                     # SwiftLint + SwiftFormat configuration
│   ├── ACCESSIBILITY_TESTING.md       # Accessibility test approach
│   ├── API_DOCUMENTATION.md           # Public API documentation
│   ├── perf-baseline.env              # Baseline performance values
│   ├── ReleaseRunbook.md              # Release process
│   ├── ReleaseRunbook-v2.md           # Updated release process
│   ├── SmokeChecklist.md              # Pre-release smoke tests
│   └── DeliveryChecklist.md           # Phase delivery tracking
├── memory/                            # Historical context for Claude Code
│   ├── decisions.md                   # Architectural decisions and rationale
│   ├── gotchas.md                     # Known technical pitfalls
│   ├── bugs.md                        # Previously fixed bugs
│   └── refactors.md                   # Completed refactor summaries
└── .github/workflows/
    ├── coverage-gates.yml             # CI: coverage + lint on PR/push
    └── copilot-review.yml             # CI: auto-request Copilot review
```

## Target Dependency Graph

```
NotesDomain  (models & protocols — no dependencies)
    ↓
NotesStorage (SQLite persistence — depends on NotesDomain)
    ↓
NotesSync    (calendar sync — depends on NotesDomain, NotesStorage)
    ↓
NotesFeatures (business logic — depends on NotesDomain, NotesStorage, NotesSync)
    ↓
NotesUI      (SwiftUI views — depends on NotesDomain, NotesFeatures)
    ↓
NotesApp     (entry point — depends on all above)
```

**Rule**: Dependencies flow downward only. No module may import a module above it in this graph.

## Key Entry Points

| Task | Start Here |
|------|-----------|
| Add a new model/entity | `Sources/NotesDomain/Models.swift` |
| Add/modify storage schema | `Sources/NotesStorage/SQLiteStore.swift` |
| Add sync behavior | `Sources/NotesSync/TwoWaySyncEngine.swift` |
| Add business logic | `Sources/NotesFeatures/WorkspaceService.swift` |
| Add/modify UI | `Sources/NotesUI/Views.swift` + `AppViewModel.swift` |
| Add performance benchmark | `Sources/NotesPerfHarness/NotesPerfHarness.swift` |

## Typical Task Workflow

1. Add model to `NotesDomain/Models.swift` if needed
2. Update `NotesStorage/SQLiteStore.swift` table schema + CRUD
3. Update `NotesFeatures/WorkspaceService.swift` protocol/implementation if new workflow
4. Add UI in `NotesUI/Views.swift` and bind to `AppViewModel`
5. Add tests to corresponding test target
6. Verify gates: `./Scripts/run-coverage-gates.sh && ./Scripts/run-perf-gates.sh`
