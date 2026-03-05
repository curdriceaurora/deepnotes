# NotesFeatures

Business logic layer — workflows, search, parsing, notifications.

## Key Files

- **WorkspaceService.swift** — Main orchestrator: note/task CRUD, search, templates, backlinks, graph edges, pagination, daily notes, unlinked mentions
- **WikiLinkParser.swift** — `[[wikilink]]` extraction and validation (case-insensitive, space-tolerant)
- **TagParser.swift** — Tag extraction from note content
- **FuzzyMatcher.swift** — Fuzzy search matching algorithm
- **NotificationScheduler.swift** — Due date notification scheduling

## Rules

- `WorkspaceService` defines the protocol that UI depends on — changes here affect `AppViewModel`
- Search uses 300ms debounce + LRU cache (max 8 entries, invalidated on mutations)
- Task filtering: `All`, `Today`, `Upcoming`, `Overdue`, `Completed`
- Subtask auto-completion: when parent task status changes, update subtasks accordingly
- `LinkIndex` precomputes title→ID and note→links for fast backlink/graph queries
- Backlinks auto-populate; updating a wikilink updates all backlinks

## Dependencies

**Allowed imports**: Foundation, NotesDomain, NotesStorage, NotesSync
**Forbidden**: NotesUI, NotesApp

## Testing

Mirror target: `NotesFeaturesTests` — workflow rules, filters, backlinks, status transitions, wikilink parsing.
