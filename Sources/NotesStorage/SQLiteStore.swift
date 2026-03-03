import Foundation
import SQLite3
import NotesDomain

private struct SQLiteConnection: @unchecked Sendable {
    let raw: OpaquePointer
}

public actor SQLiteStore: TaskStore, NoteStore, CalendarBindingStore, SyncCheckpointStore, TemplateStore {
    private let connection: SQLiteConnection
    private var db: OpaquePointer { connection.raw }

    public init(databaseURL: URL) throws {
        var dbPointer: OpaquePointer?

        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(databaseURL.path, &dbPointer, flags, nil) != SQLITE_OK || dbPointer == nil {
            let reason = String(cString: sqlite3_errmsg(dbPointer))
            if dbPointer != nil {
                sqlite3_close(dbPointer)
            }
            throw StorageError.openDatabase(path: databaseURL.path, reason: reason)
        }

        let rawDB = dbPointer!

        do {
            try Self.executeOnConnection(rawDB, sql: "PRAGMA journal_mode=WAL;")
            try Self.executeOnConnection(rawDB, sql: "PRAGMA synchronous=NORMAL;")
            try Self.executeOnConnection(rawDB, sql: "PRAGMA foreign_keys=ON;")
            try Self.runMigrations(on: rawDB)
        } catch {
            sqlite3_close(rawDB)
            throw error
        }

        self.connection = SQLiteConnection(raw: rawDB)
    }

    deinit {
        sqlite3_close(connection.raw)
    }

    // MARK: - Notes

    public func upsertNote(_ note: Note) async throws -> Note {
        let normalizedTitle = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw StorageError.executeStatement(reason: "Note title cannot be empty")
        }
        let normalizedStableID = note.stableID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? UUID().uuidString.lowercased()
            : note.stableID

        try beginTransaction()
        do {
            let existingByStableID = try fetchNoteByStableIDInternal(normalizedStableID)
            let existingByTitle = try fetchNoteByTitleInternal(normalizedTitle)
            let resolvedID = existingByStableID?.id ?? existingByTitle?.id ?? note.id
            let version = try nextVersion(for: "note_version")
            let now = max(note.updatedAt, Date())

            let tagsJSON: String
            if let data = try? JSONEncoder().encode(note.tags), let str = String(data: data, encoding: .utf8) {
                tagsJSON = str
            } else {
                tagsJSON = "[]"
            }

            let sql = """
            INSERT INTO notes (
                id,
                stable_id,
                title,
                body,
                tags,
                date_start,
                date_end,
                is_all_day,
                recurrence_rule,
                calendar_sync_enabled,
                updated_at,
                version,
                deleted_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                stable_id = excluded.stable_id,
                title = excluded.title,
                body = excluded.body,
                tags = excluded.tags,
                date_start = excluded.date_start,
                date_end = excluded.date_end,
                is_all_day = excluded.is_all_day,
                recurrence_rule = excluded.recurrence_rule,
                calendar_sync_enabled = excluded.calendar_sync_enabled,
                updated_at = excluded.updated_at,
                version = excluded.version,
                deleted_at = excluded.deleted_at;
            """

            try withStatement(sql) { statement in
                bindText(UUIDString(from: resolvedID), to: 1, in: statement)
                bindText(normalizedStableID, to: 2, in: statement)
                bindText(normalizedTitle, to: 3, in: statement)
                bindText(note.body, to: 4, in: statement)
                bindText(tagsJSON, to: 5, in: statement)
                bindOptionalDate(note.dateStart, to: 6, in: statement)
                bindOptionalDate(note.dateEnd, to: 7, in: statement)
                bindInt(note.isAllDay ? 1 : 0, to: 8, in: statement)
                bindOptionalText(note.recurrenceRule, to: 9, in: statement)
                bindInt(note.calendarSyncEnabled ? 1 : 0, to: 10, in: statement)
                bindDate(now, to: 11, in: statement)
                bindInt64(version, to: 12, in: statement)
                bindOptionalDate(note.deletedAt, to: 13, in: statement)
                try stepDone(statement)
            }

            try syncNoteFTS(
                noteID: resolvedID,
                title: normalizedTitle,
                body: note.body,
                tags: note.tags,
                deletedAt: note.deletedAt
            )

            try commitTransaction()

            var persisted = note
            persisted.id = resolvedID
            persisted.stableID = normalizedStableID
            persisted.title = normalizedTitle
            persisted.updatedAt = now
            persisted.version = version
            return persisted
        } catch {
            try? rollbackTransaction()
            throw error
        }
    }

    public func fetchNote(id: UUID) async throws -> Note? {
        try fetchNoteInternal(id: id)
    }

    public func fetchNoteByStableID(_ stableID: String) async throws -> Note? {
        try fetchNoteByStableIDInternal(stableID)
    }

    public func fetchNoteByTitle(_ title: String) async throws -> Note? {
        try fetchNoteByTitleInternal(title)
    }

    public func fetchNotes(includeDeleted: Bool = false) async throws -> [Note] {
        let sql = includeDeleted
        ? """
          SELECT id, stable_id, title, body, tags, date_start, date_end, is_all_day, recurrence_rule,
                 calendar_sync_enabled, updated_at, version, deleted_at
          FROM notes
          ORDER BY updated_at DESC;
          """
        : """
          SELECT id, stable_id, title, body, tags, date_start, date_end, is_all_day, recurrence_rule,
                 calendar_sync_enabled, updated_at, version, deleted_at
          FROM notes
          WHERE deleted_at IS NULL
          ORDER BY updated_at DESC;
          """

        return try withStatement(sql) { statement in
            var notes: [Note] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                notes.append(try note(from: statement))
            }
            return notes
        }
    }

    public func fetchNotesByTag(_ tag: String) async throws -> [Note] {
        let sql = """
        SELECT id, stable_id, title, body, tags, date_start, date_end, is_all_day, recurrence_rule,
               calendar_sync_enabled, updated_at, version, deleted_at
        FROM notes
        WHERE deleted_at IS NULL
          AND EXISTS (SELECT 1 FROM json_each(notes.tags) WHERE json_each.value = ? COLLATE NOCASE)
        ORDER BY updated_at DESC;
        """

        return try withStatement(sql) { statement in
            bindText(tag.lowercased(), to: 1, in: statement)
            var notes: [Note] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                notes.append(try note(from: statement))
            }
            return notes
        }
    }

    public func searchNotes(query: String, limit: Int = 50) async throws -> [Note] {
        let page = try await searchNotes(
            query: query,
            mode: .smart,
            limit: limit,
            offset: 0
        )
        return page.hits.map(\.note)
    }

    public func searchNotes(
        query: String,
        mode: NoteSearchMode = .smart,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> NoteSearchPage {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLimit = max(1, limit)
        let normalizedOffset = max(0, offset)
        guard !trimmed.isEmpty else {
            let notes = try await fetchNotes(includeDeleted: false)
            let start = min(normalizedOffset, notes.count)
            let end = min(notes.count, start + normalizedLimit)
            let pageNotes = Array(notes[start..<end])
            return NoteSearchPage(
                query: trimmed,
                mode: mode,
                offset: normalizedOffset,
                limit: normalizedLimit,
                totalCount: notes.count,
                hits: pageNotes.map { NoteSearchHit(note: $0, snippet: nil, rank: 0) }
            )
        }
        guard let matchExpression = ftsMatchExpression(from: trimmed, mode: mode) else {
            return NoteSearchPage(
                query: trimmed,
                mode: mode,
                offset: normalizedOffset,
                limit: normalizedLimit,
                totalCount: 0,
                hits: []
            )
        }

        let sql = """
        SELECT n.id, n.stable_id, n.title, n.body, n.tags, n.date_start, n.date_end, n.is_all_day, n.recurrence_rule,
               n.calendar_sync_enabled, n.updated_at, n.version, n.deleted_at,
               snippet(notes_fts, 2, '<mark>', '</mark>', '…', 16),
               0.0
        FROM notes_fts
        JOIN notes n ON n.id = notes_fts.note_id
        WHERE notes_fts MATCH ? AND n.deleted_at IS NULL
        ORDER BY n.updated_at DESC
        LIMIT ? OFFSET ?;
        """

        let fetchLimit = normalizedLimit + 1
        let rawHits = try withStatement(sql) { statement in
            bindText(matchExpression, to: 1, in: statement)
            bindInt(Int32(fetchLimit), to: 2, in: statement)
            bindInt(Int32(normalizedOffset), to: 3, in: statement)

            var hits: [NoteSearchHit] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let matchedNote = try note(from: statement)
                let snippet = columnOptionalText(statement, at: 13)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                hits.append(
                    NoteSearchHit(
                        note: matchedNote,
                        snippet: snippet?.isEmpty == false ? snippet : nil,
                        rank: sqlite3_column_double(statement, 14)
                    )
                )
            }
            return hits
        }
        let hasMore = rawHits.count > normalizedLimit
        let hits = hasMore ? Array(rawHits.prefix(normalizedLimit)) : rawHits
        let inferredTotalCount = normalizedOffset + hits.count + (hasMore ? 1 : 0)

        return NoteSearchPage(
            query: trimmed,
            mode: mode,
            offset: normalizedOffset,
            limit: normalizedLimit,
            totalCount: inferredTotalCount,
            hits: hits
        )
    }

    public func tombstoneNote(id: UUID, at date: Date) async throws {
        try beginTransaction()
        do {
            let version = try nextVersion(for: "note_version")
            let sql = """
            UPDATE notes
            SET deleted_at = ?,
                updated_at = ?,
                version = ?
            WHERE id = ?;
            """

            try withStatement(sql) { statement in
                bindDate(date, to: 1, in: statement)
                bindDate(date, to: 2, in: statement)
                bindInt64(version, to: 3, in: statement)
                bindText(UUIDString(from: id), to: 4, in: statement)
                try stepDone(statement)
            }
            try deleteNoteFTS(noteID: id)
            try commitTransaction()
        } catch {
            try? rollbackTransaction()
            throw error
        }
    }

    public func fetchNotesUpdated(afterVersion version: Int64, limit: Int) async throws -> [Note] {
        let fetchLimit = max(1, limit)
        let sql = """
        SELECT id, stable_id, title, body, tags, date_start, date_end, is_all_day, recurrence_rule,
               calendar_sync_enabled, updated_at, version, deleted_at
        FROM notes
        WHERE version > ?
        ORDER BY version ASC
        LIMIT ?;
        """

        return try withStatement(sql) { statement in
            bindInt64(version, to: 1, in: statement)
            bindInt(Int32(fetchLimit), to: 2, in: statement)

            var notes: [Note] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                notes.append(try note(from: statement))
            }
            return notes
        }
    }

    // MARK: - Tasks

    public func upsertTask(_ task: Task) async throws -> Task {
        guard !task.stableID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainValidationError.missingStableID
        }

        try beginTransaction()
        do {
            let existingByStableID = try fetchTaskByStableIDInternal(task.stableID)
            let resolvedID = existingByStableID?.id ?? task.id
            let version = try nextVersion(for: "task_version")
            let now = max(task.updatedAt, Date())

            let sql = """
            INSERT INTO tasks (
                id,
                note_id,
                stable_id,
                title,
                details,
                due_start,
                due_end,
                status,
                priority,
                recurrence_rule,
                kanban_order,
                completed_at,
                updated_at,
                version,
                deleted_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                note_id = excluded.note_id,
                stable_id = excluded.stable_id,
                title = excluded.title,
                details = excluded.details,
                due_start = excluded.due_start,
                due_end = excluded.due_end,
                status = excluded.status,
                priority = excluded.priority,
                recurrence_rule = excluded.recurrence_rule,
                kanban_order = excluded.kanban_order,
                completed_at = excluded.completed_at,
                updated_at = excluded.updated_at,
                version = excluded.version,
                deleted_at = excluded.deleted_at;
            """

            try withStatement(sql) { statement in
                bindText(UUIDString(from: resolvedID), to: 1, in: statement)
                bindOptionalText(task.noteID.map(UUIDString), to: 2, in: statement)
                bindText(task.stableID, to: 3, in: statement)
                bindText(task.title, to: 4, in: statement)
                bindText(task.details, to: 5, in: statement)
                bindOptionalDate(task.dueStart, to: 6, in: statement)
                bindOptionalDate(task.dueEnd, to: 7, in: statement)
                bindText(task.status.rawValue, to: 8, in: statement)
                bindInt(Int32(task.priority), to: 9, in: statement)
                bindOptionalText(task.recurrenceRule, to: 10, in: statement)
                bindDouble(task.kanbanOrder, to: 11, in: statement)
                bindOptionalDate(task.completedAt, to: 12, in: statement)
                bindDate(now, to: 13, in: statement)
                bindInt64(version, to: 14, in: statement)
                bindOptionalDate(task.deletedAt, to: 15, in: statement)
                try stepDone(statement)
            }

            try commitTransaction()

            var persisted = task
            persisted.id = resolvedID
            persisted.updatedAt = now
            persisted.version = version
            return persisted
        } catch {
            try? rollbackTransaction()
            throw error
        }
    }

    public func fetchTask(id: UUID) async throws -> Task? {
        try fetchTaskInternal(id: id)
    }

    public func fetchTaskByStableID(_ stableID: String) async throws -> Task? {
        try fetchTaskByStableIDInternal(stableID)
    }

    public func fetchTasks(includeDeleted: Bool = false) async throws -> [Task] {
        let sql = includeDeleted
        ? """
          SELECT id, note_id, stable_id, title, details, due_start, due_end, status,
                 priority, recurrence_rule, kanban_order, completed_at, updated_at, version, deleted_at
          FROM tasks
          ORDER BY updated_at DESC;
          """
        : """
          SELECT id, note_id, stable_id, title, details, due_start, due_end, status,
                 priority, recurrence_rule, kanban_order, completed_at, updated_at, version, deleted_at
          FROM tasks
          WHERE deleted_at IS NULL
          ORDER BY updated_at DESC;
          """

        return try withStatement(sql) { statement in
            var tasks: [Task] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                tasks.append(try task(from: statement))
            }
            return tasks
        }
    }

    public func fetchTasksUpdated(afterVersion version: Int64, limit: Int) async throws -> [Task] {
        let fetchLimit = max(1, limit)
        let sql = """
        SELECT id, note_id, stable_id, title, details, due_start, due_end, status,
               priority, recurrence_rule, kanban_order, completed_at, updated_at, version, deleted_at
        FROM tasks
        WHERE version > ?
        ORDER BY version ASC
        LIMIT ?;
        """

        return try withStatement(sql) { statement in
            bindInt64(version, to: 1, in: statement)
            bindInt(Int32(fetchLimit), to: 2, in: statement)

            var tasks: [Task] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                tasks.append(try task(from: statement))
            }
            return tasks
        }
    }

    public func tombstoneTask(id: UUID, at date: Date) async throws {
        try beginTransaction()
        do {
            let version = try nextVersion(for: "task_version")
            let sql = """
            UPDATE tasks
            SET deleted_at = ?,
                updated_at = ?,
                version = ?
            WHERE id = ?;
            """

            try withStatement(sql) { statement in
                bindDate(date, to: 1, in: statement)
                bindDate(date, to: 2, in: statement)
                bindInt64(version, to: 3, in: statement)
                bindText(UUIDString(from: id), to: 4, in: statement)
                try stepDone(statement)
            }
            try commitTransaction()
        } catch {
            try? rollbackTransaction()
            throw error
        }
    }

    // MARK: - Calendar binding and checkpoints

    public func upsertBinding(_ binding: CalendarBinding) async throws {
        let sql = """
        INSERT INTO calendar_bindings (
            entity_type,
            entity_id,
            calendar_id,
            event_identifier,
            external_identifier,
            last_entity_version,
            last_event_updated_at,
            last_synced_at,
            deleted_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(entity_type, entity_id, calendar_id) DO UPDATE SET
            event_identifier = excluded.event_identifier,
            external_identifier = excluded.external_identifier,
            last_entity_version = excluded.last_entity_version,
            last_event_updated_at = excluded.last_event_updated_at,
            last_synced_at = excluded.last_synced_at,
            deleted_at = excluded.deleted_at;
        """

        try withStatement(sql) { statement in
            bindText(binding.entityType.rawValue, to: 1, in: statement)
            bindText(UUIDString(from: binding.entityID), to: 2, in: statement)
            bindText(binding.calendarID, to: 3, in: statement)
            bindOptionalText(binding.eventIdentifier, to: 4, in: statement)
            bindOptionalText(binding.externalIdentifier, to: 5, in: statement)
            bindInt64(binding.lastEntityVersion, to: 6, in: statement)
            bindOptionalDate(binding.lastEventUpdatedAt, to: 7, in: statement)
            bindOptionalDate(binding.lastSyncedAt, to: 8, in: statement)
            bindOptionalDate(binding.deletedAt, to: 9, in: statement)
            try stepDone(statement)
        }
    }

    public func fetchBinding(entityType: CalendarBindingEntityType, entityID: UUID, calendarID: String) async throws -> CalendarBinding? {
        let sql = """
        SELECT entity_type, entity_id, calendar_id, event_identifier, external_identifier,
               last_entity_version, last_event_updated_at, last_synced_at, deleted_at
        FROM calendar_bindings
        WHERE entity_type = ? AND entity_id = ? AND calendar_id = ?;
        """

        return try withStatement(sql) { statement in
            bindText(entityType.rawValue, to: 1, in: statement)
            bindText(UUIDString(from: entityID), to: 2, in: statement)
            bindText(calendarID, to: 3, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            return try binding(from: statement)
        }
    }

    public func fetchBinding(taskID: UUID, calendarID: String) async throws -> CalendarBinding? {
        try await fetchBinding(entityType: .task, entityID: taskID, calendarID: calendarID)
    }

    public func fetchBinding(eventIdentifier: String, calendarID: String) async throws -> CalendarBinding? {
        let sql = """
        SELECT entity_type, entity_id, calendar_id, event_identifier, external_identifier,
               last_entity_version, last_event_updated_at, last_synced_at, deleted_at
        FROM calendar_bindings
        WHERE event_identifier = ? AND calendar_id = ?;
        """

        return try withStatement(sql) { statement in
            bindText(eventIdentifier, to: 1, in: statement)
            bindText(calendarID, to: 2, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            return try binding(from: statement)
        }
    }

    public func fetchBinding(externalIdentifier: String, calendarID: String) async throws -> CalendarBinding? {
        let sql = """
        SELECT entity_type, entity_id, calendar_id, event_identifier, external_identifier,
               last_entity_version, last_event_updated_at, last_synced_at, deleted_at
        FROM calendar_bindings
        WHERE external_identifier = ? AND calendar_id = ?;
        """

        return try withStatement(sql) { statement in
            bindText(externalIdentifier, to: 1, in: statement)
            bindText(calendarID, to: 2, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            return try binding(from: statement)
        }
    }

    public func tombstoneBinding(taskID: UUID, calendarID: String, at date: Date) async throws {
        try await tombstoneBinding(entityType: .task, entityID: taskID, calendarID: calendarID, at: date)
    }

    public func tombstoneBinding(entityType: CalendarBindingEntityType, entityID: UUID, calendarID: String, at date: Date) async throws {
        var binding = try await fetchBinding(entityType: entityType, entityID: entityID, calendarID: calendarID)
            ?? CalendarBinding(entityType: entityType, entityID: entityID, calendarID: calendarID)
        binding.deletedAt = date
        binding.lastSyncedAt = date
        try await upsertBinding(binding)
    }

    public func fetchCheckpoint(id: String) async throws -> SyncCheckpoint? {
        let sql = """
        SELECT id, task_version_cursor, note_version_cursor, calendar_token, updated_at
        FROM sync_checkpoints
        WHERE id = ?;
        """

        return try withStatement(sql) { statement in
            bindText(id, to: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }

            guard let idCString = sqlite3_column_text(statement, 0) else {
                throw StorageError.dataCorruption(reason: "sync_checkpoints.id is NULL")
            }

            return SyncCheckpoint(
                id: String(cString: idCString),
                taskVersionCursor: sqlite3_column_int64(statement, 1),
                noteVersionCursor: sqlite3_column_int64(statement, 2),
                calendarToken: columnOptionalText(statement, at: 3),
                updatedAt: columnDate(statement, at: 4)
            )
        }
    }

    public func saveCheckpoint(_ checkpoint: SyncCheckpoint) async throws {
        let sql = """
        INSERT INTO sync_checkpoints (id, task_version_cursor, note_version_cursor, calendar_token, updated_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            task_version_cursor = excluded.task_version_cursor,
            note_version_cursor = excluded.note_version_cursor,
            calendar_token = excluded.calendar_token,
            updated_at = excluded.updated_at;
        """

        try withStatement(sql) { statement in
            bindText(checkpoint.id, to: 1, in: statement)
            bindInt64(checkpoint.taskVersionCursor, to: 2, in: statement)
            bindInt64(checkpoint.noteVersionCursor, to: 3, in: statement)
            bindOptionalText(checkpoint.calendarToken, to: 4, in: statement)
            bindDate(checkpoint.updatedAt, to: 5, in: statement)
            try stepDone(statement)
        }
    }

    // MARK: - Templates

    public func fetchTemplates() async throws -> [NoteTemplate] {
        let sql = """
        SELECT id, name, body, created_at
        FROM templates
        ORDER BY created_at DESC;
        """

        return try withStatement(sql) { statement in
            var templates: [NoteTemplate] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                templates.append(try template(from: statement))
            }
            return templates
        }
    }

    public func upsertTemplate(_ template: NoteTemplate) async throws -> NoteTemplate {
        let normalizedName = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw StorageError.executeStatement(reason: "Template name cannot be empty")
        }

        let sql = """
        INSERT INTO templates (id, name, body, created_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            name = excluded.name,
            body = excluded.body,
            created_at = excluded.created_at;
        """

        try withStatement(sql) { statement in
            bindText(UUIDString(from: template.id), to: 1, in: statement)
            bindText(normalizedName, to: 2, in: statement)
            bindText(template.body, to: 3, in: statement)
            bindDate(template.createdAt, to: 4, in: statement)
            try stepDone(statement)
        }

        var persisted = template
        persisted.name = normalizedName
        return persisted
    }

    public func deleteTemplate(id: UUID) async throws {
        let sql = "DELETE FROM templates WHERE id = ?;"

        try withStatement(sql) { statement in
            bindText(UUIDString(from: id), to: 1, in: statement)
            try stepDone(statement)
        }
    }

    private func template(from statement: OpaquePointer) throws -> NoteTemplate {
        let idString = String(cString: sqlite3_column_text(statement, 0))
        let id = UUID(uuidString: idString) ?? UUID()
        let name = columnOptionalText(statement, at: 1) ?? ""
        let body = columnOptionalText(statement, at: 2) ?? ""
        let createdAt = columnDate(statement, at: 3)

        return NoteTemplate(id: id, name: name, body: body, createdAt: createdAt)
    }

    // MARK: - Internals

    private static func runMigrations(on db: OpaquePointer) throws {
        let migrationSQL = """
        CREATE TABLE IF NOT EXISTS meta (
            key TEXT PRIMARY KEY,
            int_value INTEGER NOT NULL
        );

        INSERT INTO meta (key, int_value) VALUES ('task_version', 0) ON CONFLICT(key) DO NOTHING;
        INSERT INTO meta (key, int_value) VALUES ('note_version', 0) ON CONFLICT(key) DO NOTHING;

        CREATE TABLE IF NOT EXISTS notes (
            id TEXT PRIMARY KEY,
            stable_id TEXT NOT NULL UNIQUE,
            title TEXT NOT NULL COLLATE NOCASE UNIQUE,
            body TEXT NOT NULL,
            date_start REAL,
            date_end REAL,
            is_all_day INTEGER NOT NULL DEFAULT 0,
            recurrence_rule TEXT,
            calendar_sync_enabled INTEGER NOT NULL DEFAULT 0,
            updated_at REAL NOT NULL,
            version INTEGER NOT NULL,
            deleted_at REAL
        );

        CREATE INDEX IF NOT EXISTS idx_notes_updated_at ON notes(updated_at);

        CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
            note_id UNINDEXED,
            title,
            body,
            tokenize='unicode61 remove_diacritics 2'
        );

        DELETE FROM notes_fts;
        INSERT INTO notes_fts (note_id, title, body)
        SELECT id, title, body
        FROM notes
        WHERE deleted_at IS NULL;

        CREATE TABLE IF NOT EXISTS tasks (
            id TEXT PRIMARY KEY,
            note_id TEXT,
            stable_id TEXT NOT NULL UNIQUE,
            title TEXT NOT NULL,
            details TEXT NOT NULL,
            due_start REAL,
            due_end REAL,
            status TEXT NOT NULL,
            priority INTEGER NOT NULL,
            recurrence_rule TEXT,
            kanban_order REAL NOT NULL DEFAULT 0,
            completed_at REAL,
            updated_at REAL NOT NULL,
            version INTEGER NOT NULL,
            deleted_at REAL,
            FOREIGN KEY(note_id) REFERENCES notes(id)
        );

        """

        try executeOnConnection(db, sql: migrationSQL)
        try ensureColumnExists(
            table: "notes",
            column: "stable_id",
            definition: "TEXT",
            on: db
        )
        try executeOnConnection(
            db,
            sql: "UPDATE notes SET stable_id = lower(id) WHERE stable_id IS NULL OR trim(stable_id) = '';"
        )
        try executeOnConnection(
            db,
            sql: "CREATE UNIQUE INDEX IF NOT EXISTS idx_notes_stable_id ON notes(stable_id);"
        )
        try ensureColumnExists(table: "notes", column: "date_start", definition: "REAL", on: db)
        try ensureColumnExists(table: "notes", column: "date_end", definition: "REAL", on: db)
        try ensureColumnExists(table: "notes", column: "is_all_day", definition: "INTEGER NOT NULL DEFAULT 0", on: db)
        try ensureColumnExists(table: "notes", column: "recurrence_rule", definition: "TEXT", on: db)
        try ensureColumnExists(table: "notes", column: "calendar_sync_enabled", definition: "INTEGER NOT NULL DEFAULT 0", on: db)
        try ensureColumnExists(table: "notes", column: "tags", definition: "TEXT NOT NULL DEFAULT '[]'", on: db)
        try ensureColumnExists(
            table: "tasks",
            column: "kanban_order",
            definition: "REAL NOT NULL DEFAULT 0",
            on: db
        )

        let indexSQL = """
        CREATE INDEX IF NOT EXISTS idx_tasks_version ON tasks(version);
        CREATE INDEX IF NOT EXISTS idx_tasks_stable_id ON tasks(stable_id);
        CREATE INDEX IF NOT EXISTS idx_tasks_updated_at ON tasks(updated_at);

        CREATE TABLE IF NOT EXISTS calendar_bindings (
            entity_type TEXT NOT NULL DEFAULT 'task',
            entity_id TEXT NOT NULL,
            calendar_id TEXT NOT NULL,
            event_identifier TEXT,
            external_identifier TEXT,
            last_entity_version INTEGER NOT NULL,
            last_event_updated_at REAL,
            last_synced_at REAL,
            deleted_at REAL,
            PRIMARY KEY (entity_type, entity_id, calendar_id)
        );

        CREATE INDEX IF NOT EXISTS idx_bindings_event_identifier ON calendar_bindings(calendar_id, event_identifier);
        CREATE INDEX IF NOT EXISTS idx_bindings_external_identifier ON calendar_bindings(calendar_id, external_identifier);

        CREATE TABLE IF NOT EXISTS sync_checkpoints (
            id TEXT PRIMARY KEY,
            task_version_cursor INTEGER NOT NULL,
            note_version_cursor INTEGER NOT NULL DEFAULT 0,
            calendar_token TEXT,
            updated_at REAL NOT NULL
        );
        """
        try executeOnConnection(db, sql: indexSQL)
        try migrateCalendarBindingsToPolymorphic(on: db)
        try ensureColumnExists(table: "sync_checkpoints", column: "note_version_cursor", definition: "INTEGER NOT NULL DEFAULT 0", on: db)

        let templatesSQL = """
        CREATE TABLE IF NOT EXISTS templates (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            body TEXT NOT NULL,
            created_at REAL NOT NULL
        );
        """
        try executeOnConnection(db, sql: templatesSQL)

        // Rebuild FTS to include tags content
        let ftsRebuildSQL = """
        DELETE FROM notes_fts;
        INSERT INTO notes_fts (note_id, title, body)
        SELECT id, title, body || CASE WHEN tags != '[]' THEN ' ' || replace(replace(replace(tags, '["', ''), '"]', ''), '","', ' ') ELSE '' END
        FROM notes
        WHERE deleted_at IS NULL;
        """
        try executeOnConnection(db, sql: ftsRebuildSQL)
    }

    private static func executeOnConnection(_ db: OpaquePointer, sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw StorageError.executeStatement(reason: String(cString: sqlite3_errmsg(db)))
        }
    }

    private static func ensureColumnExists(
        table: String,
        column: String,
        definition: String,
        on db: OpaquePointer
    ) throws {
        let pragmaSQL = "PRAGMA table_info(\(table));"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, pragmaSQL, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw StorageError.prepareStatement(reason: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var exists = false
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let nameCString = sqlite3_column_text(statement, 1) else {
                continue
            }
            if String(cString: nameCString) == column {
                exists = true
                break
            }
        }

        guard !exists else {
            return
        }

        try executeOnConnection(db, sql: "ALTER TABLE \(table) ADD COLUMN \(column) \(definition);")
    }

    private static func tableHasColumn(table: String, column: String, on db: OpaquePointer) throws -> Bool {
        let pragmaSQL = "PRAGMA table_info(\(table));"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, pragmaSQL, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw StorageError.prepareStatement(reason: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let nameCString = sqlite3_column_text(statement, 1) else {
                continue
            }
            if String(cString: nameCString) == column {
                return true
            }
        }
        return false
    }

    private static func migrateCalendarBindingsToPolymorphic(on db: OpaquePointer) throws {
        let alreadyMigrated = try tableHasColumn(table: "calendar_bindings", column: "entity_type", on: db)
            && tableHasColumn(table: "calendar_bindings", column: "entity_id", on: db)
        guard !alreadyMigrated else {
            return
        }

        let migrationSQL = """
        ALTER TABLE calendar_bindings RENAME TO calendar_bindings_legacy;

        CREATE TABLE IF NOT EXISTS calendar_bindings (
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            calendar_id TEXT NOT NULL,
            event_identifier TEXT,
            external_identifier TEXT,
            last_entity_version INTEGER NOT NULL,
            last_event_updated_at REAL,
            last_synced_at REAL,
            deleted_at REAL,
            PRIMARY KEY (entity_type, entity_id, calendar_id)
        );

        INSERT INTO calendar_bindings (
            entity_type,
            entity_id,
            calendar_id,
            event_identifier,
            external_identifier,
            last_entity_version,
            last_event_updated_at,
            last_synced_at,
            deleted_at
        )
        SELECT
            'task',
            task_id,
            calendar_id,
            event_identifier,
            external_identifier,
            last_task_version,
            last_event_updated_at,
            last_synced_at,
            deleted_at
        FROM calendar_bindings_legacy;

        DROP TABLE calendar_bindings_legacy;

        CREATE INDEX IF NOT EXISTS idx_bindings_event_identifier ON calendar_bindings(calendar_id, event_identifier);
        CREATE INDEX IF NOT EXISTS idx_bindings_external_identifier ON calendar_bindings(calendar_id, external_identifier);
        """

        try executeOnConnection(db, sql: migrationSQL)
    }

    private func nextVersion(for key: String) throws -> Int64 {
        let fetchSQL = "SELECT int_value FROM meta WHERE key = ?;"
        let currentVersion = try withStatement(fetchSQL) { statement in
            bindText(key, to: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw StorageError.dataCorruption(reason: "meta.\(key) row missing")
            }
            return sqlite3_column_int64(statement, 0)
        }

        let newVersion = currentVersion + 1
        let updateSQL = "UPDATE meta SET int_value = ? WHERE key = ?;"
        try withStatement(updateSQL) { statement in
            bindInt64(newVersion, to: 1, in: statement)
            bindText(key, to: 2, in: statement)
            try stepDone(statement)
        }
        return newVersion
    }

    private func fetchNoteInternal(id: UUID) throws -> Note? {
        let sql = """
        SELECT id, stable_id, title, body, tags, date_start, date_end, is_all_day, recurrence_rule,
               calendar_sync_enabled, updated_at, version, deleted_at
        FROM notes
        WHERE id = ?;
        """

        return try withStatement(sql) { statement in
            bindText(UUIDString(from: id), to: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            return try note(from: statement)
        }
    }

    private func fetchNoteByTitleInternal(_ title: String) throws -> Note? {
        let sql = """
        SELECT id, stable_id, title, body, tags, date_start, date_end, is_all_day, recurrence_rule,
               calendar_sync_enabled, updated_at, version, deleted_at
        FROM notes
        WHERE title = ? COLLATE NOCASE
        LIMIT 1;
        """

        return try withStatement(sql) { statement in
            bindText(title.trimmingCharacters(in: .whitespacesAndNewlines), to: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            return try note(from: statement)
        }
    }

    private func fetchNoteByStableIDInternal(_ stableID: String) throws -> Note? {
        let sql = """
        SELECT id, stable_id, title, body, tags, date_start, date_end, is_all_day, recurrence_rule,
               calendar_sync_enabled, updated_at, version, deleted_at
        FROM notes
        WHERE stable_id = ?
        LIMIT 1;
        """

        return try withStatement(sql) { statement in
            bindText(stableID.trimmingCharacters(in: .whitespacesAndNewlines), to: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            return try note(from: statement)
        }
    }

    private func fetchTaskInternal(id: UUID) throws -> Task? {
        let sql = """
        SELECT id, note_id, stable_id, title, details, due_start, due_end, status,
               priority, recurrence_rule, kanban_order, completed_at, updated_at, version, deleted_at
        FROM tasks
        WHERE id = ?;
        """

        return try withStatement(sql) { statement in
            bindText(UUIDString(from: id), to: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            return try task(from: statement)
        }
    }

    private func fetchTaskByStableIDInternal(_ stableID: String) throws -> Task? {
        let sql = """
        SELECT id, note_id, stable_id, title, details, due_start, due_end, status,
               priority, recurrence_rule, kanban_order, completed_at, updated_at, version, deleted_at
        FROM tasks
        WHERE stable_id = ?;
        """

        return try withStatement(sql) { statement in
            bindText(stableID, to: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            return try task(from: statement)
        }
    }

    private func note(from statement: OpaquePointer) throws -> Note {
        guard
            let idText = columnOptionalText(statement, at: 0),
            let id = UUID(uuidString: idText),
            let stableID = columnOptionalText(statement, at: 1),
            let title = columnOptionalText(statement, at: 2),
            let body = columnOptionalText(statement, at: 3)
        else {
            throw StorageError.dataCorruption(reason: "Invalid note row values")
        }

        let tags: [String]
        if let tagsJSON = columnOptionalText(statement, at: 4),
           let data = tagsJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            tags = decoded
        } else {
            tags = []
        }

        return Note(
            id: id,
            stableID: stableID,
            title: title,
            body: body,
            tags: tags,
            dateStart: columnOptionalDate(statement, at: 5),
            dateEnd: columnOptionalDate(statement, at: 6),
            isAllDay: sqlite3_column_int(statement, 7) != 0,
            recurrenceRule: columnOptionalText(statement, at: 8),
            calendarSyncEnabled: sqlite3_column_int(statement, 9) != 0,
            updatedAt: columnDate(statement, at: 10),
            version: sqlite3_column_int64(statement, 11),
            deletedAt: columnOptionalDate(statement, at: 12)
        )
    }

    private func task(from statement: OpaquePointer) throws -> Task {
        guard
            let idCString = sqlite3_column_text(statement, 0),
            let id = UUID(uuidString: String(cString: idCString)),
            let stableIDCString = sqlite3_column_text(statement, 2),
            let titleCString = sqlite3_column_text(statement, 3),
            let detailsCString = sqlite3_column_text(statement, 4),
            let statusCString = sqlite3_column_text(statement, 7),
            let status = TaskStatus(rawValue: String(cString: statusCString))
        else {
            throw StorageError.dataCorruption(reason: "Invalid task row values")
        }

        let noteID: UUID?
        if let noteIDText = columnOptionalText(statement, at: 1) {
            noteID = UUID(uuidString: noteIDText)
        } else {
            noteID = nil
        }

        return try Task(
            id: id,
            noteID: noteID,
            stableID: String(cString: stableIDCString),
            title: String(cString: titleCString),
            details: String(cString: detailsCString),
            dueStart: columnOptionalDate(statement, at: 5),
            dueEnd: columnOptionalDate(statement, at: 6),
            status: status,
            priority: Int(sqlite3_column_int(statement, 8)),
            recurrenceRule: columnOptionalText(statement, at: 9),
            kanbanOrder: sqlite3_column_double(statement, 10),
            completedAt: columnOptionalDate(statement, at: 11),
            updatedAt: columnDate(statement, at: 12),
            version: sqlite3_column_int64(statement, 13),
            deletedAt: columnOptionalDate(statement, at: 14)
        )
    }

    private func binding(from statement: OpaquePointer) throws -> CalendarBinding {
        guard
            let entityTypeRaw = columnOptionalText(statement, at: 0),
            let entityType = CalendarBindingEntityType(rawValue: entityTypeRaw),
            let entityIDText = columnOptionalText(statement, at: 1),
            let entityID = UUID(uuidString: entityIDText),
            let calendarID = columnOptionalText(statement, at: 2)
        else {
            throw StorageError.dataCorruption(reason: "Invalid calendar binding row")
        }

        return CalendarBinding(
            entityType: entityType,
            entityID: entityID,
            calendarID: calendarID,
            eventIdentifier: columnOptionalText(statement, at: 3),
            externalIdentifier: columnOptionalText(statement, at: 4),
            lastEntityVersion: sqlite3_column_int64(statement, 5),
            lastEventUpdatedAt: columnOptionalDate(statement, at: 6),
            lastSyncedAt: columnOptionalDate(statement, at: 7),
            deletedAt: columnOptionalDate(statement, at: 8)
        )
    }

    private func execute(_ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw StorageError.executeStatement(reason: errorMessage)
        }
    }

    private func syncNoteFTS(noteID: UUID, title: String, body: String, tags: [String], deletedAt: Date?) throws {
        try deleteNoteFTS(noteID: noteID)
        guard deletedAt == nil else {
            return
        }

        let tagsContent = tags.isEmpty ? "" : " " + tags.joined(separator: " ")
        let sql = "INSERT INTO notes_fts (note_id, title, body) VALUES (?, ?, ?);"
        try withStatement(sql) { statement in
            bindText(UUIDString(from: noteID), to: 1, in: statement)
            bindText(title, to: 2, in: statement)
            bindText(body + tagsContent, to: 3, in: statement)
            try stepDone(statement)
        }
    }

    private func deleteNoteFTS(noteID: UUID) throws {
        let sql = "DELETE FROM notes_fts WHERE note_id = ?;"
        try withStatement(sql) { statement in
            bindText(UUIDString(from: noteID), to: 1, in: statement)
            try stepDone(statement)
        }
    }

    private enum FTSSearchSegment {
        case phrase(String)
        case token(String)
    }

    private func ftsMatchExpression(from query: String, mode: NoteSearchMode) -> String? {
        switch mode {
        case .prefix:
            let tokens = tokenizeSearchTerms(query)
            guard !tokens.isEmpty else {
                return nil
            }
            return tokens.map { "\"\(escapeFTSValue($0))\"*" }.joined(separator: " AND ")
        case .phrase:
            let phrase = query
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty else {
                return nil
            }
            return "\"\(escapeFTSValue(phrase))\""
        case .smart:
            let segments = parseSmartSearchSegments(query)
            guard !segments.isEmpty else {
                return nil
            }
            return segments.map { segment in
                switch segment {
                case let .phrase(phrase):
                    return "\"\(escapeFTSValue(phrase))\""
                case let .token(token):
                    return "\"\(escapeFTSValue(token))\"*"
                }
            }.joined(separator: " AND ")
        }
    }

    private func tokenizeSearchTerms(_ query: String) -> [String] {
        let tokenSeparators = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).inverted
        return query
            .lowercased()
            .components(separatedBy: tokenSeparators)
            .filter { !$0.isEmpty }
    }

    private func parseSmartSearchSegments(_ query: String) -> [FTSSearchSegment] {
        var segments: [FTSSearchSegment] = []
        var buffer = ""
        var inQuote = false

        func flushBuffer() {
            guard !buffer.isEmpty else {
                return
            }
            if inQuote {
                let phrase = buffer
                    .split(whereSeparator: \.isWhitespace)
                    .map(String.init)
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !phrase.isEmpty {
                    segments.append(.phrase(phrase))
                }
            } else {
                let tokens = tokenizeSearchTerms(buffer)
                segments.append(contentsOf: tokens.map(FTSSearchSegment.token))
            }
            buffer = ""
        }

        for character in query {
            if character == "\"" {
                flushBuffer()
                inQuote.toggle()
                continue
            }
            buffer.append(character)
        }
        flushBuffer()

        return segments
    }

    private func escapeFTSValue(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\"\"")
    }

    private func withStatement<T>(_ sql: String, _ work: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw StorageError.prepareStatement(reason: errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        return try work(statement)
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        let result = sqlite3_step(statement)
        if result != SQLITE_DONE {
            throw StorageError.executeStatement(reason: errorMessage)
        }
    }

    private func beginTransaction() throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
    }

    private func commitTransaction() throws {
        try execute("COMMIT;")
    }

    private func rollbackTransaction() throws {
        try execute("ROLLBACK;")
    }

    private var errorMessage: String {
        String(cString: sqlite3_errmsg(db))
    }
}

private func UUIDString(from uuid: UUID) -> String {
    uuid.uuidString.lowercased()
}

private let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func bindText(_ value: String, to index: Int32, in statement: OpaquePointer) {
    sqlite3_bind_text(statement, index, value, -1, sqliteTransientDestructor)
}

private func bindOptionalText(_ value: String?, to index: Int32, in statement: OpaquePointer) {
    if let value {
        bindText(value, to: index, in: statement)
    } else {
        sqlite3_bind_null(statement, index)
    }
}

private func bindDate(_ value: Date, to index: Int32, in statement: OpaquePointer) {
    sqlite3_bind_double(statement, index, value.timeIntervalSince1970)
}

private func bindOptionalDate(_ value: Date?, to index: Int32, in statement: OpaquePointer) {
    if let value {
        bindDate(value, to: index, in: statement)
    } else {
        sqlite3_bind_null(statement, index)
    }
}

private func bindInt(_ value: Int32, to index: Int32, in statement: OpaquePointer) {
    sqlite3_bind_int(statement, index, value)
}

private func bindDouble(_ value: Double, to index: Int32, in statement: OpaquePointer) {
    sqlite3_bind_double(statement, index, value)
}

private func bindInt64(_ value: Int64, to index: Int32, in statement: OpaquePointer) {
    sqlite3_bind_int64(statement, index, value)
}

private func columnOptionalText(_ statement: OpaquePointer, at index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL,
          let cString = sqlite3_column_text(statement, index)
    else {
        return nil
    }
    return String(cString: cString)
}

private func columnDate(_ statement: OpaquePointer, at index: Int32) -> Date {
    Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
}

private func columnOptionalDate(_ statement: OpaquePointer, at index: Int32) -> Date? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
        return nil
    }
    return columnDate(statement, at: index)
}
