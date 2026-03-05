import Foundation
import XCTest
@testable import NotesDomain
@testable import NotesStorage

final class SQLiteStoreTests: XCTestCase {
    func testSmoke_UpsertAndFetchNote() async throws {
        let store = try makeStore()

        let note = Note(
            title: "Q2 Launch Plan",
            body: "Roadmap and milestones",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )

        let persisted = try await store.upsertNote(note)
        let fetched = try await store.fetchNote(id: persisted.id)

        XCTAssertEqual(fetched?.title, "Q2 Launch Plan")
        XCTAssertEqual(fetched?.body, "Roadmap and milestones")
        XCTAssertGreaterThan(persisted.version, 0)
    }

    func testSmoke_UpsertAndFetchTask() async throws {
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
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )

        let persisted = try await store.upsertTask(task)
        let fetched = try await store.fetchTask(id: persisted.id)

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.stableID, "task-1")
        XCTAssertEqual(fetched?.title, "Draft launch email")
        XCTAssertGreaterThan(persisted.version, 0)
    }

    func testSmoke_StableIDPreventsDuplicatesAcrossEdits() async throws {
        let store = try makeStore()
        let first = try Task(
            id: UUID(),
            stableID: "task-repeatable-id",
            title: "Initial",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        let persistedFirst = try await store.upsertTask(first)

        let second = try Task(
            id: UUID(),
            stableID: "task-repeatable-id",
            title: "Edited title",
            updatedAt: Date(timeIntervalSince1970: 1_700_010_000),
        )

        let persistedSecond = try await store.upsertTask(second)

        XCTAssertEqual(persistedFirst.id, persistedSecond.id)
        XCTAssertGreaterThan(persistedSecond.version, persistedFirst.version)

        let fetched = try await store.fetchTaskByStableID("task-repeatable-id")
        XCTAssertEqual(fetched?.title, "Edited title")
    }

    func testSmoke_UpsertTaskPersistsKanbanOrder() async throws {
        let store = try makeStore()
        let task = try Task(
            stableID: "task-kanban-order",
            title: "Ordered",
            status: .backlog,
            kanbanOrder: 42.5,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )

        let persisted = try await store.upsertTask(task)
        XCTAssertEqual(persisted.kanbanOrder, 42.5)

        let fetched = try await store.fetchTask(id: persisted.id)
        XCTAssertEqual(fetched?.kanbanOrder, 42.5)
    }

    func testSmoke_TombstoneMarksDeletedAndIncrementsVersion() async throws {
        let store = try makeStore()

        let task = try Task(
            stableID: "task-delete",
            title: "Delete me",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
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
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
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
            Note(title: "Alpha Sprint Plan", body: "Discuss launch checklist and timeline", updatedAt: now),
        )
        _ = try await store.upsertNote(
            Note(title: "Beta", body: "Contains vendor meeting details", updatedAt: now.addingTimeInterval(1)),
        )

        let alphaMatches = try await store.searchNotes(query: "alpha launch", limit: 20)
        XCTAssertEqual(alphaMatches.count, 1)
        XCTAssertEqual(alphaMatches.first?.id, alpha.id)

        try await store.tombstoneNote(id: alpha.id, at: now.addingTimeInterval(2))
        let afterDelete = try await store.searchNotes(query: "alpha", limit: 20)
        XCTAssertTrue(afterDelete.isEmpty)
    }

    func testSearchNotesPhraseModeMatchesOnlyAdjacentTerms() async throws {
        let store = try makeStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let phraseMatch = try await store.upsertNote(
            Note(title: "Release", body: "launch checklist and owners", updatedAt: now),
        )
        _ = try await store.upsertNote(
            Note(title: "Non Phrase", body: "launch prep then checklist later", updatedAt: now.addingTimeInterval(1)),
        )

        let page = try await store.searchNotes(
            query: "launch checklist",
            mode: .phrase,
            limit: 10,
            offset: 0,
        )

        XCTAssertEqual(page.totalCount, 1)
        XCTAssertEqual(page.hits.first?.note.id, phraseMatch.id)
    }

    func testSearchNotesPrefixModeMatchesWordPrefixes() async throws {
        let store = try makeStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let planning = try await store.upsertNote(
            Note(title: "Planning Board", body: "Project plan details", updatedAt: now),
        )
        _ = try await store.upsertNote(
            Note(title: "Execution", body: "Build and ship", updatedAt: now.addingTimeInterval(1)),
        )

        let page = try await store.searchNotes(
            query: "plan",
            mode: .prefix,
            limit: 10,
            offset: 0,
        )

        XCTAssertEqual(page.totalCount, 1)
        XCTAssertEqual(page.hits.first?.note.id, planning.id)
    }

    func testSearchNotesPageIncludesHighlightSnippetAndOffsetPagination() async throws {
        let store = try makeStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let first = try await store.upsertNote(
            Note(title: "One", body: "launch alpha details", updatedAt: now),
        )
        let second = try await store.upsertNote(
            Note(title: "Two", body: "launch beta notes", updatedAt: now.addingTimeInterval(1)),
        )
        let third = try await store.upsertNote(
            Note(title: "Three", body: "launch gamma timeline", updatedAt: now.addingTimeInterval(2)),
        )

        let page1 = try await store.searchNotes(
            query: "launch",
            mode: .smart,
            limit: 2,
            offset: 0,
        )
        XCTAssertEqual(page1.totalCount, 3)
        XCTAssertEqual(page1.hits.count, 2)
        XCTAssertEqual(page1.nextOffset, 2)
        XCTAssertTrue(page1.hits.allSatisfy { $0.snippet?.lowercased().contains("<mark>launch</mark>") == true })

        let page2 = try await store.searchNotes(
            query: "launch",
            mode: .smart,
            limit: 2,
            offset: 2,
        )
        XCTAssertEqual(page2.totalCount, 3)
        XCTAssertEqual(page2.hits.count, 1)
        XCTAssertNil(page2.nextOffset)

        let allIDs = (page1.hits + page2.hits).map(\.note.id)
        XCTAssertEqual(Set(allIDs), Set([first.id, second.id, third.id]))
    }

    private func makeStore() throws -> SQLiteStore {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-engine-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try SQLiteStore(databaseURL: folder.appendingPathComponent("notes.sqlite"))
    }
}
