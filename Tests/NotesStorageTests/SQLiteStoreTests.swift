import XCTest
import Foundation
@testable import NotesStorage
@testable import NotesDomain

final class SQLiteStoreTests: XCTestCase {
    func testUpsertAndFetchNote() async throws {
        let store = try makeStore()

        let note = Note(
            title: "Q2 Launch Plan",
            body: "Roadmap and milestones",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let persisted = try await store.upsertNote(note)
        let fetched = try await store.fetchNote(id: persisted.id)

        XCTAssertEqual(fetched?.title, "Q2 Launch Plan")
        XCTAssertEqual(fetched?.body, "Roadmap and milestones")
        XCTAssertGreaterThan(persisted.version, 0)
    }

    func testUpsertAndFetchTask() async throws {
        let store = try makeStore()

        let task = try Task(
            stableID: "task-1",
            title: "Draft launch email",
            details: "Use [[Q2 Launch Plan]] links.",
            dueStart: Date(timeIntervalSince1970: 1_700_000_000),
            dueEnd: Date(timeIntervalSince1970: 1_700_000_900),
            status: .next,
            priority: 3,
            recurrenceRule: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let persisted = try await store.upsertTask(task)
        let fetched = try await store.fetchTask(id: persisted.id)

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.stableID, "task-1")
        XCTAssertEqual(fetched?.title, "Draft launch email")
        XCTAssertGreaterThan(persisted.version, 0)
    }

    func testStableIDPreventsDuplicatesAcrossEdits() async throws {
        let store = try makeStore()
        let first = try Task(
            id: UUID(),
            stableID: "task-repeatable-id",
            title: "Initial",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let persistedFirst = try await store.upsertTask(first)

        let second = try Task(
            id: UUID(),
            stableID: "task-repeatable-id",
            title: "Edited title",
            updatedAt: Date(timeIntervalSince1970: 1_700_010_000)
        )

        let persistedSecond = try await store.upsertTask(second)

        XCTAssertEqual(persistedFirst.id, persistedSecond.id)
        XCTAssertGreaterThan(persistedSecond.version, persistedFirst.version)

        let fetched = try await store.fetchTaskByStableID("task-repeatable-id")
        XCTAssertEqual(fetched?.title, "Edited title")
    }

    func testUpsertTaskPersistsKanbanOrder() async throws {
        let store = try makeStore()
        let task = try Task(
            stableID: "task-kanban-order",
            title: "Ordered",
            status: .backlog,
            kanbanOrder: 42.5,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let persisted = try await store.upsertTask(task)
        XCTAssertEqual(persisted.kanbanOrder, 42.5)

        let fetched = try await store.fetchTask(id: persisted.id)
        XCTAssertEqual(fetched?.kanbanOrder, 42.5)
    }

    func testTombstoneMarksDeletedAndIncrementsVersion() async throws {
        let store = try makeStore()

        let task = try Task(
            stableID: "task-delete",
            title: "Delete me",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let persisted = try await store.upsertTask(task)

        let tombstoneDate = Date(timeIntervalSince1970: 1_700_020_000)
        try await store.tombstoneTask(id: persisted.id, at: tombstoneDate)

        let fetched = try await store.fetchTask(id: persisted.id)
        XCTAssertEqual(fetched?.deletedAt, tombstoneDate)
        XCTAssertTrue((fetched?.version ?? 0) > persisted.version)

        let changed = try await store.fetchTasksUpdated(afterVersion: persisted.version, limit: 10)
        XCTAssertEqual(changed.count, 1)
        XCTAssertEqual(changed.first?.id, persisted.id)
        XCTAssertEqual(changed.first?.deletedAt, tombstoneDate)
    }

    func testFetchTasksIncludeDeletedFlag() async throws {
        let store = try makeStore()

        let task = try Task(
            stableID: "task-delete-visible",
            title: "Needs cleanup",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let persisted = try await store.upsertTask(task)
        try await store.tombstoneTask(id: persisted.id, at: Date(timeIntervalSince1970: 1_700_005_000))

        let activeTasks = try await store.fetchTasks(includeDeleted: false)
        let allTasks = try await store.fetchTasks(includeDeleted: true)

        XCTAssertTrue(activeTasks.isEmpty)
        XCTAssertEqual(allTasks.count, 1)
        XCTAssertEqual(allTasks.first?.id, persisted.id)
    }

    func testSearchNotesUsesFTSAndExcludesDeleted() async throws {
        let store = try makeStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let alpha = try await store.upsertNote(
            Note(title: "Alpha Sprint Plan", body: "Discuss launch checklist and timeline", updatedAt: now)
        )
        _ = try await store.upsertNote(
            Note(title: "Beta", body: "Contains vendor meeting details", updatedAt: now.addingTimeInterval(1))
        )

        let alphaMatches = try await store.searchNotes(query: "alpha launch", limit: 20)
        XCTAssertEqual(alphaMatches.count, 1)
        XCTAssertEqual(alphaMatches.first?.id, alpha.id)

        try await store.tombstoneNote(id: alpha.id, at: now.addingTimeInterval(2))
        let afterDelete = try await store.searchNotes(query: "alpha", limit: 20)
        XCTAssertTrue(afterDelete.isEmpty)
    }

    private func makeStore() throws -> SQLiteStore {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-engine-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try SQLiteStore(databaseURL: folder.appendingPathComponent("notes.sqlite"))
    }
}
