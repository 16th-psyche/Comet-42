import AppKit
import SwiftUI

/// A streamed reply, re-parsed on every change; blocks are cheap and replies are short.
struct MarkdownView: View {
    let text: String
    var midStream = false

    var body: some View {
        BlocksView(blocks: MarkdownBlock.parse(text, midStream: midStream))
            .textSelection(.enabled)
    }
}

private struct BlocksView: View {
    let blocks: [MarkdownBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
            }
        }
    }
}

private struct BlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(MarkdownBlock.inline(text))
                .scaledFont(level <= 1 ? 18 : level == 2 ? 16 : 14, weight: .semibold)
                .padding(.top, 2)
        case .paragraph(let text):
            Text(MarkdownBlock.inline(text))
                .fixedSize(horizontal: false, vertical: true)
        case .bulletList(let items):
            ListView(items: items, marker: { _ in "•" })
        case .numberedList(let start, let items):
            ListView(items: items, marker: { "\(start + $0)." })
        case .code(let language, let text):
            CodeBlockView(language: language, text: text)
        case .quote(let blocks):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 3)
                BlocksView(blocks: blocks)
                    .foregroundStyle(.secondary)
            }
        case .table(let table):
            TableView(table: table)
        case .rule:
            Divider()
        }
    }
}

private struct ListView: View {
    let items: [MarkdownBlock.Item]
    let marker: (Int) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    if let checked = item.checked {
                        Image(systemName: checked ? "checkmark.square" : "square")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(marker(index))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    BlocksView(blocks: item.blocks)
                }
            }
        }
    }
}

private struct CodeBlockView: View {
    let language: String?
    let text: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language?.isEmpty == false ? language! : "code")
                    .scaledFont(11, weight: .medium)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .scaledFont(11)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(copied ? "Code copied" : "Copy code")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .scaledFont(12, design: .monospaced)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
        }
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TableView: View {
    let table: MarkdownBlock.Table

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { index, cell in
                        Text(MarkdownBlock.inline(cell))
                            .fontWeight(.semibold)
                            .gridColumnAlignment(alignment(index))
                    }
                }
                Divider()
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(MarkdownBlock.inline(cell))
                        }
                    }
                }
            }
            .padding(10)
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func alignment(_ column: Int) -> HorizontalAlignment {
        guard table.alignments.indices.contains(column) else { return .leading }
        switch table.alignments[column] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

/// Word-level changes inline, so the reader sees what a rewrite touched.
struct DiffView: View {
    let original: String
    let modified: String

    var body: some View {
        Text(attributed)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for chunk in TextDiffEngine.diff(original: original, modified: modified) {
            switch chunk {
            case .equal(let text):
                result += AttributedString(text)
            case .inserted(let text):
                var part = AttributedString(text)
                part.backgroundColor = Color.green.opacity(0.22)
                // Underlined too, so an insertion reads without relying on colour.
                part.underlineStyle = .single
                result += part
            case .deleted(let text):
                var part = AttributedString(text)
                part.strikethroughStyle = .single
                part.foregroundColor = Color.red.opacity(0.8)
                result += part
            }
        }
        return result
    }
}
