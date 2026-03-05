import NotesDomain
import NotesStorage
import XCTest

final class SQLiteKanbanColumnTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSmoke_FetchColumnsReturnsSeededDefaults() async throws {
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("test.db"))

        let columns = try await store.fetchColumns()

        XCTAssertEqual(columns.count, 5)
        XCTAssertEqual(columns[0].builtInStatus, .backlog)
        XCTAssertEqual(columns[1].builtInStatus, .next)
        XCTAssertEqual(columns[2].builtInStatus, .doing)
        XCTAssertEqual(columns[3].builtInStatus, .waiting)
        XCTAssertEqual(columns[4].builtInStatus, .done)
        XCTAssertEqual(columns.map(\.position), [0, 1, 2, 3, 4])
    }

    func testSmoke_UpsertCustomColumn() async throws {
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("test.db"))

        let column = KanbanColumn(title: "Review", position: 5, wipLimit: 3, colorHex: "#FF5500")
        let persisted = try await store.upsertColumn(column)

        let columns = try await store.fetchColumns()
        XCTAssertEqual(columns.count, 6)
        let custom = columns.first(where: { $0.id == persisted.id })
        XCTAssertNotNil(custom)
        XCTAssertEqual(custom?.title, "Review")
        XCTAssertEqual(custom?.wipLimit, 3)
        XCTAssertEqual(custom?.colorHex, "#FF5500")
        XCTAssertNil(custom?.builtInStatus)
    }

    func testSmoke_DeleteCustomColumn() async throws {
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("test.db"))

        let column = KanbanColumn(title: "Custom", position: 5)
        let persisted = try await store.upsertColumn(column)
        try await store.deleteColumn(id: persisted.id)

        let columns = try await store.fetchColumns()
        XCTAssertEqual(columns.count, 5) // Only built-in remain
        XCTAssertFalse(columns.contains(where: { $0.id == persisted.id }))
    }

    func testDeleteBuiltInColumnGuarded() async throws {
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("test.db"))

        let columns = try await store.fetchColumns()
        let backlogColumn = try XCTUnwrap(columns.first(where: { $0.builtInStatus == .backlog }))

        // Should no-op (built-in columns are protected)
        try await store.deleteColumn(id: backlogColumn.id)

        let afterDelete = try await store.fetchColumns()
        XCTAssertEqual(afterDelete.count, 5)
        XCTAssertTrue(afterDelete.contains(where: { $0.id == backlogColumn.id }))
    }

    func testTaskLabelsJSONRoundTrip() async throws {
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("test.db"))

        let labels = [TaskLabel(name: "Bug", colorHex: "#FF0000"), TaskLabel(name: "Feature", colorHex: "#00FF00")]
        var task = try Task(stableID: "label-test", title: "Labeled task", updatedAt: Date(), labels: labels)
        task = try await store.upsertTask(task)

        let fetched = try await store.fetchTask(id: task.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.labels.count, 2)
        XCTAssertEqual(fetched?.labels.first?.name, "Bug")
        XCTAssertEqual(fetched?.labels.first?.colorHex, "#FF0000")
        XCTAssertEqual(fetched?.labels.last?.name, "Feature")
    }

    func testSmoke_TaskKanbanColumnIDPersistence() async throws {
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("test.db"))

        let column = KanbanColumn(title: "Custom", position: 5)
        let persisted = try await store.upsertColumn(column)

        var task = try Task(stableID: "col-test", title: "Task in custom col", updatedAt: Date(), kanbanColumnID: persisted.id)
        task = try await store.upsertTask(task)

        let fetched = try await store.fetchTask(id: task.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.kanbanColumnID, persisted.id)
    }
}
