import XCTest
import NotesDomain
import NotesFeatures
import NotesStorage

final class GraphEdgesTests: XCTestCase {
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

    func testResolvesWikiLinksToEdges() async throws {
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let service = WorkspaceService(store: store)

        let noteA = try await service.createNote(title: "Note A", body: "")
        let noteB = try await service.createNote(title: "Note B", body: "")
        let noteC = try await service.createNote(title: "Note C", body: "")

        _ = try await service.updateNote(id: noteA.id, title: "Note A", body: "[[Note B]] [[Note C]]")

        let edges = try await service.graphEdges()

        XCTAssertEqual(edges.count, 2)
        let fromAEdges = edges.filter { $0.from == noteA.id }
        XCTAssertEqual(fromAEdges.count, 2)
    }

    func testExcludesSelfLinks() async throws {
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let service = WorkspaceService(store: store)

        let noteA = try await service.createNote(title: "Note A", body: "[[Note A]]")

        let edges = try await service.graphEdges()

        let selfLinks = edges.filter { $0.from == $0.to }
        XCTAssertEqual(selfLinks.count, 0)
    }

    func testExcludesUnresolvableLinks() async throws {
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let service = WorkspaceService(store: store)

        let noteA = try await service.createNote(title: "Note A", body: "[[Nonexistent Note]]")

        let edges = try await service.graphEdges()

        XCTAssertEqual(edges.count, 0)
    }

    func testEmptyStoreReturnsNoEdges() async throws {
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let service = WorkspaceService(store: store)

        let edges = try await service.graphEdges()

        XCTAssertEqual(edges.count, 0)
    }
}
