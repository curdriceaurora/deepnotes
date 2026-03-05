import XCTest
@testable import NotesFeatures

final class FuzzyMatcherTests: XCTestCase {
    private let matcher = FuzzyMatcher()

    func testSmoke_ExactMatchRanksFirst() {
        let candidates = ["Alpha", "alpha project", "Alphanumeric"]
        let results = matcher.rank(query: "Alpha", candidates: candidates)
        XCTAssertEqual(results.first?.title, "Alpha")
        XCTAssertEqual(results.first?.score, 1000)
    }

    func testPrefixAboveContains() {
        let candidates = ["My Alpha", "Alpha Beta"]
        let results = matcher.rank(query: "Alpha", candidates: candidates)
        XCTAssertEqual(results[0].title, "Alpha Beta")
        XCTAssertEqual(results[0].score, 800)
        XCTAssertEqual(results[1].title, "My Alpha")
        XCTAssertEqual(results[1].score, 600)
    }

    func testContainsAboveFuzzy() {
        let candidates = ["A_B_C", "ABC Project"]
        let results = matcher.rank(query: "ABC", candidates: candidates)
        // "ABC Project" has prefix -> 800
        // "A_B_C" has fuzzy subsequence -> 400
        XCTAssertEqual(results[0].title, "ABC Project")
        XCTAssertEqual(results[1].title, "A_B_C")
        XCTAssertGreaterThan(results[0].score, results[1].score)
    }

    func testSmoke_NonMatchExcluded() {
        let candidates = ["Alpha", "Beta", "Gamma"]
        let results = matcher.rank(query: "Zeta", candidates: candidates)
        XCTAssertTrue(results.isEmpty)
    }

    func testEmptyQueryReturnsAll() {
        let candidates = ["Gamma", "Alpha", "Beta"]
        let results = matcher.rank(query: "", candidates: candidates)
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results.map(\.title), ["Alpha", "Beta", "Gamma"])
    }

    func testSmoke_CaseInsensitive() {
        let candidates = ["ALPHA", "alpha", "Alpha"]
        let results = matcher.rank(query: "alpha", candidates: candidates)
        XCTAssertEqual(results.count, 3)
        XCTAssertTrue(results.allSatisfy { $0.score == 1000 })
    }

    func testStableSortForTies() {
        let candidates = ["Zebra", "Apple", "Mango"]
        let results = matcher.rank(query: "", candidates: candidates)
        XCTAssertEqual(results.map(\.title), ["Apple", "Mango", "Zebra"])
    }

    func testFuzzySubsequence() {
        let candidates = ["Q2 Launch Plan"]
        let results = matcher.rank(query: "qlp", candidates: candidates)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].score, 400)
    }
}
