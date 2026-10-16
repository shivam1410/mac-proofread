// Renders the Markdown that models return (headings, nested bullet/numbered lists, tables, inline styles).
// SwiftUI's Text only handles inline Markdown, so block structure is parsed here.
import SwiftUI

struct MarkdownBlock: Equatable {
    enum Kind: Equatable {
        case paragraph
        case heading
        case bullet(level: Int)
        case numbered(level: Int, number: String)
        /// Tab-separated rows (pasted from or into a spreadsheet) or a Markdown pipe table; first row is the header.
        case table(rows: [[String]])
    }

    let kind: Kind
    var text = ""
}

/// Cells of a table line, or nil when the line isn't one. Pipe-table divider rows (|---|:--:|) give [].
func tableCells(_ line: String) -> [String]? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("|") {
        if trimmed.allSatisfy({ "|-: ".contains($0) }) { return [] }
        var cells = trimmed.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if cells.first == "" { cells.removeFirst() }
        if cells.last == "" { cells.removeLast() }
        return cells
    }
    guard trimmed.contains("\t") else { return nil }
    return trimmed.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
}

/// Splits Markdown into lines of blocks. List depth comes from relative indentation,
/// so both 2-space and 4-space nested lists work.
func parseMarkdownBlocks(_ markdown: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    var listIndents: [Int] = [] // indentation of each open list level
    for line in markdown.components(separatedBy: .newlines) {
        if let cells = tableCells(line) {
            listIndents = []
            if cells.isEmpty { continue } // pipe-table divider
            if case let .table(rows)? = blocks.last?.kind {
                blocks[blocks.count - 1] = MarkdownBlock(kind: .table(rows: rows + [cells]))
            } else {
                blocks.append(MarkdownBlock(kind: .table(rows: [cells])))
            }
            continue
        }
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
        case let .table(rows):
            table(rows)
        }
    }

    /// Header in bold over a divider; numbers right-aligned so digits line up. Scrolls sideways when wide.
    private func table(_ rows: [[String]]) -> some View {
        let columns = rows.map(\.count).max() ?? 0
        return ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(0..<columns, id: \.self) { column in
                            let cell = column < row.count ? row[column] : ""
                            Text(inline(cell))
                                .fontWeight(index == 0 ? .semibold : .regular)
                                .monospacedDigit()
                                .gridColumnAlignment(isNumeric(cell) ? .trailing : .leading)
                        }
                    }
                    if index == 0 && rows.count > 1 { Divider() }
                }
            }
            .font(.callout)
            .padding(.vertical, 2)
        }
    }

    private func isNumeric(_ cell: String) -> Bool {
        Double(cell.replacingOccurrences(of: ",", with: "")) != nil
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
