import Foundation

public struct WikiLinkParser: Sendable {
    private let regex: NSRegularExpression

    public init() {
        self.regex = try! NSRegularExpression(pattern: #"\[\[([^\]|]+)(?:\|[^\]]+)?\]\]"#)
    }

    public func linkedTitles(in body: String) -> [String] {
        guard !body.isEmpty else {
            return []
        }

        let range = NSRange(location: 0, length: body.utf16.count)
        let matches = regex.matches(in: body, options: [], range: range)

        return matches.compactMap { match in
            guard match.numberOfRanges > 1,
                  let titleRange = Range(match.range(at: 1), in: body)
            else {
                return nil
            }

            let title = String(body[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        }
    }
}
