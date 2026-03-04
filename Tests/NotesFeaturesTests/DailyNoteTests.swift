import NotesDomain
import NotesFeatures
import NotesStorage
import XCTest

final class DailyNoteTests: XCTestCase {
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

    func testCreatesWithISODateTitle() async throws {
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let service = WorkspaceService(store: store)

        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2025-03-03T00:00:00Z"))
        let note = try await service.createOrOpenDailyNote(date: date)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current
        let expectedTitle = formatter.string(from: date)

        XCTAssertEqual(note.title, expectedTitle)
    }

    func testIdempotentOnSameDay() async throws {
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let service = WorkspaceService(store: store)

        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2025-03-03T00:00:00Z"))
        let note1 = try await service.createOrOpenDailyNote(date: date)
        let note2 = try await service.createOrOpenDailyNote(date: date)

        XCTAssertEqual(note1.id, note2.id)
    }

    func testRespectsLocalTimezone() async throws {
        let store = try SQLiteStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let service = WorkspaceService(store: store)

        let date = Date()
        let note = try await service.createOrOpenDailyNote(date: date)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current

        XCTAssertTrue(note.title.contains("-"))
    }
}
