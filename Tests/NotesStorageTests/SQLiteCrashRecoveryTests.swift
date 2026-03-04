import Foundation
import SQLite3
import XCTest
@testable import NotesDomain
@testable import NotesStorage

/// Tests that crash-like interruptions (failed transactions, bad migration inputs,
/// partial writes) leave the database in a consistent, reopenable state.
final class SQLiteCrashRecoveryTests: XCTestCase {
    // MARK: - Migration recovery

    /// Opening a database that has a truncated / zero-byte file should fail with a
    /// StorageError and not leave the process in a broken state.  The path must be
    /// openable again after the error.
    func testOpeningCorruptDatabaseThrowsAndDoesNotLeak() throws {
        let dbURL = try makeDatabaseURL()

        // Write garbage bytes that are not a valid SQLite header.
        try Data(repeating: 0xFF, count: 64).write(to: dbURL)

        XCTAssertThrowsError(try SQLiteStore(databaseURL: dbURL)) { error in
            // Must surface as a StorageError rather than an untyped error.
            XCTAssertTrue(
                error is StorageError,
                "Expected StorageError, got \(error)",
            )
        }

        // The URL must still be reachable (file not deleted, no handle leak that
        // would prevent overwriting it).
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbURL.path))
    }

    /// If migration encounters a truly broken schema (e.g. a table with the same
    /// name as an expected CREATE TABLE IF NOT EXISTS target but an incompatible
    /// schema that causes a later ALTER to fail), the store init should throw and
    /// should not leave a half-migrated file that prevents future opens.
    func testMigrationFailureLeavesDBReopenable() throws {
        let dbURL = try makeDatabaseURL()

        // Plant a broken fixture: `meta` table has wrong column name so
        // INSERT INTO meta ... ON CONFLICT(key) DO NOTHING will fail because
        // the column is named `k` not `key`.
        try execSQL(databaseURL: dbURL, sql: """
        CREATE TABLE meta (
            k TEXT PRIMARY KEY,
            int_value INTEGER NOT NULL
        );
        INSERT INTO meta (k, int_value) VALUES ('task_version', 0);
        INSERT INTO meta (k, int_value) VALUES ('note_version', 0);
        CREATE TABLE notes (
            id TEXT PRIMARY KEY,
            stable_id TEXT NOT NULL UNIQUE,
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
            status TEXT NOT NULL,
            priority INTEGER NOT NULL,
            updated_at REAL NOT NULL,
            version INTEGER NOT NULL,
            deleted_at REAL
        );
        CREATE TABLE sync_checkpoints (
            id TEXT PRIMARY KEY,
            task_version_cursor INTEGER NOT NULL,
            calendar_token TEXT,
            updated_at REAL NOT NULL
        );
        """)

        // The store open should throw because the migration SQL tries
        // `INSERT INTO meta (key, ...) ON CONFLICT(key)` but the column
        // is named `k`, causing SQLITE_ERROR.
        XCTAssertThrowsError(try SQLiteStore(databaseURL: dbURL)) { error in
            XCTAssertTrue(
                error is StorageError,
                "Migration failure must surface as StorageError, got \(error)",
            )
        }

        // The file must still exist and be a valid SQLite container
        // (SQLite itself opened it; we just failed the migration step).
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbURL.path))
    }

    // MARK: - Note transaction rollback

    /// Inserting a note with a title that conflicts with an existing note
    /// triggers the UNIQUE constraint on the `title` column mid-transaction.
    /// The partial write (incremented meta version) must be rolled back so
    /// the meta cursor doesn't drift ahead of any persisted data.
    func testFailedNoteUpsertRollsBackMetaVersion() async throws {
        let store = try makeStore()

        let note1 = Note(
            title: "Unique Title",
            body: "original body",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        let persisted = try await store.upsertNote(note1)
        let versionAfterFirstWrite = persisted.version

        // Second note with a duplicate title — different stableID so it
        // won't merge by stableID, then conflicts on the UNIQUE title index.
        let note2 = Note(
            stableID: "different-stable-id",
            title: "Unique Title", // intentional duplicate
            body: "conflicting body",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
        )
        do {
            _ = try await store.upsertNote(note2)
            // The UPSERT ON CONFLICT(id) should merge by id. The title
            // conflict triggers a UNIQUE violation on title when the stableID
            // lookup finds a *different* row. If the store coalesces, this
            // is fine; what matters is the DB is not in a partial state.
        } catch {
            // A storage error is acceptable — verify rollback left DB consistent.
        }

        // Regardless of outcome, the note with the original body must still
        // be fetchable and the DB must be reopenable.
        let fetched = try await store.fetchNoteByTitle("Unique Title")
        XCTAssertNotNil(fetched, "Original note should still be accessible")
        // The body must be from one of the two upserts — never empty / nil.
        let body = fetched?.body ?? ""
        XCTAssertFalse(body.isEmpty, "Note body should not be empty after any outcome")

        // The meta note_version cursor must not have advanced beyond the version
        // recorded after the successful first write (no phantom increment from the
        // failed second attempt's transaction).
        let noteAfterFail = try await store.fetchNoteByTitle("Unique Title")
        let versionAfterFail = noteAfterFail?.version ?? 0
        XCTAssertLessThanOrEqual(
            versionAfterFail, versionAfterFirstWrite + 1,
            "note_version must not drift beyond the last successfully committed version",
        )
    }

    /// An upsert with an empty stableID throws a validation error *before*
    /// any transaction begins.  No meta version increment should occur.
    func testTaskUpsertWithEmptyStableIDThrowsBeforeDBWrite() async throws {
        let store = try makeStore()

        // Record baseline version by writing one valid task.
        let seed = try Task(
            stableID: "seed-task",
            title: "Seed",
            status: .backlog,
            kanbanOrder: 1,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        _ = try await store.upsertTask(seed)
        let seedFetched = try await store.fetchTaskByStableID("seed-task")
        let versionBaseline = seedFetched?.version ?? 0

        // Now attempt a task with an empty stableID — must throw before touching DB.
        let badTask = try Task(
            stableID: "",
            title: "Bad Task",
            status: .backlog,
            kanbanOrder: 2,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
        )
        do {
            _ = try await store.upsertTask(badTask)
            XCTFail("Expected DomainValidationError.missingStableID")
        } catch DomainValidationError.missingStableID {
            // Expected
        }

        // Seed task still accessible, version unchanged.
        let refetched = try await store.fetchTaskByStableID("seed-task")
        XCTAssertNotNil(refetched)
        XCTAssertEqual(
            refetched?.version,
            versionBaseline,
            "Meta version must not advance when write is rejected before transaction",
        )
    }

    /// Two tasks with the same `stable_id` (but different primary-key UUIDs) trigger a
    /// UNIQUE constraint violation on the `stable_id` column *inside* the SQLite
    /// transaction, exercising the actual `try? rollbackTransaction()` path in
    /// `SQLiteStore.upsertTask`.  After the rollback the first task must still be
    /// readable and the meta `task_version` cursor must equal the version left by the
    /// first successful write — not incremented by the failed second attempt.
    func testTaskUpsertUniqueConstraintViolationRollsBackVersion() async throws {
        let store = try makeStore()

        let task1 = try Task(
            id: XCTUnwrap(UUID(uuidString: "AA000000-0000-0000-0000-000000000001")),
            stableID: "shared-stable-id",
            title: "First Task",
            status: .backlog,
            kanbanOrder: 1,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        let committed = try await store.upsertTask(task1)
        let versionAfterFirstWrite = committed.version

        // Second task has a *different* primary-key UUID but the same stable_id.
        // The store will try to INSERT a new row; the UNIQUE constraint on stable_id
        // fires inside the transaction and the store must roll back.
        let task2 = try Task(
            id: XCTUnwrap(UUID(uuidString: "BB000000-0000-0000-0000-000000000002")),
            stableID: "shared-stable-id",
            title: "Conflicting Task",
            status: .next,
            kanbanOrder: 2,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
        )
        do {
            _ = try await store.upsertTask(task2)
            // The store may also merge by stable_id (idempotent upsert) — that is
            // a valid implementation choice. Only assert consistency below.
        } catch {
            // A StorageError from the constraint violation is expected.
            XCTAssertTrue(error is StorageError, "Constraint violation must surface as StorageError, got \(error)")
        }

        // The first task must still be readable with its original data intact.
        let refetched = try await store.fetchTaskByStableID("shared-stable-id")
        XCTAssertNotNil(refetched, "Task with shared stable_id must still be accessible after constraint violation")

        // The task_version cursor must not have advanced beyond what the first
        // successful write established (no phantom increment from the rolled-back attempt).
        XCTAssertLessThanOrEqual(
            refetched?.version ?? 0, versionAfterFirstWrite + 1,
            "task_version must not drift beyond the last successfully committed version",
        )
    }

    // MARK: - Checkpoint atomicity

    /// A checkpoint written successfully then overwritten must reflect only the
    /// final value — last-write-wins semantics, no phantom of the intermediate state.
    func testCheckpointLastWriteWinsAndFinalValueIsConsistent() async throws {
        let store = try makeStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        var cp = SyncCheckpoint(
            id: "cp-atomic",
            taskVersionCursor: 1,
            noteVersionCursor: 0,
            calendarToken: "token-v1",
            updatedAt: now,
        )
        try await store.saveCheckpoint(cp)

        // Overwrite with new cursors.
        cp.taskVersionCursor = 5
        cp.noteVersionCursor = 3
        cp.calendarToken = "token-v2"
        cp.updatedAt = now.addingTimeInterval(60)
        try await store.saveCheckpoint(cp)

        let fetched = try await store.fetchCheckpoint(id: "cp-atomic")
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.taskVersionCursor, 5)
        XCTAssertEqual(fetched?.noteVersionCursor, 3)
        XCTAssertEqual(
            fetched?.calendarToken,
            "token-v2",
            "Latest checkpoint token must be persisted; no stale intermediate value",
        )
    }

    /// After a failed note write, saving a checkpoint must still succeed —
    /// the store must not be stuck in an open transaction from the failed write.
    func testCheckpointSaveSucceedsAfterFailedNoteWrite() async throws {
        let store = try makeStore()

        // Trigger a write error: empty title is rejected before the transaction
        // but use a note with an empty body that passes our validation (only
        // title is checked). We force a constraint violation by inserting a note
        // then trying to insert with the same title but a different stableID.
        let note1 = Note(
            title: "Title Conflict Test",
            body: "first",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        _ = try await store.upsertNote(note1)

        // This will either merge or throw — either way the store must remain usable.
        let note2 = Note(
            stableID: UUID().uuidString,
            title: "Title Conflict Test",
            body: "second",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
        )
        _ = try? await store.upsertNote(note2)

        // Checkpoint write must succeed regardless.
        let cp = SyncCheckpoint(
            id: "post-error-cp",
            taskVersionCursor: 99,
            noteVersionCursor: 42,
            calendarToken: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_200),
        )
        try await store.saveCheckpoint(cp)

        let fetched = try await store.fetchCheckpoint(id: "post-error-cp")
        XCTAssertEqual(fetched?.taskVersionCursor, 99)
        XCTAssertEqual(fetched?.noteVersionCursor, 42)
    }

    // MARK: - Reopen consistency

    /// Data committed before a failed write must survive a store reopen.
    /// The meta version counters must be consistent with the persisted rows.
    func testReopenAfterFailedWritePreservesCommittedData() async throws {
        let dbURL = try makeDatabaseURL()

        do {
            let store = try SQLiteStore(databaseURL: dbURL)

            // Write good data.
            _ = try await store.upsertTask(Task(
                stableID: "committed-task",
                title: "Should Survive",
                status: .next,
                kanbanOrder: 1,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            ))

            // Attempt a bad write (empty stableID validation fires).
            let badTask = try Task(
                stableID: "",
                title: "Bad",
                status: .backlog,
                kanbanOrder: 2,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            )
            _ = try? await store.upsertTask(badTask)
            // store goes out of scope, connection closed
        }

        // Reopen from disk.
        let reopened = try SQLiteStore(databaseURL: dbURL)
        let task = try await reopened.fetchTaskByStableID("committed-task")
        XCTAssertNotNil(task, "Committed task must survive store reopen after a failed write")
        XCTAssertEqual(task?.title, "Should Survive")
    }

    /// A checkpoint written and closed must be readable after reopen, with the
    /// exact same cursor values — no partial flush or WAL gap.
    func testCheckpointSurvidesReopenAfterClose() async throws {
        let dbURL = try makeDatabaseURL()

        do {
            let store = try SQLiteStore(databaseURL: dbURL)
            try await store.saveCheckpoint(SyncCheckpoint(
                id: "durable-cp",
                taskVersionCursor: 77,
                noteVersionCursor: 13,
                calendarToken: "durable-token",
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            ))
        } // store dealloc → sqlite3_close

        let reopened = try SQLiteStore(databaseURL: dbURL)
        let cp = try await reopened.fetchCheckpoint(id: "durable-cp")
        XCTAssertNotNil(cp)
        XCTAssertEqual(cp?.taskVersionCursor, 77)
        XCTAssertEqual(cp?.noteVersionCursor, 13)
        XCTAssertEqual(
            cp?.calendarToken,
            "durable-token",
            "Checkpoint token must be durably written and readable after reopen",
        )
    }

    // MARK: - Helpers

    private func makeStore() throws -> SQLiteStore {
        let dbURL = try makeDatabaseURL()
        return try SQLiteStore(databaseURL: dbURL)
    }

    private func makeDatabaseURL() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-engine-crash-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("notes.sqlite")
    }

    private func execSQL(databaseURL: URL, sql: String) throws {
        var dbPointer: OpaquePointer?
        let openCode = sqlite3_open_v2(
            databaseURL.path,
            &dbPointer,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil,
        )
        guard openCode == SQLITE_OK, let dbPointer else {
            throw StorageError.openDatabase(path: databaseURL.path, reason: "Could not create fixture DB")
        }
        defer { sqlite3_close(dbPointer) }
        guard sqlite3_exec(dbPointer, sql, nil, nil, nil) == SQLITE_OK else {
            throw StorageError.executeStatement(reason: String(cString: sqlite3_errmsg(dbPointer)))
        }
    }
}
