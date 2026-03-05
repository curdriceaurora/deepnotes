# Debugging & Performance Profiling

## Performance Budgets (p95)

| Operation | Budget |
|-----------|--------|
| Launch-to-interactive | ≤ 900ms |
| Open note | ≤ 40ms |
| Save note edit | ≤ 30ms |
| Kanban render | ≤ 8.333ms (120Hz) |
| Kanban drag reorder | ≤ 50ms |
| Create note | ≤ 30ms |
| Search at 50k notes | ≤ 80ms |
| Sync push (500 tasks) | ≤ 200ms |
| Sync pull (500 events) | ≤ 200ms |
| Sync round-trip (mixed) | ≤ 300ms |
| Sync conflict resolution | ≤ 250ms |

Baseline values: `Docs/perf-baseline.env`

## Performance Gates

```bash
# Run in release mode
./Scripts/run-perf-gates.sh
```

Gates run automatically on every push via CI. They build in release mode and measure against the budgets above.

## Performance Harness

`Sources/NotesPerfHarness/NotesPerfHarness.swift` — standalone benchmark tool.

```bash
swift build --product notes-perf-harness -c release
./.build/release/notes-perf-harness
```

Loads 50k+ seed records and measures latencies for all critical operations. Results compared against `perf-baseline.env`.

## Launch Profiling

Uses `os_signpost` markers integrated with Xcode Instruments:
- Marks placed at key lifecycle points (init, load, first render)
- `load()` parallelized with `async let` for concurrent data fetching
- Target: 900ms budget (achieved ~200ms after optimization)

## Key Performance Patterns

### Cursor-Based Pagination
Note lists paginate in pages of 50 using `WHERE id > :cursor LIMIT 50`. Avoids offset scanning which degrades linearly with dataset size.

### Search Result Caching
LRU cache (max 8 entries) in WorkspaceService. Invalidated on any note/task mutation. Prevents redundant SQLite queries during interactive search typing.

### In-Memory Link Index
`LinkIndex` precomputes title→ID and note→links mappings. Invalidated on mutations. Avoids repeated full-table scans for backlink resolution and graph edge computation.

### Lazy Loading
Note bodies are loaded on demand. List views query only `id`, `title`, `updated_at`. Full body fetched when user selects a note.

### WAL Mode
SQLite WAL enables concurrent reads during writes. The UI can query while sync writes without blocking.

## Debugging Tips

### Build with Clean Output
```bash
swift build 2>&1 | xcbeautify
swift test 2>&1 | xcbeautify
```

### SQLite Debugging
The SQLite database is at `./data/notes.sqlite`. Use `sqlite3` CLI to inspect:
```bash
sqlite3 ./data/notes.sqlite ".schema"
sqlite3 ./data/notes.sqlite "SELECT count(*) FROM notes WHERE deleted_at IS NULL"
```

### Seed Test Data
```bash
swift run notes-cli seed --db ./data/notes.sqlite
```
