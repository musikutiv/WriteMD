import AppKit

/// Rendered paragraphs -> Markdown source, one block at a time.
enum Serializer {
    static func unitText(block: Block, paragraphs: [NSAttributedString]) -> String {
        switch block.kind {
        case .paragraph:
            return paragraphs.map(InlineSerializer.markdown).joined(separator: "\n")

        case .heading(let level):
            let content = paragraphs.map(InlineSerializer.markdown).joined(separator: "\n")
            if let u = block.setext, level <= 2, u.first == (level == 1 ? "=" : "-"), !content.isEmpty {
                return content + "\n" + u
            }
            let flat = content.replacingOccurrences(of: "\n", with: " ")
            return String(repeating: "#", count: level) + (flat.isEmpty ? "" : " " + flat)

        case .quote:
            let md = paragraphs.map(InlineSerializer.markdown).joined(separator: "\n")
            return md.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n")

        case .listItem:
            let p = paragraphs.first ?? NSAttributedString()
            let s = p.string as NSString
            let tab = s.range(of: "\t")
            var marker: String?
            var body = p
            if tab.location != NSNotFound {
                marker = s.substring(to: tab.location)
                body = p.attributedSubstring(from: NSRange(location: NSMaxRange(tab), length: s.length - NSMaxRange(tab)))
            }
            let md = InlineSerializer.markdown(body)
            guard let m = marker else { return block.indent + md }
            let markerOut = m == Styler.bullet ? block.marker : m
            let spacing = (block.spacing.isEmpty && !md.isEmpty) ? " " : block.spacing
            let head = block.indent + markerOut + spacing
            let pad = String(repeating: " ", count: Parser_cols(head))
            let parts = md.split(separator: "\n", omittingEmptySubsequences: false)
            return head + parts[0] + parts.dropFirst().map { "\n" + pad + $0 }.joined()

        case .code:
            var lines = paragraphs.flatMap { rawLines($0) }
            if lines == [""] { lines = [] }
            var open = block.fenceOpen
            var close = block.fenceClose ?? ""
            let trimmedOpen = open.drop(while: { $0 == " " })
            if let ch = trimmedOpen.first, ch == "`" || ch == "~" {
                let len = trimmedOpen.prefix(while: { $0 == ch }).count
                var need = len
                for l in lines {
                    let t = l.drop(while: { $0 == " " })
                    let run = t.prefix(while: { $0 == ch }).count
                    if run >= len, t.dropFirst(run).allSatisfy({ $0 == " " || $0 == "\t" }) { need = max(need, run + 1) }
                }
                if need > len {
                    let info = trimmedOpen.dropFirst(len)
                    open = String(repeating: ch, count: need) + info
                    close = String(repeating: ch, count: need)
                } else if close.isEmpty {
                    close = String(repeating: ch, count: len)
                }
            } else if close.isEmpty { close = "```" }
            return ([open] + lines + [close]).joined(separator: "\n")

        case .verbatim:
            return paragraphs.flatMap { rawLines($0) }.joined(separator: "\n")

        case .rule:
            let t = (paragraphs.first?.string ?? "").trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? "---" : t
        }
    }

    private static func rawLines(_ p: NSAttributedString) -> [String] {
        p.string.replacingOccurrences(of: "\u{2028}", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func Parser_cols(_ s: String) -> Int { s.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } }

    /// Serialization of the block as it would be after loading its own origin: used to decide whether an
    /// edited-then-reverted block can go back to its original text.
    static func canonicalText(origin: String) -> String? {
        let doc = MarkdownParser.parse(origin)
        guard doc.blocks.count == 1, doc.leading.isEmpty else { return nil }
        let pb = doc.blocks[0]
        let paras = pb.paras.map { DocumentBuilder.paragraph($0, block: pb.block) }
        return unitText(block: pb.block, paragraphs: paras)
    }
}
