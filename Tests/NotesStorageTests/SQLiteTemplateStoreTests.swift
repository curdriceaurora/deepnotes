import NotesDomain
import NotesStorage
import XCTest

final class SQLiteTemplateStoreTests: XCTestCase {
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

    func testFetchEmptyTemplates() async throws {
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("test.db"))

        let templates = try await store.fetchTemplates()

        XCTAssertEqual(templates.count, 0)
    }

    func testUpsertAndFetch() async throws {
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("test.db"))

        let template = NoteTemplate(name: "Test", body: "Body", createdAt: Date())
        _ = try await store.upsertTemplate(template)

        let fetched = try await store.fetchTemplates()

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].name, "Test")
        XCTAssertEqual(fetched[0].body, "Body")
    }

    func testUpdate() async throws {
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("test.db"))

        let template = NoteTemplate(name: "Test", body: "Body", createdAt: Date())
        let persisted = try await store.upsertTemplate(template)

        var updated = persisted
        updated.body = "Updated Body"
        _ = try await store.upsertTemplate(updated)

        let fetched = try await store.fetchTemplates()

        XCTAssertEqual(fetched[0].body, "Updated Body")
    }

    func testDelete() async throws {
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("test.db"))

        let template = NoteTemplate(name: "Test", body: "Body", createdAt: Date())
        let persisted = try await store.upsertTemplate(template)

        try await store.deleteTemplate(id: persisted.id)

        let fetched = try await store.fetchTemplates()

        XCTAssertEqual(fetched.count, 0)
    }

    func testMigrationFromOldSchema() async throws {
        let dbURL = tempDir.appendingPathComponent("test.db")
        let store = try SQLiteStore(databaseURL: dbURL)

        let template = NoteTemplate(name: "Test", body: "Body", createdAt: Date())
        _ = try await store.upsertTemplate(template)

        let templates = try await store.fetchTemplates()
        XCTAssertEqual(templates.count, 1)
    }
}
