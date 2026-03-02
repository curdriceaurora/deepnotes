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
