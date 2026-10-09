import AppKit

enum EditorModelError: Error, LocalizedError {
    case notUTF8
    var errorDescription: String? { "WriteMD can only open UTF-8 text files." }
}

/// Owns the NSTextStorage of one document and everything needed to turn it back into the file.
final class EditorModel: NSObject, NSTextStorageDelegate {
    let storage = NSTextStorage()

    private(set) var leading = ""
    private(set) var endTrailer = "\n"
    private(set) var crlf = false
    private(set) var bom = false
    private var isLoading = false
    private var isRestyling = false
    /// A document whose only block renders to no text at all (e.g. an empty fenced block) has no character
    /// to carry its Block; remember it until the first edit.
    private var pristineEmptyBlock: Block?

    override init() {
        super.init()
        storage.delegate = self
    }

    // MARK: Load

    func load(data: Data) throws {
        var bytes = data
        var hasBOM = false
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3); hasBOM = true }
        guard var text = String(data: bytes, encoding: .utf8) else { throw EditorModelError.notUTF8 }
        let crlfCount = text.components(separatedBy: "\r\n").count - 1
        if crlfCount > 0 {
            let lfCount = text.utf8.reduce(0) { $0 + ($1 == 10 ? 1 : 0) }
            crlf = crlfCount * 2 > lfCount
            text = text.replacingOccurrences(of: "\r\n", with: "\n")
        } else { crlf = false }
        bom = hasBOM
        load(markdown: text)
    }

    /// `text` must use "\n" line endings.
    func load(markdown text: String) {
        let doc = text.isEmpty ? MarkdownParser.emptyDocument() : MarkdownParser.parse(text)
        leading = doc.leading
        endTrailer = doc.endTrailer
        let attributed = DocumentBuilder.build(doc)
        isLoading = true
        storage.beginEditing()
        storage.setAttributedString(attributed)
        Styler.restyle(storage, range: NSRange(location: 0, length: storage.length), markDirty: false)
        storage.endEditing()
        isLoading = false
        pristineEmptyBlock = (storage.length == 0 && doc.blocks.count == 1) ? doc.blocks[0].block : nil
    }

    // MARK: Editing hook

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard !isLoading, !isRestyling else { return }
        pristineEmptyBlock = nil
        isRestyling = true
        Styler.restyle(textStorage, range: editedRange, markDirty: true)
        isRestyling = false
    }

    // MARK: Save

    private struct Unit {
        var block: Block
        var ranges: [NSRange]
    }
    private struct Part {
        var text: String
        var block: Block
        var usedOrigin: Bool
    }

    /// Paragraph content ranges (without newline) with the Block of each (nil for a trailing empty paragraph).
    private func paragraphs() -> [(NSRange, Block?)] {
        let ns = storage.string as NSString
        let len = ns.length
        var result: [(NSRange, Block?)] = []
        var loc = 0
        while true {
            var s = 0, e = 0, ce = 0
            ns.getParagraphStart(&s, end: &e, contentsEnd: &ce, for: NSRange(location: loc, length: 0))
            let block = s < len ? storage.attribute(.wmdBlock, at: s, effectiveRange: nil) as? Block : nil
            result.append((NSRange(location: s, length: ce - s), block))
            if e >= len && ce == e { break }
            if e >= len { result.append((NSRange(location: len, length: 0), nil)); break }
            loc = e
        }
        return result
    }

    func markdown() -> String {
        var units: [Unit] = []
        if let b = pristineEmptyBlock, storage.length == 0 {
            units.append(Unit(block: b, ranges: [NSRange(location: 0, length: 0)]))
        } else {
        let paras = paragraphs()
        for (idx, (range, block)) in paras.enumerated() {
            var b = block ?? Block(.paragraph)
            // A trailing empty paragraph has no character to carry attributes: it continues a code/verbatim block.
            if block == nil, idx == paras.count - 1, let last = units.last, last.block.kind.isGroup { b = last.block }
            if b.kind.isGroup, let last = units.last, last.block === b {
                units[units.count - 1].ranges.append(range)
            } else {
                units.append(Unit(block: b, ranges: [range]))
            }
        }
        }

        var parts: [Part] = []
        var emitted = Set<ObjectIdentifier>()
        for u in units {
            let id = ObjectIdentifier(u.block)
            var text: String?
            var used = false
            if let origin = u.block.origin, !emitted.contains(id) {
                if !u.block.dirty {
                    text = origin; used = true
                } else {
                    let fresh = Serializer.unitText(block: u.block, paragraphs: u.ranges.map { storage.attributedSubstring(from: $0) })
                    if fresh == Serializer.canonicalText(origin: origin) { text = origin; used = true } else { text = fresh }
                }
                if used { emitted.insert(id) }
            }
            if text == nil {
                text = Serializer.unitText(block: u.block, paragraphs: u.ranges.map { storage.attributedSubstring(from: $0) })
            }
            if !used {
                // Empty paragraphs/quotes carry no Markdown.
                if text!.isEmpty || (u.block.kind == .quote && text! == ">") { continue }
            }
            parts.append(Part(text: text!, block: u.block, usedOrigin: used))
        }

        var out = leading
        for (i, p) in parts.enumerated() {
            out += p.text
            out += i == parts.count - 1 ? endTrailer : separator(p, parts[i + 1])
        }
        return out
    }

    private func separator(_ a: Part, _ b: Part) -> String {
        let base = a.block.trailer
        if a.usedOrigin, b.usedOrigin, a.block.seq >= 0, b.block.seq == a.block.seq + 1 { return base }
        // Blocks that are new or changed get a blank line between them (tight only between list items).
        let needBlank = !(a.block.kind == .listItem && b.block.kind == .listItem)
        let need = needBlank ? 2 : 1
        return base.filter({ $0 == "\n" }).count >= need ? base : (needBlank ? "\n\n" : "\n")
    }

    func data() -> Data {
        var s = markdown()
        if crlf { s = s.replacingOccurrences(of: "\n", with: "\r\n") }
        var d = Data()
        if bom { d.append(contentsOf: [0xEF, 0xBB, 0xBF]) }
        d.append(Data(s.utf8))
        return d
    }
}
