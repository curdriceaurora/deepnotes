import XCTest
@testable import NotesFeatures

final class TagParserTests: XCTestCase {
    private let parser = TagParser()

    func testExtractsSingleTag() {
        let tags = parser.extractTags(from: "Hello #world")
        XCTAssertEqual(tags, ["world"])
    }

    func testExtractsMultipleTags() {
        let tags = parser.extractTags(from: "#first some text #second")
        XCTAssertEqual(tags, ["first", "second"])
    }

    func testTagsAreLowercased() {
        let tags = parser.extractTags(from: "#MyTag #UPPER")
        XCTAssertEqual(tags, ["mytag", "upper"])
    }

    func testDeduplicatesTags() {
        let tags = parser.extractTags(from: "#hello #Hello #HELLO")
        XCTAssertEqual(tags, ["hello"])
    }

    func testIgnoresEmbeddedHash() {
        let tags = parser.extractTags(from: "text#notag but #real")
        XCTAssertEqual(tags, ["real"])
    }

    func testSupportsSlashAndHyphen() {
        let tags = parser.extractTags(from: "#project/sub-task")
        XCTAssertEqual(tags, ["project/sub-task"])
    }

    func testEmptyBodyReturnsEmpty() {
        let tags = parser.extractTags(from: "")
        XCTAssertTrue(tags.isEmpty)
    }

    func testTagMustStartWithLetter() {
        let tags = parser.extractTags(from: "#123 #a1")
        XCTAssertEqual(tags, ["a1"])
    }

    func testTagAtStartOfLine() {
        let tags = parser.extractTags(from: "#first\n#second")
        XCTAssertEqual(tags, ["first", "second"])
    }
}
