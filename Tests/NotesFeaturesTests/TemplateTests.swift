import NotesDomain
import NotesFeatures
import NotesStorage
import XCTest

final class TemplateTests: XCTestCase {
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

    func testCRUDTemplates() async throws {
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let service = WorkspaceService(store: store)

        let template = try await service.createTemplate(name: "Meeting", body: "## Attendees\n## Agenda\n## Notes")

        var templates = try await service.listTemplates()
        XCTAssertEqual(templates.count, 1)
        XCTAssertEqual(templates[0].name, "Meeting")
        XCTAssertEqual(templates[0].body, "## Attendees\n## Agenda\n## Notes")

        try await service.deleteTemplate(id: template.id)

        templates = try await service.listTemplates()
        XCTAssertEqual(templates.count, 0)
    }

    func testEmptyNameThrows() async throws {
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let service = WorkspaceService(store: store)

        do {
            _ = try await service.createTemplate(name: "   ", body: "body")
            XCTFail("Should throw for empty name")
        } catch StorageError.executeStatement {
            XCTAssert(true)
        }
    }

    func testCreateNoteUsesTemplateBody() async throws {
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let service = WorkspaceService(store: store)

        let template = try await service.createTemplate(name: "Template", body: "Template content")
        let note = try await service.createNote(title: "New Note", body: "", templateID: template.id)

        XCTAssertEqual(note.body, "Template content")
    }

    func testCreateNoteNilTemplateIDUsesEmptyBody() async throws {
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let service = WorkspaceService(store: store)

        let note = try await service.createNote(title: "New Note", body: "", templateID: nil)

        XCTAssertEqual(note.body, "")
    }
}
