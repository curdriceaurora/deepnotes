# Persistence Layer

## SQLiteStore Actor

`NotesStorage.SQLiteStore` is an `actor` providing thread-safe database access. All calls must be `await`ed.

### WAL Mode

Write-Ahead Logging (WAL) is enabled for concurrent reads during writes. This allows the UI to query while a sync operation writes without blocking.

### Migrations

Migrations run automatically on first `.initialize()` call. The migration system bootstraps all tables and indexes on a fresh database.

### Tables

#### Notes
| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID | Primary key |
| `title` | TEXT | Case-insensitive unique |
| `body` | TEXT | Lazy-loaded in list views |
| `updated_at` | DATETIME | Timestamp for conflict resolution |
| `version` | INTEGER | Monotonic, incremented on each update |
| `deleted_at` | DATETIME | Tombstone (NULL = active) |

#### Tasks
| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID | Primary key |
| `note_id` | UUID | Foreign key → notes |
| `stable_id` | TEXT | Immutable sync identifier (unique) |
| `title` | TEXT | Display title |
| `status` | TEXT | todo/in_progress/done |
| `priority` | INTEGER | P0 (highest) to P5 (hidden) |
| `due_date` | DATETIME | Optional |
| `recurrence` | TEXT | Optional recurrence rule |
| `version` | INTEGER | Monotonic |
| `deleted_at` | DATETIME | Tombstone |

#### Calendar Bindings
| Column | Type | Notes |
|--------|------|-------|
| `task_id` | UUID | Composite PK with calendar_id |
| `calendar_id` | TEXT | Composite PK |
| `event_identifier` | TEXT | EventKit primary ID |
| `external_identifier` | TEXT | EventKit external ID (backup) |
| `sync_marker` | TEXT | Change tracking token |

#### Checkpoints
| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT | Checkpoint identifier |
| `task_version` | INTEGER | Last-synced task version cursor |
| `note_version` | INTEGER | Last-synced note version cursor |
| `calendar_token` | TEXT | EventKit change token |

#### Templates
| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID | Primary key |
| `name` | TEXT | Unique template name |
| `body` | TEXT | Template content |

## Key Patterns

### Tombstone Semantics

- Records are never hard-deleted
- `deleted_at IS NOT NULL` marks a record as deleted
- Queries filter with `WHERE deleted_at IS NULL` by default
- Tombstones are preserved indefinitely for sync reliability

### Monotonic Versioning

- Each record has a `version` field, incremented on every update
- Sync checkpoints store the last-seen version
- Delta queries: `WHERE version > :last_seen_version`
- Avoids full-table scans on sync cycles

### Lazy Loading

- Note list queries return `id`, `title`, `updated_at` only (no `body`)
- Full body loaded on demand when user selects a note
- Pagination uses cursor-based `WHERE id > :cursor LIMIT 50`

## Testing

Mirror test target: `NotesStorageTests`
- Table correctness (CRUD operations)
- Version/tombstone semantics
- Migration bootstrap
- Concurrent access patterns
