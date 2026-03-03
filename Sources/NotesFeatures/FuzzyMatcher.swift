import Foundation

public struct ScoredMatch: Sendable, Equatable {
    public let title: String
    public let score: Int

    public init(title: String, score: Int) {
        self.title = title
        self.score = score
    }
}

public struct FuzzyMatcher: Sendable {
    public init() {}

    public func rank(query: String, candidates: [String]) -> [ScoredMatch] {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalizedQuery.isEmpty {
            return candidates
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .map { ScoredMatch(title: $0, score: 0) }
        }

        return candidates
            .compactMap { candidate -> ScoredMatch? in
                let lowered = candidate.lowercased()
                if lowered == normalizedQuery {
                    return ScoredMatch(title: candidate, score: 1000)
                }
                if lowered.hasPrefix(normalizedQuery) {
                    return ScoredMatch(title: candidate, score: 800)
                }
                if lowered.contains(normalizedQuery) {
                    return ScoredMatch(title: candidate, score: 600)
                }
                if isFuzzySubsequence(normalizedQuery, in: lowered) {
                    return ScoredMatch(title: candidate, score: 400)
                }
                return nil
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private func isFuzzySubsequence(_ query: String, in candidate: String) -> Bool {
        var queryIndex = query.startIndex
        var candidateIndex = candidate.startIndex

        while queryIndex < query.endIndex && candidateIndex < candidate.endIndex {
            if query[queryIndex] == candidate[candidateIndex] {
                queryIndex = query.index(after: queryIndex)
            }
            candidateIndex = candidate.index(after: candidateIndex)
        }

        return queryIndex == query.endIndex
    }
}
