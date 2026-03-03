import Foundation

public struct TagParser: Sendable {
    private let regex: NSRegularExpression

    public init() {
        self.regex = try! NSRegularExpression(pattern: #"(?:^|\s)#([a-zA-Z][a-zA-Z0-9_/\-]*)"#, options: .anchorsMatchLines)
    }

    public func extractTags(from body: String) -> [String] {
        guard !body.isEmpty else {
            return []
        }

        let range = NSRange(location: 0, length: body.utf16.count)
        let matches = regex.matches(in: body, options: [], range: range)

        var seen = Set<String>()
        var result: [String] = []

        for match in matches {
            guard match.numberOfRanges > 1,
                  let tagRange = Range(match.range(at: 1), in: body)
            else {
                continue
            }

            let tag = String(body[tagRange]).lowercased()
            guard !tag.isEmpty, !seen.contains(tag) else {
                continue
            }
            seen.insert(tag)
            result.append(tag)
        }

        return result
    }
}
