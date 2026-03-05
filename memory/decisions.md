# Architectural Decisions

## Swift 6 Strict Concurrency (`-strict-concurrency=complete`)

**Decision**: Keep strict concurrency checking across all targets.

**Rationale**:
1. NotesStorage & NotesSync are actor-heavy (SQLiteStore, TwoWaySyncEngine, EventKitCalendarProvider)
2. Actor isolation violations caught by complete mode prevent real race conditions
3. 10K LOC is still manageable with strict checking
4. Investment already made in fixing all warnings
5. Strict-by-default is safer for concurrent access patterns

**Would only consider `targeted` on**: NotesDomain, NotesUI, test targets (lower concurrency usage).

---

## Tombstone Deletes (No Hard Deletes)

Records are soft-deleted via `deleted_at` timestamp. Hard deletes never happen. This prevents ghost re-creation when sync is delayed — a deleted task won't reappear from a stale calendar pull.

---

## Monotonic Version Cursors

Tables track `version` and `updated_at` per record. Sync queries only changed records since last pull using version cursors (`task_version`, `note_version`). Avoids full-table scans on every sync cycle.

---

## Cursor-Based Pagination (Not Offset)

Search results and note lists paginate in chunks of 50 using cursor-based pagination. Offset-based pagination degrades on large datasets because the DB must scan and skip rows. Cursor-based uses indexed `WHERE id > ?` for consistent performance.

---

## Stable IDs for Sync

Tasks use immutable `stableID` so edits/renames don't create duplicate calendar events. The `stableID` is set at creation and never changes, even if the task title or content is modified.

---

## `{ Date() }` Closure vs `Date.init` for Sendable

Swift 6's strict concurrency checker does not recognize `Date.init` as `@Sendable`. The closure wrapper `{ Date() }` is required to satisfy `@escaping @Sendable () -> Date` constraints. The heap allocation overhead is negligible (~microseconds per sync cycle). Trust the compiler over code review agent heuristics.

---

## SemVer + Deprecation Policy

- **MAJOR.MINOR.PATCH** versioning
- Breaking API changes only in major bumps
- Minimum deprecation period: 2 releases before removal
- Use `@available(*, deprecated, renamed:, message:)` annotation
- Document in CHANGELOG.md

---

## In-Memory Link Index

`LinkIndex` precomputes title→ID mappings and note→links edges for fast backlink/graph queries. Invalidated on any note mutation. Trade-off: memory usage vs. query speed for graph visualization and backlink resolution.

---

## Search Result Caching (LRU)

WorkspaceService caches search results with LRU eviction (max 8 entries). Cache is invalidated on any note/task mutation. Avoids redundant SQLite queries for repeated search terms during interactive typing.
