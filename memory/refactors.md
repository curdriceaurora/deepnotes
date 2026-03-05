# Completed Refactors

## Accessibility Test Refactoring (PR #22/#25, 2026-03-04)

Restructured accessibility tests into MECE tiers:
- **Tier A**: Consolidated identifiers across all views
- **Tier B**: Created semantic attribute tests (labels, hints)
- **Tier C**: Verification pass

Converted affected ViewInspector identifier tests to `XCTSkip()` where lookups fail due to framework limitation (see `memory/gotchas.md`).

---

## Search & Pagination Polish (Section 7)

1. **Offset-based pagination**: `NoteListItemPage` with paginated SQLite, `.onAppear` trigger, pages of 50
2. **Search result caching**: LRU cache (max 8) in WorkspaceService, invalidated on mutations
3. **In-memory backlinks index**: `LinkIndex` precomputes title→ID + note→links
4. **Launch profiling**: `os_signpost`, parallelized `load()` with `async let`, budget 900→200ms

---

## Obsidian Polish Tier (2026-03-04)

Four features implemented:
1. **Unlinked Mentions** — detects plain-text references and links them
2. **Graph View** — interactive force-directed knowledge graph
3. **Daily Notes** — date-indexed note creation
4. **Note Templates** — reusable templates with CRUD + migration

---

## Kanban Board Foundation (Section 9)

1. Priority badges + tag chips on kanban cards (`PriorityDisplay` enum in Theme.swift)
2. Card detail modal (`KanbanCardDetailSheet`)
3. Due-date color coding (`DueDateStyle`)
4. Priority in creation/edit flows (`quickTaskPriority` binding)

---

## Test Helper Consolidation (2026-03-04)

Created `Tests/NotesUITests/TestHelpers.swift`:
- `@MainActor makeTestAppViewModel()` — unified factory (was duplicated 3x)
- `@MainActor waitUntil()` — polling helper (was duplicated)
- `flushAsyncActions()` — async flush helper (was duplicated)
- Reduced duplication by 60+ lines

---

## Sync Cycle Benchmarks (PR #36)

Added performance harness benchmarks for sync operations:
- Sync push (500 tasks)
- Sync pull (500 events)
- Sync round-trip (mixed ops)
- Sync conflict resolution
