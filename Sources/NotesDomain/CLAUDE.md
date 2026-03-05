# NotesDomain

Pure domain models, protocols, and error types. Zero external dependencies.

## Key Files

- **Models.swift** — All entity types: `Note`, `Task`, `Subtask`, `CalendarBinding`, `SyncCheckpoint`, `NoteTemplate`, `GraphNode`, `GraphEdge`, `NoteListItemPage`
- **Protocols.swift** — Store protocols: `NoteStore`, `TaskStore`, `CalendarProvider`, `TemplateStore` (all require `Sendable`)
- **Errors.swift** — Typed error enums: `NoteError`, `TaskError`, `SyncError`, etc.

## Rules

- All models are **structs with value semantics** (automatically `Sendable` under Swift 6)
- No `import Foundation` beyond what's needed for `UUID`, `Date`, `Codable`
- No dependencies on any other module — this is the bottom of the dependency graph
- Error types must have descriptive `description` properties (coverage gate: ≥ 99%)
- New models should conform to `Identifiable`, `Hashable`, `Codable` where appropriate

## Dependencies

**Allowed imports**: Foundation, swift-markdown (for markdown types only)
**Forbidden**: NotesStorage, NotesSync, NotesFeatures, NotesUI, NotesApp

## Testing

Mirror target: `NotesDomainTests` — model validation, error handling, protocol conformance.
