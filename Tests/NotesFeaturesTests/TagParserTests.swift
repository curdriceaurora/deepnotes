import Testing
@testable import NotesFeatures

@Suite("TagParser")
struct TagParserTests {
    let parser = TagParser()

    @Test("Extracts single tag")
    func extractsSingleTag() {
        let tags = parser.extractTags(from: "Hello #world")
        #expect(tags == ["world"])
    }

    @Test("Extracts multiple tags")
    func extractsMultipleTags() {
        let tags = parser.extractTags(from: "#first some text #second")
        #expect(tags == ["first", "second"])
    }

    @Test("Tags are lowercased")
    func tagsAreLowercased() {
        let tags = parser.extractTags(from: "#MyTag #UPPER")
        #expect(tags == ["mytag", "upper"])
    }

    @Test("Deduplicates tags")
    func deduplicatesTags() {
        let tags = parser.extractTags(from: "#hello #Hello #HELLO")
        #expect(tags == ["hello"])
    }

    @Test("Ignores tags without leading space or start of line")
    func ignoresEmbeddedHash() {
        let tags = parser.extractTags(from: "text#notag but #real")
        #expect(tags == ["real"])
    }

    @Test("Supports slash and hyphen in tags")
    func supportsSlashAndHyphen() {
        let tags = parser.extractTags(from: "#project/sub-task")
        #expect(tags == ["project/sub-task"])
    }

    @Test("Empty body returns empty array")
    func emptyBodyReturnsEmpty() {
        let tags = parser.extractTags(from: "")
        #expect(tags.isEmpty)
    }

    @Test("Tag must start with letter")
    func tagMustStartWithLetter() {
        let tags = parser.extractTags(from: "#123 #a1")
        #expect(tags == ["a1"])
    }

    @Test("Tag at start of line")
    func tagAtStartOfLine() {
        let tags = parser.extractTags(from: "#first\n#second")
        #expect(tags == ["first", "second"])
    }
}
