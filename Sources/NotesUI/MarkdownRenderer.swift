import Foundation
import Markdown

public struct MarkdownRenderer: @unchecked Sendable {
    public init() {}

    public func render(_ markdown: String, noteTitles: [String]) -> AttributedString {
        guard !markdown.isEmpty else {
            return AttributedString()
        }

        let document = Document(parsing: markdown)
        var visitor = AttributedStringVisitor(noteTitles: noteTitles)
        return visitor.visit(document)
    }
}

private struct AttributedStringVisitor: MarkupVisitor {
    typealias Result = AttributedString

    let existingTitles: Set<String>

    init(noteTitles: [String]) {
        self.existingTitles = Set(noteTitles.map { $0.lowercased() })
    }

    mutating func defaultVisit(_ markup: any Markup) -> AttributedString {
        var result = AttributedString()
        for child in markup.children {
            result.append(visit(child))
        }
        return result
    }

    mutating func visitDocument(_ document: Document) -> AttributedString {
        var result = AttributedString()
        for child in document.children {
            result.append(visit(child))
        }
        return result
    }

    mutating func visitHeading(_ heading: Heading) -> AttributedString {
        var content = defaultVisit(heading)
        content.inlinePresentationIntent = .stronglyEmphasized
        return content + AttributedString("\n")
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> AttributedString {
        defaultVisit(paragraph) + AttributedString("\n")
    }

    mutating func visitText(_ text: Markdown.Text) -> AttributedString {
        processWikiLinks(in: text.string)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> AttributedString {
        var result = defaultVisit(emphasis)
        result.inlinePresentationIntent = .emphasized
        return result
    }

    mutating func visitStrong(_ strong: Strong) -> AttributedString {
        var result = defaultVisit(strong)
        result.inlinePresentationIntent = .stronglyEmphasized
        return result
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> AttributedString {
        var result = AttributedString(inlineCode.code)
        result.inlinePresentationIntent = .code
        return result
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> AttributedString {
        var result = AttributedString(codeBlock.code)
        result.inlinePresentationIntent = .code
        return result + AttributedString("\n")
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> AttributedString {
        var result = AttributedString()
        for item in unorderedList.listItems {
            result.append(AttributedString("  \u{2022} "))
            result.append(visit(item))
        }
        return result
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> AttributedString {
        var result = AttributedString()
        for (index, item) in orderedList.listItems.enumerated() {
            result.append(AttributedString("  \(index + 1). "))
            result.append(visit(item))
        }
        return result
    }

    mutating func visitListItem(_ listItem: ListItem) -> AttributedString {
        defaultVisit(listItem)
    }

    mutating func visitSoftBreak(_: SoftBreak) -> AttributedString {
        AttributedString("\n")
    }

    mutating func visitLineBreak(_: LineBreak) -> AttributedString {
        AttributedString("\n")
    }

    mutating func visitThematicBreak(_: ThematicBreak) -> AttributedString {
        AttributedString("\n---\n")
    }

    mutating func visitLink(_ link: Markdown.Link) -> AttributedString {
        var result = defaultVisit(link)
        if let destination = link.destination, let url = URL(string: destination) {
            result.link = url
        }
        return result
    }

    private func processWikiLinks(in text: String) -> AttributedString {
        let pattern = #"\[\[([^\]|]+)(?:\|([^\]]+))?\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return AttributedString(text)
        }

        let nsRange = NSRange(text.startIndex ..< text.endIndex, in: text)
        let matches = regex.matches(in: text, range: nsRange)

        guard !matches.isEmpty else {
            return AttributedString(text)
        }

        var result = AttributedString()
        var lastEnd = text.startIndex

        for match in matches {
            guard let fullRange = Range(match.range(at: 0), in: text),
                  let titleRange = Range(match.range(at: 1), in: text)
            else {
                continue
            }

            if lastEnd < fullRange.lowerBound {
                result.append(AttributedString(String(text[lastEnd ..< fullRange.lowerBound])))
            }

            let title = String(text[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let displayText: String = if match.numberOfRanges > 2, let aliasRange = Range(match.range(at: 2), in: text) {
                String(text[aliasRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                title
            }

            var linkAttr = AttributedString(displayText)
            let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
            linkAttr.link = URL(string: "deepnotes://wikilink/\(encodedTitle)")

            if existingTitles.contains(title.lowercased()) {
                linkAttr.foregroundColor = .accentColor
            } else {
                linkAttr.foregroundColor = .red.opacity(0.6)
            }

            result.append(linkAttr)
            lastEnd = fullRange.upperBound
        }

        if lastEnd < text.endIndex {
            result.append(AttributedString(String(text[lastEnd ..< text.endIndex])))
        }

        return result
    }
}
