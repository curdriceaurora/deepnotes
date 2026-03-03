import Testing
@testable import NotesFeatures

@Suite("FuzzyMatcher")
struct FuzzyMatcherTests {
    let matcher = FuzzyMatcher()

    @Test("Exact match ranks first")
    func exactMatchRanksFirst() {
        let candidates = ["Alpha", "alpha project", "Alphanumeric"]
        let results = matcher.rank(query: "Alpha", candidates: candidates)
        #expect(results.first?.title == "Alpha")
        #expect(results.first?.score == 1000)
    }

    @Test("Prefix ranks above contains")
    func prefixAboveContains() {
        let candidates = ["My Alpha", "Alpha Beta"]
        let results = matcher.rank(query: "Alpha", candidates: candidates)
        #expect(results[0].title == "Alpha Beta")
        #expect(results[0].score == 800)
        #expect(results[1].title == "My Alpha")
        #expect(results[1].score == 600)
    }

    @Test("Contains ranks above fuzzy")
    func containsAboveFuzzy() {
        let candidates = ["A_B_C", "ABC Project"]
        let results = matcher.rank(query: "ABC", candidates: candidates)
        // "ABC Project" has prefix -> 800
        // "A_B_C" has fuzzy subsequence -> 400
        #expect(results[0].title == "ABC Project")
        #expect(results[1].title == "A_B_C")
        #expect(results[0].score > results[1].score)
    }

    @Test("Non-match excluded")
    func nonMatchExcluded() {
        let candidates = ["Alpha", "Beta", "Gamma"]
        let results = matcher.rank(query: "Zeta", candidates: candidates)
        #expect(results.isEmpty)
    }

    @Test("Empty query returns all sorted alphabetically")
    func emptyQueryReturnsAll() {
        let candidates = ["Gamma", "Alpha", "Beta"]
        let results = matcher.rank(query: "", candidates: candidates)
        #expect(results.count == 3)
        #expect(results.map(\.title) == ["Alpha", "Beta", "Gamma"])
    }

    @Test("Case insensitive matching")
    func caseInsensitive() {
        let candidates = ["ALPHA", "alpha", "Alpha"]
        let results = matcher.rank(query: "alpha", candidates: candidates)
        #expect(results.count == 3)
        #expect(results.allSatisfy { $0.score == 1000 })
    }

    @Test("Stable sort for ties")
    func stableSortForTies() {
        let candidates = ["Zebra", "Apple", "Mango"]
        let results = matcher.rank(query: "", candidates: candidates)
        #expect(results.map(\.title) == ["Apple", "Mango", "Zebra"])
    }

    @Test("Fuzzy subsequence matches")
    func fuzzySubsequence() {
        let candidates = ["Q2 Launch Plan"]
        let results = matcher.rank(query: "qlp", candidates: candidates)
        #expect(results.count == 1)
        #expect(results[0].score == 400)
    }
}
