import XCTest
@testable import NotesUI

final class MarkdownRendererTests: XCTestCase {
    let renderer = MarkdownRenderer()

    private func text(of run: AttributedString.Runs.Run, in str: AttributedString) -> String {
        String(str[run.range].characters)
    }

    func testSmoke_HeadingIsBold() {
        let result = renderer.render("# Hello", noteTitles: [])
        let runs = Array(result.runs)
        XCTAssertFalse(runs.isEmpty)
        let firstPresentation = runs.first?.inlinePresentationIntent
        XCTAssertNotNil(firstPresentation)
        XCTAssertTrue(firstPresentation?.contains(.stronglyEmphasized) == true)
    }

    func testBoldText() {
        let result = renderer.render("**bold**", noteTitles: [])
        let runs = Array(result.runs)
        let boldRun = runs.first { text(of: $0, in: result) == "bold" }
        XCTAssertNotNil(boldRun)
        XCTAssertTrue(boldRun?.inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
    }

    func testItalicText() {
        let result = renderer.render("*italic*", noteTitles: [])
        let runs = Array(result.runs)
        let italicRun = runs.first { text(of: $0, in: result) == "italic" }
        XCTAssertNotNil(italicRun)
        XCTAssertTrue(italicRun?.inlinePresentationIntent?.contains(.emphasized) == true)
    }

    func testSmoke_BulletList() {
        let result = renderer.render("- Item A\n- Item B", noteTitles: [])
        let fullText = String(result.characters)
        XCTAssertTrue(fullText.contains("\u{2022}"))
        XCTAssertTrue(fullText.contains("Item A"))
        XCTAssertTrue(fullText.contains("Item B"))
    }

    func testSmoke_WikiLinkWithExistingTitle() {
        let result = renderer.render("See [[Alpha]] here", noteTitles: ["Alpha"])
        let runs = Array(result.runs)
        let linkRun = runs.first { $0.link != nil }
        XCTAssertNotNil(linkRun)
        XCTAssertEqual(linkRun?.link?.scheme, "deepnotes")
        XCTAssertEqual(linkRun?.link?.host, "wikilink")
    }

    func testWikiLinkNonExistentTitleIsDimmed() {
        let result = renderer.render("See [[Missing]] here", noteTitles: ["Alpha"])
        let runs = Array(result.runs)
        let linkRun = runs.first { $0.link != nil }
        XCTAssertNotNil(linkRun)
        XCTAssertNotNil(linkRun?.foregroundColor)
    }

    func testSmoke_CodeSpanMonospaced() {
        let result = renderer.render("Use `code` here", noteTitles: [])
        let runs = Array(result.runs)
        let codeRun = runs.first { text(of: $0, in: result) == "code" }
        XCTAssertNotNil(codeRun)
        XCTAssertTrue(codeRun?.inlinePresentationIntent?.contains(.code) == true)
    }

    func testSmoke_EmptyStringReturnsEmptyAttributedString() {
        let result = renderer.render("", noteTitles: [])
        XCTAssertTrue(result.characters.isEmpty)
    }

    func testOrderedList() {
        let result = renderer.render("1. First\n2. Second", noteTitles: [])
        let fullText = String(result.characters)
        XCTAssertTrue(fullText.contains("1."))
        XCTAssertTrue(fullText.contains("First"))
        XCTAssertTrue(fullText.contains("Second"))
    }

    func testWikiLinkWithAlias() {
        let result = renderer.render("See [[Alpha|My Alias]]", noteTitles: ["Alpha"])
        let fullText = String(result.characters)
        XCTAssertTrue(fullText.contains("My Alias"))
    }

    func testThematicBreak() {
        let result = renderer.render("Above\n\n---\n\nBelow", noteTitles: [])
        let fullText = String(result.characters)
        XCTAssertTrue(fullText.contains("---"))
    }

    func testMultipleWikiLinks() {
        let result = renderer.render("[[Alpha]] and [[Beta]]", noteTitles: ["Alpha", "Beta"])
        let runs = Array(result.runs)
        let linkRuns = runs.filter { $0.link != nil }
        XCTAssertEqual(linkRuns.count, 2)
    }

    func testPlainTextWithNoMarkdown() {
        let result = renderer.render("Hello world", noteTitles: [])
        let fullText = String(result.characters)
        XCTAssertTrue(fullText.contains("Hello world"))
    }

    func testCodeBlock() {
        let result = renderer.render("```\nlet x = 1\n```", noteTitles: [])
        let runs = Array(result.runs)
        let codeRun = runs.first { $0.inlinePresentationIntent?.contains(.code) == true }
        XCTAssertNotNil(codeRun)
    }

    func testMarkdownLink() {
        let result = renderer.render("[Click here](https://example.com)", noteTitles: [])
        let runs = Array(result.runs)
        let linkRun = runs.first { $0.link != nil }
        XCTAssertNotNil(linkRun)
        XCTAssertEqual(linkRun?.link?.absoluteString, "https://example.com")
    }
}
