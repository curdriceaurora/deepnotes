import XCTest
import Foundation
import SQLite3
@testable import NotesStorage
@testable import NotesDomain

final class SQLiteMigrationTests: XCTestCase {
    func testFreshInstallBootstrapIsIdempotentAcrossReopen() async throws {
        let dbURL = try makeDatabaseURL()

        do {
            let store = try SQLiteStore(databaseURL: dbURL)
            let created = try await store.upsertTask(
                Task(
                    stableID: "fresh-task",
                    title: "Fresh task",
                    status: .backlog,
                    kanbanOrder: 1,
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
                )
            )
            XCTAssertEqual(created.kanbanOrder, 1)
        }

        do {
            let reopened = try SQLiteStore(databaseURL: dbURL)
            let fetched = try await reopened.fetchTaskByStableID("fresh-task")
            XCTAssertEqual(fetched?.title, "Fresh task")
            XCTAssertEqual(fetched?.kanbanOrder, 1)
        }

        let versions = try fetchMetaVersions(databaseURL: dbURL)
        XCTAssertNotNil(versions["task_version"])
        XCTAssertNotNil(versions["note_version"])
    }

    // MARK: - Schema upgrade matrix

    /// Schema era 1: notes + tasks with no kanban_order, no stable_id on notes,
    /// original task_id-keyed calendar_bindings, sync_checkpoints without note_version_cursor.
    /// Matches the existing loadLegacyFixture snapshot (the pre-kanban release).
    /// Verifies: kanban_order added, stable_id backfilled, FTS rebuilt, bindings migrated to
    /// polymorphic schema, note_version_cursor added to sync_checkpoints.
    func testSchemaEra1MigratesAllColumnsAndTablesCorrectly() async throws {
        let dbURL = try makeDatabaseURL()
        try loadEra1Fixture(databaseURL: dbURL)

        let store = try SQLiteStore(databaseURL: dbURL)

        // Task data preserved and kanban_order defaulted to 0
        let task = try await store.fetchTaskByStableID("era1-task")
        XCTAssertNotNil(task, "era1-task should survive migration")
        XCTAssertEqual(task?.kanbanOrder, 0)
        XCTAssertEqual(task?.title, "Era1 Task")

        // Note FTS rebuilt: search should find the note
        let hits = try await store.searchNotes(query: "era1", limit: 10)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.title, "Era1 Note")

        // calendar_bindings migrated to polymorphic schema — binding is accessible
        let binding = try await store.fetchBinding(
            eventIdentifier: "era1-event",
            calendarID: "era1-cal"
        )
        XCTAssertNotNil(binding, "Existing binding should be migrated to polymorphic schema")
        XCTAssertEqual(binding?.calendarID, "era1-cal")

        // sync_checkpoints gains note_version_cursor (readable via fetchCheckpoint)
        let checkpoint = try await store.fetchCheckpoint(id: "era1-checkpoint")
        XCTAssertNotNil(checkpoint)
        XCTAssertEqual(checkpoint?.taskVersionCursor, 3)
        XCTAssertEqual(checkpoint?.noteVersionCursor, 0, "note_version_cursor defaults to 0 after migration")

        // Columns present on notes table
        let noteColumns = try tableColumns(table: "notes", databaseURL: dbURL)
        XCTAssertTrue(noteColumns.contains("stable_id"))
        XCTAssertTrue(noteColumns.contains("date_start"))
        XCTAssertTrue(noteColumns.contains("is_all_day"))
        XCTAssertTrue(noteColumns.contains("recurrence_rule"))
        XCTAssertTrue(noteColumns.contains("calendar_sync_enabled"))
    }

    /// Schema era 2: notes already has stable_id and kanban_order exists on tasks,
    /// but calendar_bindings still uses the old task_id-keyed schema (pre-polymorphic).
    /// Verifies the binding migration path in isolation.
    func testSchemaEra2MigratesCalendarBindingsToPolymorphic() async throws {
        let dbURL = try makeDatabaseURL()
        try loadEra2Fixture(databaseURL: dbURL)

        let store = try SQLiteStore(databaseURL: dbURL)

        // Task still accessible
        let task = try await store.fetchTaskByStableID("era2-task")
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.kanbanOrder, 5)

        // Old task_id binding was migrated: entity_type = 'task', entity_id = task UUID
        let binding = try await store.fetchBinding(
            eventIdentifier: "era2-event",
            calendarID: "era2-cal"
        )
        XCTAssertNotNil(binding, "task_id-keyed binding should be migrated")
        XCTAssertEqual(binding?.eventIdentifier, "era2-event")

        // Legacy table should be gone
        let tables = try tableNames(databaseURL: dbURL)
        XCTAssertFalse(tables.contains("calendar_bindings_legacy"), "Legacy table should be dropped after migration")
    }

    /// Schema era 3: fully migrated schema except sync_checkpoints is missing note_version_cursor.
    /// Verifies that note_version_cursor is added and defaults to 0.
    func testSchemaEra3AddsNoteVersionCursorToCheckpoints() async throws {
        let dbURL = try makeDatabaseURL()
        try loadEra3Fixture(databaseURL: dbURL)

        let store = try SQLiteStore(databaseURL: dbURL)

        let checkpoint = try await store.fetchCheckpoint(id: "era3-checkpoint")
        XCTAssertNotNil(checkpoint)
        XCTAssertEqual(checkpoint?.taskVersionCursor, 10)
        XCTAssertEqual(checkpoint?.noteVersionCursor, 0, "note_version_cursor defaults to 0 after column is added")

        // Upsert through the store to confirm the column is writable
        var updated = checkpoint!
        updated.noteVersionCursor = 7
        updated.updatedAt = Date()
        try await store.saveCheckpoint(updated)
        let refetched = try await store.fetchCheckpoint(id: "era3-checkpoint")
        XCTAssertEqual(refetched?.noteVersionCursor, 7)
    }

    func testLegacySchemaMigrationAddsKanbanOrderAndRebuildsFTS() async throws {
        let dbURL = try makeDatabaseURL()
        try loadLegacyFixture(databaseURL: dbURL)

        let store = try SQLiteStore(databaseURL: dbURL)

        let migrated = try await store.fetchTaskByStableID("legacy-task")
        XCTAssertNotNil(migrated)
        XCTAssertEqual(migrated?.kanbanOrder, 0)

        let matches = try await store.searchNotes(query: "launch", limit: 10)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.title, "Legacy Plan")

        let versions = try fetchMetaVersions(databaseURL: dbURL)
        XCTAssertEqual(versions["task_version"], 7)
        XCTAssertEqual(versions["note_version"], 5)
    }

    private func makeDatabaseURL() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-engine-migration-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("notes.sqlite")
    }

    private func loadLegacyFixture(databaseURL: URL) throws {
        var dbPointer: OpaquePointer?
        let openCode = sqlite3_open_v2(
            databaseURL.path,
            &dbPointer,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openCode == SQLITE_OK, let dbPointer else {
            throw StorageError.openDatabase(path: databaseURL.path, reason: "Could not create legacy fixture DB")
        }
        defer { sqlite3_close(dbPointer) }

        let legacySQL = """
        CREATE TABLE meta (
            key TEXT PRIMARY KEY,
            int_value INTEGER NOT NULL
        );
        INSERT INTO meta (key, int_value) VALUES ('task_version', 7);
        INSERT INTO meta (key, int_value) VALUES ('note_version', 5);

        CREATE TABLE notes (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL COLLATE NOCASE UNIQUE,
            body TEXT NOT NULL,
            updated_at REAL NOT NULL,
            version INTEGER NOT NULL,
            deleted_at REAL
        );

        CREATE TABLE tasks (
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
            completed_at REAL,
            updated_at REAL NOT NULL,
            version INTEGER NOT NULL,
            deleted_at REAL
        );

        CREATE TABLE calendar_bindings (
            task_id TEXT NOT NULL,
            calendar_id TEXT NOT NULL,
            event_identifier TEXT,
            external_identifier TEXT,
            last_task_version INTEGER NOT NULL,
            last_event_updated_at REAL,
            last_synced_at REAL,
            deleted_at REAL,
            PRIMARY KEY (task_id, calendar_id)
        );

        CREATE TABLE sync_checkpoints (
            id TEXT PRIMARY KEY,
            task_version_cursor INTEGER NOT NULL,
            calendar_token TEXT,
            updated_at REAL NOT NULL
        );

        INSERT INTO notes (id, title, body, updated_at, version, deleted_at)
        VALUES (
            'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'Legacy Plan',
            'Legacy launch checklist',
            1700000000,
            3,
            NULL
        );

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
            completed_at,
            updated_at,
            version,
            deleted_at
        ) VALUES (
            'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
            'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'legacy-task',
            'Legacy migration task',
            '',
            NULL,
            NULL,
            'backlog',
            3,
            NULL,
            NULL,
            1700000000,
            4,
            NULL
        );
        """

        guard sqlite3_exec(dbPointer, legacySQL, nil, nil, nil) == SQLITE_OK else {
            let reason = String(cString: sqlite3_errmsg(dbPointer))
            throw StorageError.executeStatement(reason: reason)
        }
    }

    // MARK: - Era fixtures

    /// Era 1: oldest known schema — no kanban_order, no stable_id on notes,
    /// old task_id-keyed calendar_bindings, sync_checkpoints without note_version_cursor.
    private func loadEra1Fixture(databaseURL: URL) throws {
        try execSQL(databaseURL: databaseURL, sql: """
        CREATE TABLE meta (
            key TEXT PRIMARY KEY,
            int_value INTEGER NOT NULL
        );
        INSERT INTO meta (key, int_value) VALUES ('task_version', 2);
        INSERT INTO meta (key, int_value) VALUES ('note_version', 1);

        CREATE TABLE notes (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL COLLATE NOCASE UNIQUE,
            body TEXT NOT NULL,
            updated_at REAL NOT NULL,
            version INTEGER NOT NULL,
            deleted_at REAL
        );

        CREATE TABLE tasks (
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
            completed_at REAL,
            updated_at REAL NOT NULL,
            version INTEGER NOT NULL,
            deleted_at REAL
        );

        CREATE TABLE calendar_bindings (
            task_id TEXT NOT NULL,
            calendar_id TEXT NOT NULL,
            event_identifier TEXT,
            external_identifier TEXT,
            last_task_version INTEGER NOT NULL,
            last_event_updated_at REAL,
            last_synced_at REAL,
            deleted_at REAL,
            PRIMARY KEY (task_id, calendar_id)
        );

        CREATE TABLE sync_checkpoints (
            id TEXT PRIMARY KEY,
            task_version_cursor INTEGER NOT NULL,
            calendar_token TEXT,
            updated_at REAL NOT NULL
        );

        INSERT INTO notes (id, title, body, updated_at, version, deleted_at)
        VALUES (
            'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1',
            'Era1 Note',
            'era1 content for full-text search',
            1700000000,
            1,
            NULL
        );

        INSERT INTO tasks (id, note_id, stable_id, title, details, due_start, due_end,
                           status, priority, recurrence_rule, completed_at, updated_at, version, deleted_at)
        VALUES (
            'b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1',
            'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1',
            'era1-task',
            'Era1 Task',
            '',
            NULL, NULL,
            'backlog',
            2,
            NULL, NULL,
            1700000000,
            2,
            NULL
        );

        INSERT INTO calendar_bindings (task_id, calendar_id, event_identifier, external_identifier,
                                       last_task_version, last_event_updated_at, last_synced_at, deleted_at)
        VALUES (
            'b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1',
            'era1-cal',
            'era1-event',
            'era1-ext',
            2,
            1700000000,
            1700000100,
            NULL
        );

        INSERT INTO sync_checkpoints (id, task_version_cursor, calendar_token, updated_at)
        VALUES ('era1-checkpoint', 3, 'token-era1', 1700000200);
        """)
    }

    /// Era 2: notes has stable_id + new columns, tasks has kanban_order,
    /// but calendar_bindings still uses the old task_id PK schema.
    private func loadEra2Fixture(databaseURL: URL) throws {
        try execSQL(databaseURL: databaseURL, sql: """
        CREATE TABLE meta (
            key TEXT PRIMARY KEY,
            int_value INTEGER NOT NULL
        );
        INSERT INTO meta (key, int_value) VALUES ('task_version', 4);
        INSERT INTO meta (key, int_value) VALUES ('note_version', 2);

        CREATE TABLE notes (
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

        CREATE TABLE tasks (
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
            deleted_at REAL
        );

        CREATE TABLE calendar_bindings (
            task_id TEXT NOT NULL,
            calendar_id TEXT NOT NULL,
            event_identifier TEXT,
            external_identifier TEXT,
            last_task_version INTEGER NOT NULL,
            last_event_updated_at REAL,
            last_synced_at REAL,
            deleted_at REAL,
            PRIMARY KEY (task_id, calendar_id)
        );

        CREATE TABLE sync_checkpoints (
            id TEXT PRIMARY KEY,
            task_version_cursor INTEGER NOT NULL,
            calendar_token TEXT,
            updated_at REAL NOT NULL
        );

        INSERT INTO notes (id, stable_id, title, body, updated_at, version)
        VALUES (
            'c2c2c2c2-c2c2-c2c2-c2c2-c2c2c2c2c2c2',
            'era2-note',
            'Era2 Note',
            'era2 body',
            1700001000,
            2
        );

        INSERT INTO tasks (id, note_id, stable_id, title, details, status, priority,
                           kanban_order, updated_at, version)
        VALUES (
            'd2d2d2d2-d2d2-d2d2-d2d2-d2d2d2d2d2d2',
            'c2c2c2c2-c2c2-c2c2-c2c2-c2c2c2c2c2c2',
            'era2-task',
            'Era2 Task',
            '',
            'next',
            3,
            5,
            1700001000,
            4
        );

        INSERT INTO calendar_bindings (task_id, calendar_id, event_identifier, external_identifier,
                                       last_task_version, last_event_updated_at, last_synced_at, deleted_at)
        VALUES (
            'd2d2d2d2-d2d2-d2d2-d2d2-d2d2d2d2d2d2',
            'era2-cal',
            'era2-event',
            'era2-ext',
            4,
            1700001000,
            1700001100,
            NULL
        );
        """)
    }

    /// Era 3: fully up-to-date schema except sync_checkpoints is missing note_version_cursor.
    private func loadEra3Fixture(databaseURL: URL) throws {
        try execSQL(databaseURL: databaseURL, sql: """
        CREATE TABLE meta (
            key TEXT PRIMARY KEY,
            int_value INTEGER NOT NULL
        );
        INSERT INTO meta (key, int_value) VALUES ('task_version', 8);
        INSERT INTO meta (key, int_value) VALUES ('note_version', 4);

        CREATE TABLE notes (
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

        CREATE TABLE tasks (
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
            deleted_at REAL
        );

        CREATE TABLE calendar_bindings (
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

        CREATE TABLE sync_checkpoints (
            id TEXT PRIMARY KEY,
            task_version_cursor INTEGER NOT NULL,
            calendar_token TEXT,
            updated_at REAL NOT NULL
        );

        INSERT INTO sync_checkpoints (id, task_version_cursor, calendar_token, updated_at)
        VALUES ('era3-checkpoint', 10, 'token-era3', 1700002000);
        """)
    }

    // MARK: - SQL helpers

    private func execSQL(databaseURL: URL, sql: String) throws {
        var dbPointer: OpaquePointer?
        let openCode = sqlite3_open_v2(
            databaseURL.path,
            &dbPointer,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openCode == SQLITE_OK, let dbPointer else {
            throw StorageError.openDatabase(path: databaseURL.path, reason: "Could not create fixture DB")
        }
        defer { sqlite3_close(dbPointer) }
        guard sqlite3_exec(dbPointer, sql, nil, nil, nil) == SQLITE_OK else {
            throw StorageError.executeStatement(reason: String(cString: sqlite3_errmsg(dbPointer)))
        }
    }

    private func tableColumns(table: String, databaseURL: URL) throws -> Set<String> {
        var dbPointer: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &dbPointer,
                              SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let dbPointer else {
            throw StorageError.openDatabase(path: databaseURL.path, reason: "Could not open for column inspection")
        }
        defer { sqlite3_close(dbPointer) }
        let sql = "PRAGMA table_info(\(table));"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(dbPointer, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw StorageError.prepareStatement(reason: String(cString: sqlite3_errmsg(dbPointer)))
        }
        defer { sqlite3_finalize(statement) }
        var columns = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let cstr = sqlite3_column_text(statement, 1) {
                columns.insert(String(cString: cstr))
            }
        }
        return columns
    }

    private func tableNames(databaseURL: URL) throws -> Set<String> {
        var dbPointer: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &dbPointer,
                              SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let dbPointer else {
            throw StorageError.openDatabase(path: databaseURL.path, reason: "Could not open for table inspection")
        }
        defer { sqlite3_close(dbPointer) }
        let sql = "SELECT name FROM sqlite_master WHERE type='table';"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(dbPointer, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw StorageError.prepareStatement(reason: String(cString: sqlite3_errmsg(dbPointer)))
        }
        defer { sqlite3_finalize(statement) }
        var names = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let cstr = sqlite3_column_text(statement, 0) {
                names.insert(String(cString: cstr))
            }
        }
        return names
    }

    private func fetchMetaVersions(databaseURL: URL) throws -> [String: Int64] {
        var dbPointer: OpaquePointer?
        let openCode = sqlite3_open_v2(
            databaseURL.path,
            &dbPointer,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openCode == SQLITE_OK, let dbPointer else {
            throw StorageError.openDatabase(path: databaseURL.path, reason: "Could not open DB for meta assertion")
        }
        defer { sqlite3_close(dbPointer) }

        let sql = "SELECT key, int_value FROM meta;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(dbPointer, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            let reason = String(cString: sqlite3_errmsg(dbPointer))
            throw StorageError.prepareStatement(reason: reason)
        }
        defer { sqlite3_finalize(statement) }

        var versions: [String: Int64] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let keyCString = sqlite3_column_text(statement, 0) else {
                continue
            }
            let key = String(cString: keyCString)
            versions[key] = sqlite3_column_int64(statement, 1)
        }
        return versions
    }
}
