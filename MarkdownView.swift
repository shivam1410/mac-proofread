// Renders the Markdown that models return (headings, nested bullet/numbered lists, inline styles).
// SwiftUI's Text only handles inline Markdown, so block structure is parsed here.
import SwiftUI

struct MarkdownBlock: Equatable {
    enum Kind: Equatable {
        case paragraph
        case heading
        case bullet(level: Int)
        case numbered(level: Int, number: String)
    }

    let kind: Kind
    let text: String
}

/// Splits Markdown into lines of blocks. List depth comes from relative indentation,
/// so both 2-space and 4-space nested lists work.
func parseMarkdownBlocks(_ markdown: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    var listIndents: [Int] = [] // indentation of each open list level
    for line in markdown.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }
        let indent = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }

        if let match = trimmed.firstMatch(of: #/^#{1,6}\s+(.+)$/#) {
            listIndents = []
            blocks.append(MarkdownBlock(kind: .heading, text: String(match.1)))
            continue
        }
        let bullet = trimmed.firstMatch(of: #/^[-*+•◦▪]\s+(.+)$/#)
        let numbered = trimmed.firstMatch(of: #/^(\d+[.)])\s+(.+)$/#)
        guard bullet != nil || numbered != nil else {
            listIndents = []
            blocks.append(MarkdownBlock(kind: .paragraph, text: trimmed))
            continue
        }
        while let last = listIndents.last, last > indent { listIndents.removeLast() }
        if listIndents.last != indent { listIndents.append(indent) }
        let level = min(listIndents.count - 1, 3)
        if let bullet {
            blocks.append(MarkdownBlock(kind: .bullet(level: level), text: String(bullet.1)))
        } else if let numbered {
            blocks.append(MarkdownBlock(kind: .numbered(level: level, number: String(numbered.1)), text: String(numbered.2)))
        }
    }
    return blocks
}

struct MarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(parseMarkdownBlocks(markdown).enumerated()), id: \.offset) { _, block in
                row(block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder private func row(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case .paragraph:
            Text(inline(block.text)).fixedSize(horizontal: false, vertical: true)
        case .heading:
            Text(inline(block.text)).font(.headline).padding(.top, 2)
        case let .bullet(level):
            listRow(marker: ["●", "○", "▪", "▫"][level], markerFont: .system(size: level < 2 ? 7 : 10), level: level, text: block.text)
        case let .numbered(level, number):
            listRow(marker: number, markerFont: .body.monospacedDigit(), level: level, text: block.text)
        }
    }

    private func listRow(marker: String, markerFont: Font, level: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(marker).font(markerFont).foregroundStyle(.secondary).frame(minWidth: 10, alignment: .trailing)
            Text(inline(text)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, CGFloat(level) * 18)
    }

    /// Bold, italic, code and links inside one line.
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
