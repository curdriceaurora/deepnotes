# NotesUI

SwiftUI views and app state management.

## Key Files

- **AppViewModel.swift** — `@MainActor` orchestration: note/task selection, filters, sync status, search, templates, kanban state
- **Views.swift** — All SwiftUI views: editor, tasks list, kanban board, sync dashboard, graph, card detail sheet
- **Theme.swift** — `PriorityDisplay`, `DueDateStyle`, colors, spacing, markdown formatting
- **MarkdownRenderer.swift** — Markdown → AttributedString conversion

## Rules

- All views and `AppViewModel` are **`@MainActor`-isolated** (Swift 6 requirement)
- `AppViewModel` is the **single view model** — no other view models exist
- Views bind directly to `AppViewModel` properties
- Optimistic UI: update state immediately, persist async, revert on failure
- Lazy-load note bodies — list shows titles only, body loads on selection
- Pagination triggers on `.onAppear` of last visible item

## ViewInspector Limitations

ViewInspector **cannot** find views by accessibility identifier. All identifier tests use `XCTSkip()`. See `memory/gotchas.md`.

## Dependencies

**Allowed imports**: Foundation, SwiftUI, NotesDomain, NotesFeatures
**Forbidden**: NotesStorage, NotesSync, NotesApp (UI must not depend on persistence/sync directly)

## Details

See `Docs/ui-patterns.md` for SwiftUI patterns, test setup, and service spies.

## Testing

Mirror target: `NotesUITests` — ViewInspector interaction tests, structural assertions, AppViewModel state management.

Coverage minimums:
- AppViewModel: ≥ 95%
- Views.swift: ≥ 85%
