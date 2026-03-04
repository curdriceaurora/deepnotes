import XCTest
import NotesDomain
import NotesFeatures
import NotesStorage

final class UnlinkedMentionsTests: XCTestCase {
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

    func testDetectsPlainTextMentions() async throws {
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let service = WorkspaceService(store: store)

        let targetNote = try await service.createNote(title: "Target Note", body: "")
        let sourceNote = try await service.createNote(title: "Source Note", body: "This mentions Target Note in plain text")

        let mentions = try await service.unlinkedMentions(for: targetNote.id)

        XCTAssertEqual(mentions.count, 1)
        XCTAssertEqual(mentions[0].sourceNoteID, sourceNote.id)
        XCTAssertEqual(mentions[0].sourceTitle, "Source Note")
    }

    func testExcludesExistingBacklinks() async throws {
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let service = WorkspaceService(store: store)

        let targetNote = try await service.createNote(title: "Target Note", body: "")
        let sourceNote = try await service.createNote(title: "Source Note", body: "[[Target Note]] and Target Note")

        let mentions = try await service.unlinkedMentions(for: targetNote.id)

        XCTAssertEqual(mentions.count, 0, "Should exclude existing backlinks")
    }

    func testCaseInsensitiveMentions() async throws {
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let service = WorkspaceService(store: store)

        let targetNote = try await service.createNote(title: "Target Note", body: "")
        let sourceNote = try await service.createNote(title: "Source Note", body: "This mentions target note in lowercase")

        let mentions = try await service.unlinkedMentions(for: targetNote.id)

        XCTAssertEqual(mentions.count, 1)
        XCTAssertEqual(mentions[0].sourceNoteID, sourceNote.id)
    }

    func testLinkMentionReplaceFirstMatch() async throws {
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let service = WorkspaceService(store: store)

        let targetNote = try await service.createNote(title: "Target Note", body: "")
        let sourceNote = try await service.createNote(title: "Source Note", body: "This mentions Target Note and Target Note again")

        let updated = try await service.linkMention(in: sourceNote.id, targetTitle: "Target Note")

        XCTAssertTrue(updated.body.contains("[[Target Note]]"))
        XCTAssertTrue(updated.body.contains("Target Note again"))
        let linkCount = updated.body.components(separatedBy: "[[").count - 1
        XCTAssertEqual(linkCount, 1, "Should replace only first match")
    }
}
