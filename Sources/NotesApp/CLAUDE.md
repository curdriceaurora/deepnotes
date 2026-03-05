# NotesApp

App entry point and live dependency wiring.

## Key Files

- **NotesApplication.swift** — Instantiates `SQLiteStore`, `EventKitCalendarProvider`, `WorkspaceService`, and wires them into the SwiftUI app

## Rules

- This is the **composition root** — all live dependencies are created here
- Tab-based navigation: Notes, Tasks, Kanban, Calendar Sync, Graph
- No business logic belongs here — delegate to `WorkspaceService` and `AppViewModel`
- Keep this file minimal — it should only wire dependencies and define the app structure

## Dependencies

**Allowed imports**: All modules (this is the top of the dependency graph)

## Testing

No dedicated test target — tested indirectly through integration tests and smoke checklist (`Docs/SmokeChecklist.md`).
