import Foundation

/// One editor paragraph as parsed from source.
struct Para {
    /// Literal text shown before the body (list markers: "4.\t" or "•\t").
    var prefix = ""
    /// Inline Markdown (or raw text when `raw`). Soft line breaks are "\n".
    var body: String
    var raw = false
}

struct ParsedBlock {
    var block: Block
    var paras: [Para]
}

struct ParsedDocument {
    /// Blank lines before the first block.
    var leading: String
    var blocks: [ParsedBlock]
    /// Whitespace after the last block (usually "\n").
    var endTrailer: String
}

private struct LineInfo {
    var blank: Bool
    var cols: Int       // indentation in columns (tab = 4)
    var bytes: Int      // indentation in bytes
    var first: UInt8    // first non-blank byte
}

/// Line-based block parser. Deliberately conservative: anything it is not sure about becomes a
/// `.verbatim` block that is displayed and saved exactly as written.
/// Every block remembers its exact source text and the whitespace that followed it, so an untouched
/// document reassembles byte-for-byte.
enum MarkdownParser {
    static func parse(_ text: String) -> ParsedDocument {
        var p = Parser(text: text)
        return p.run()
    }

    static func emptyDocument() -> ParsedDocument {
        ParsedDocument(leading: "", blocks: [], endTrailer: "\n")
    }
}

private let blockTags: Set<String> = [
    "address", "article", "aside", "base", "blockquote", "body", "caption", "center", "col", "colgroup", "dd", "details",
    "dialog", "dir", "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form", "frame", "frameset",
    "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hr", "html", "iframe", "legend", "li", "link", "main", "menu",
    "menuitem", "nav", "noframes", "ol", "optgroup", "option", "p", "param", "section", "source", "summary", "table",
    "tbody", "td", "tfoot", "th", "thead", "title", "tr", "track", "ul", "pre", "script", "style", "textarea",
]

private struct Parser {
    let text: String
    let lines: [Substring]
    let infos: [LineInfo]

    init(text: String) {
        self.text = text
        lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        infos = lines.map(Parser.info)
    }

    static func info(_ line: Substring) -> LineInfo {
        var cols = 0, bytes = 0
        for b in line.utf8 {
            if b == 32 { cols += 1 } else if b == 9 { cols += 4 } else if b == 13 { /* stray CR */ }
            else { return LineInfo(blank: false, cols: cols, bytes: bytes, first: b) }
            bytes += 1
        }
        return LineInfo(blank: true, cols: cols, bytes: bytes, first: 0)
    }

    var n: Int { lines.count }

    mutating func run() -> ParsedDocument {
        var i = 0
        while i < n, infos[i].blank { i += 1 }
        if i >= n { return ParsedDocument(leading: text, blocks: [], endTrailer: "\n") }
        let leading = String(text[text.startIndex..<lines[i].startIndex])

        var blocks: [ParsedBlock] = []
        var spans: [(Int, Int)] = []
        var afterList = false
        while i < n {
            if infos[i].blank { i += 1; continue }
            let (pb, next) = parseBlock(i, afterList: afterList)
            spans.append((i, next))
            blocks.append(pb)
            afterList = pb.block.kind == .listItem
            i = next
        }
        for b in 0..<blocks.count {
            let (s, e) = spans[b]
            let start = lines[s].startIndex, end = lines[e - 1].endIndex
            let after = b + 1 < blocks.count ? lines[spans[b + 1].0].startIndex : text.endIndex
            blocks[b].block.origin = String(text[start..<end])
            blocks[b].block.trailer = String(text[end..<after])
            blocks[b].block.seq = b
        }
        return ParsedDocument(leading: leading, blocks: blocks, endTrailer: blocks.last!.block.trailer)
    }

    // MARK: Block dispatch

    mutating func parseBlock(_ i: Int, afterList: Bool) -> (ParsedBlock, Int) {
        let li = infos[i], line = lines[i]

        if i == 0, li.cols == 0, trimmed(line) == "---" {
            var j = 1
            while j < n { let t = trimmed(lines[j]); if t == "---" || t == "..." { return verbatim(i, j + 1) }; j += 1 }
        }
        if li.cols >= 4 && !(afterList && listMarker(i) != nil) {
            return indentedRun(i, minCols: 4)
        }
        if afterList && li.cols >= 2 && listMarker(i) == nil && !startsOtherBlock(i) {
            return indentedRun(i, minCols: 2)
        }
        if li.first == UInt8(ascii: "`") || li.first == UInt8(ascii: "~"), let f = fence(i) {
            return fencedCode(i, f)
        }
        if li.first == UInt8(ascii: "#"), let h = atx(i) {
            let b = Block(.heading(h.level))
            return (ParsedBlock(block: b, paras: [Para(body: h.content)]), i + 1)
        }
        if li.first == UInt8(ascii: "$"), trimmed(line).hasPrefix("$$") {
            let t = trimmed(line)
            if t.count >= 4 && t.hasSuffix("$$") { return verbatim(i, i + 1) }
            var j = i + 1
            while j < n { if lines[j].contains("$$") { return verbatim(i, j + 1) }; j += 1 }
            return verbatim(i, n)
        }
        if isRule(i) {
            let b = Block(.rule)
            return (ParsedBlock(block: b, paras: [Para(body: String(line), raw: true)]), i + 1)
        }
        if lines[i].utf8.contains(124), i + 1 < n, isDelimiterRow(i + 1) {
            var j = i + 2
            while j < n, !infos[j].blank, ![UInt8(ascii: ">"), UInt8(ascii: "#")].contains(infos[j].first),
                  fence(j) == nil { j += 1 }
            return verbatim(i, j)
        }
        if li.first == UInt8(ascii: ">") { return quote(i) }
        if listMarker(i) != nil { return listItem(i) }
        if li.first == UInt8(ascii: "["), isRefDef(i) {
            var j = i + 1
            while j < n, !infos[j].blank, isRefDef(j) || infos[j].cols >= 2 { j += 1 }
            return verbatim(i, j)
        }
        if li.first == UInt8(ascii: "<"), let end = htmlEnd(i) { return verbatim(i, end) }
        return paragraph(i)
    }

    func trimmed(_ s: Substring) -> String { s.trimmingCharacters(in: .whitespaces) }

    // MARK: Verbatim

    func verbatim(_ i: Int, _ j: Int) -> (ParsedBlock, Int) {
        let paras = lines[i..<j].map { Para(body: String($0), raw: true) }
        return (ParsedBlock(block: Block(.verbatim), paras: paras), j)
    }

    func indentedRun(_ i: Int, minCols: Int) -> (ParsedBlock, Int) {
        var j = i + 1
        var last = i
        while j < n {
            if infos[j].blank { j += 1; continue }
            if infos[j].cols >= minCols { last = j; j += 1 } else { break }
        }
        return verbatim(i, last + 1)
    }

    // MARK: Headings

    func atx(_ i: Int) -> (level: Int, content: String)? {
        let li = infos[i]
        guard li.cols < 4 else { return nil }
        let u = Array(lines[i].utf8)
        var k = li.bytes, level = 0
        while k < u.count, u[k] == 35 { level += 1; k += 1 }
        guard (1...6).contains(level), k == u.count || u[k] == 32 || u[k] == 9 else { return nil }
        var content = trimmed(Substring(String(decoding: u[k...], as: UTF8.self)))
        // optional closing sequence: trailing #'s preceded by a space (or making up the whole content)
        if let r = content.range(of: "(^|[ \t])#+$", options: .regularExpression) {
            content = trimmed(Substring(content[..<r.lowerBound]))
        }
        return (level, content)
    }

    // MARK: Fenced code

    struct Fence { var char: UInt8; var len: Int; var indent: Int }

    func fence(_ i: Int) -> Fence? {
        let li = infos[i]
        guard li.cols < 4, li.first == 96 || li.first == 126 else { return nil }
        let u = Array(lines[i].utf8)
        var k = li.bytes, len = 0
        while k < u.count, u[k] == li.first { len += 1; k += 1 }
        guard len >= 3 else { return nil }
        if li.first == 96, u[k...].contains(96) { return nil }
        return Fence(char: li.first, len: len, indent: li.cols)
    }

    func isClosingFence(_ i: Int, _ f: Fence) -> Bool {
        let li = infos[i]
        guard li.cols < 4, li.first == f.char else { return false }
        let u = Array(lines[i].utf8)
        var k = li.bytes, len = 0
        while k < u.count, u[k] == f.char { len += 1; k += 1 }
        guard len >= f.len else { return false }
        return u[k...].allSatisfy { $0 == 32 || $0 == 9 || $0 == 13 }
    }

    func fencedCode(_ i: Int, _ f: Fence) -> (ParsedBlock, Int) {
        var j = i + 1
        while j < n, !isClosingFence(j, f) { j += 1 }
        let closed = j < n
        if f.indent > 0 { return verbatim(i, closed ? j + 1 : n) }
        let b = Block(.code)
        b.fenceOpen = String(lines[i])
        b.fenceClose = closed ? String(lines[j]) : nil
        var paras = lines[(i + 1)..<min(j, n)].map { Para(body: String($0), raw: true) }
        if paras.isEmpty { paras = [Para(body: "", raw: true)] }
        return (ParsedBlock(block: b, paras: paras), closed ? j + 1 : n)
    }

    // MARK: Rules, tables, html, definitions

    func isRule(_ i: Int) -> Bool {
        let li = infos[i]
        guard li.cols < 4, [45, 42, 95].contains(li.first) else { return false }
        var count = 0
        for b in lines[i].utf8 {
            if b == li.first { count += 1 } else if b != 32 && b != 9 && b != 13 { return false }
        }
        return count >= 3
    }

    func isDelimiterRow(_ i: Int) -> Bool {
        var dash = false, pipe = false
        for b in lines[i].utf8 {
            switch b {
            case 45: dash = true
            case 124: pipe = true
            case 58, 32, 9, 13: break
            default: return false
            }
        }
        return dash && pipe
    }

    func isRefDef(_ i: Int) -> Bool {
        let li = infos[i]
        guard li.cols < 4, li.first == 91 else { return false }
        let u = Array(lines[i].utf8)
        var k = li.bytes + 1
        while k < u.count, u[k] != 93 { if u[k] == 91 { return false }; k += 1 }
        return k > li.bytes + 1 && k + 1 < u.count && u[k + 1] == 58
    }

    /// Exclusive end line of an HTML block starting at `i`, or nil if line `i` is not one.
    func htmlEnd(_ i: Int) -> Int? {
        let li = infos[i]
        guard li.cols < 4 else { return nil }
        let t = trimmed(lines[i])
        var untilBlank = true
        if t.hasPrefix("<!--") { untilBlank = false }
        else if t.hasPrefix("<?") || t.hasPrefix("<![") || t.hasPrefix("<!") { untilBlank = false }
        else {
            // tag name
            let body = t.dropFirst().drop(while: { $0 == "/" })
            let name = body.prefix(while: { $0.isLetter || $0.isNumber || $0 == "-" }).lowercased()
            guard !name.isEmpty else { return nil }
            let isBlockTag = blockTags.contains(name)
            let loneTag = t.hasSuffix(">") && t.filter({ $0 == "<" }).count == 1 && t.first == "<"
            guard isBlockTag || loneTag else { return nil }
        }
        if untilBlank {
            var j = i + 1
            while j < n, !infos[j].blank { j += 1 }
            return j
        }
        let closer = t.hasPrefix("<!--") ? "-->" : (t.hasPrefix("<?") ? "?>" : ">")
        var j = i
        if t.hasPrefix("<!--") && t.dropFirst(4).contains("-->") { return i + 1 }
        if closer == ">" && t.dropFirst().contains(">") { return i + 1 }
        j = i + 1
        while j < n { if lines[j].contains(closer) { return j + 1 }; j += 1 }
        return n
    }

    // MARK: Quotes

    func quote(_ i: Int) -> (ParsedBlock, Int) {
        var j = i
        var contents: [String] = []
        var simple = true
        while j < n, infos[j].first == 62, infos[j].cols < 4 {
            var u = Substring(lines[j].drop(while: { $0 == " " }))
            u = u.dropFirst()
            if u.first == " " { u = u.dropFirst() }
            let content = String(u)
            if content.trimmingCharacters(in: .whitespaces).isEmpty || content.hasPrefix(">") { simple = false }
            contents.append(content)
            j += 1
        }
        if simple {
            for k in 0..<contents.count {
                let inf = Parser.info(Substring(contents[k]))
                let probe = Parser(text: contents[k])
                if inf.cols >= 4 || probe.atx(0) != nil || probe.fence(0) != nil || probe.isRule(0)
                    || probe.listMarker(0) != nil || contents[k].hasPrefix("|") { simple = false; break }
            }
        }
        if !simple { return verbatim(i, j) }
        return (ParsedBlock(block: Block(.quote), paras: [Para(body: contents.joined(separator: "\n"))]), j)
    }

    // MARK: Lists

    struct Marker { var indent: String; var marker: String; var spacing: String; var rest: Substring
                    var ordered: Bool; var number: Int }

    func listMarker(_ i: Int) -> Marker? {
        let li = infos[i]
        guard !li.blank else { return nil }
        let line = lines[i]
        let u = line.utf8
        let startIdx = u.index(u.startIndex, offsetBy: li.bytes)
        var idx = startIdx
        let c = u[idx]
        var ordered = false, number = 0
        if c == 45 || c == 43 || c == 42 {
            idx = u.index(after: idx)
        } else if c >= 48 && c <= 57 {
            var digits = 0
            while idx < u.endIndex, u[idx] >= 48, u[idx] <= 57 {
                number = number * 10 + Int(u[idx] - 48); digits += 1; idx = u.index(after: idx)
            }
            guard digits <= 9, idx < u.endIndex, u[idx] == 46 || u[idx] == 41 else { return nil }
            idx = u.index(after: idx)
            ordered = true
        } else { return nil }
        guard idx == u.endIndex || u[idx] == 32 || u[idx] == 9 else { return nil }
        let markerStr = String(line[startIdx..<idx])
        var sp = idx
        while sp < u.endIndex, u[sp] == 32 || u[sp] == 9 { sp = u.index(after: sp) }
        // 5+ spaces after the marker mean indented code inside the item: keep one space as the separator
        var spacing = String(line[idx..<sp])
        var restStart = sp
        if spacing.count >= 5 { spacing = String(spacing.prefix(1)); restStart = line.index(idx, offsetBy: 1) }
        return Marker(indent: String(line[line.startIndex..<startIdx]), marker: markerStr, spacing: spacing,
                      rest: line[restStart...], ordered: ordered, number: number)
    }

    /// True if line `k` starts something that ends a paragraph / list item.
    func startsOtherBlock(_ k: Int) -> Bool {
        let li = infos[k]
        if li.blank { return true }
        switch li.first {
        case 35: return atx(k) != nil
        case 96, 126: return fence(k) != nil
        case 62: return li.cols < 4
        case 36: return trimmed(lines[k]).hasPrefix("$$")
        case 60: return li.cols < 4 && htmlBlockStartsParagraph(k)
        case 45, 42, 95: return isRule(k)
        default: return false
        }
    }

    func htmlBlockStartsParagraph(_ k: Int) -> Bool {
        let t = trimmed(lines[k])
        if t.hasPrefix("<!--") { return true }
        let name = t.dropFirst().drop(while: { $0 == "/" }).prefix(while: { $0.isLetter || $0.isNumber }).lowercased()
        return blockTags.contains(name)
    }

    func listItem(_ i: Int) -> (ParsedBlock, Int) {
        let m = listMarker(i)!
        let b = Block(.listItem)
        b.indent = m.indent; b.spacing = m.spacing; b.ordered = m.ordered
        if !m.ordered { b.marker = m.marker }
        let contentCols = Parser.cols(m.indent) + m.marker.count + m.spacing.count
        var body = String(m.rest)
        var j = i + 1
        while j < n, !startsOtherBlock(j), listMarker(j) == nil {
            body += "\n" + stripIndent(lines[j], upTo: contentCols)
            j += 1
        }
        let prefix = (m.ordered ? m.marker : Styler.bullet) + "\t"
        return (ParsedBlock(block: b, paras: [Para(prefix: prefix, body: body)]), j)
    }

    static func cols(_ s: String) -> Int { s.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } }

    func stripIndent(_ line: Substring, upTo cols: Int) -> String {
        var c = 0
        var idx = line.startIndex
        while idx < line.endIndex, c < cols, line[idx] == " " || line[idx] == "\t" {
            c += line[idx] == "\t" ? 4 : 1
            idx = line.index(after: idx)
        }
        return String(line[idx...])
    }

    // MARK: Paragraphs

    func paragraph(_ i: Int) -> (ParsedBlock, Int) {
        var j = i + 1
        while j < n {
            // setext heading underline
            let lj = infos[j]
            if lj.cols < 4, lj.first == 61 || lj.first == 45, isSetextUnderline(j) {
                let level = lj.first == 61 ? 1 : 2
                let b = Block(.heading(level))
                b.setext = trimmed(lines[j])
                let body = lines[i..<j].map { String($0) }.joined(separator: "\n")
                return (ParsedBlock(block: b, paras: [Para(body: body)]), j + 1)
            }
            if startsOtherBlock(j) { break }
            if let m = listMarker(j), !m.rest.allSatisfy({ $0 == " " }), !m.ordered || m.number == 1 { break }
            j += 1
        }
        let body = lines[i..<j].map { String($0) }.joined(separator: "\n")
        return (ParsedBlock(block: Block(.paragraph), paras: [Para(body: body)]), j)
    }

    func isSetextUnderline(_ i: Int) -> Bool {
        let li = infos[i]
        for b in lines[i].utf8 where b != li.first && b != 32 && b != 9 && b != 13 { return false }
        // spaces only allowed at the end
        let t = trimmed(lines[i])
        return t.utf8.allSatisfy { $0 == li.first }
    }
}
