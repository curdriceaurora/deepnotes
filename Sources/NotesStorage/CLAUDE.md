# NotesStorage

SQLite persistence layer. Actor-isolated for thread safety.

## Key Files

- **SQLiteStore.swift** — `actor SQLiteStore` with WAL mode, migration bootstrap, all CRUD operations, tombstone support, version cursors

## Rules

- `SQLiteStore` is an **actor** — all access must be `await`ed
- WAL mode is enabled for concurrent reads during writes
- Migrations run on first `.initialize()` call — never skip
- Records are **soft-deleted** via `deleted_at` timestamp (no hard deletes)
- Every mutation increments the record's `version` field (monotonic versioning)
- Lazy-load note bodies — list queries return only `id`, `title`, `updated_at`
- Pagination is cursor-based (`WHERE id > ? LIMIT 50`), never offset-based

## Dependencies

**Allowed imports**: Foundation, NotesDomain
**Forbidden**: NotesSync, NotesFeatures, NotesUI, NotesApp

## Details

See `Docs/persistence.md` for table schemas, tombstone semantics, and versioning details.

## Testing

Mirror target: `NotesStorageTests` — table correctness, version/tombstone semantics, migration bootstrap, concurrent access.
