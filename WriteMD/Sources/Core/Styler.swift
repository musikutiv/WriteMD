import AppKit

/// All appearance decisions. Everything here is *derived* from (Block, InlineFlags, neighbours);
/// nothing derived is ever saved, so restyling a few paragraphs after an edit is always safe.
enum Styler {
    static let bodySize: CGFloat = 15
    static let codeSize: CGFloat = 13.5
    static let headingSizes: [CGFloat] = [30, 23, 19, 16.5, 15, 13.5]
    static let bullet = "\u{2022}"

    // Palette follows LookMD (GitHub-like), adapting to light/dark.
    static func dynamic(_ light: Int, _ dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let v = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255,
                           blue: CGFloat(v & 255) / 255, alpha: 1)
        }
    }
    static let codeBackground = dynamic(0xf6f8fa, 0x161b22)
    static let linkColor = dynamic(0x0366d6, 0x58a6ff)
    static let ruleColor = dynamic(0xd0d7de, 0x30363d)
    static let quoteBar = dynamic(0xd0d7de, 0x30363d)

    // MARK: Fonts

    private static var fontCache: [String: NSFont] = [:]

    static func font(kind: BlockKind, flags: InlineFlags) -> NSFont {
        var size = bodySize
        var weight: NSFont.Weight = flags.contains(.bold) ? .bold : .regular
        var mono = flags.contains(.code)
        switch kind {
        case .heading(let n):
            size = headingSizes[max(1, min(6, n)) - 1]
            weight = .bold
            if mono { size = (size * 0.9).rounded() }
        case .code: mono = true; size = codeSize; weight = .regular
        case .verbatim: mono = true; size = codeSize - 0.5; weight = .regular
        default: if mono { size = codeSize }
        }
        let italic = flags.contains(.italic) && !kind.isRaw
        let key = "\(size)|\(weight.rawValue)|\(mono)|\(italic)"
        if let f = fontCache[key] { return f }
        var f: NSFont = mono ? .monospacedSystemFont(ofSize: size, weight: weight)
                             : .systemFont(ofSize: size, weight: weight)
        if italic {
            let d = f.fontDescriptor.withSymbolicTraits(.italic)
            f = NSFont(descriptor: d, size: size) ?? f
        }
        fontCache[key] = f
        return f
    }

    // MARK: Paragraph style

    private static var styleCache: [String: NSParagraphStyle] = [:]

    /// Width reserved for a list marker ("4." / bullet) before the text starts: the hanging indent.
    static func hang(forPrefix prefix: String) -> CGFloat {
        let w = (prefix as NSString).size(withAttributes: [.font: font(kind: .paragraph, flags: [])]).width
        return max(26, ceil(w) + 8)
    }

    /// Width of a manually typed list prefix ("12.  ", "- ") at the start of a paragraph, or 0.
    static func manualPrefixWidth(_ ns: NSString, _ pr: NSRange) -> CGFloat {
        var i = pr.location
        let end = pr.location + pr.length
        func ch(_ k: Int) -> unichar { ns.character(at: k) }
        if i < end, [45, 42, 43].contains(ch(i)) { i += 1 }
        else {
            let d = i
            while i < end, ch(i) >= 48, ch(i) <= 57 { i += 1 }
            guard i > d, i - d <= 9, i < end, ch(i) == 46 || ch(i) == 41 else { return 0 }
            i += 1
        }
        let m = i
        while i < end, ch(i) == 32 { i += 1 }
        guard i > m, i < end else { return 0 }
        let w = ns.substring(with: NSRange(location: pr.location, length: i - pr.location))
        return ceil((w as NSString).size(withAttributes: [.font: font(kind: .paragraph, flags: [])]).width)
    }

    /// Bullets are drawn larger and heavier than body text (visual only; the source marker is untouched).
    static let bulletFont = NSFont.systemFont(ofSize: 20, weight: .heavy)

    static func indentWidth(_ indent: String) -> CGFloat {
        var cols = 0
        for ch in indent { cols += ch == "\t" ? 4 : 1 }
        return CGFloat(cols) * 7
    }

    /// `continuing`: previous paragraph belongs to the same visual block (tight spacing).
    static func paragraphStyle(for block: Block, continuing: Bool, hang: CGFloat) -> NSParagraphStyle {
        let key = "\(block.kind)|\(continuing)|\(hang)|\(block.kind == .listItem ? block.indent : "")"
        if let s = styleCache[key] { return s }
        let p = NSMutableParagraphStyle()
        p.defaultTabInterval = 28
        p.lineHeightMultiple = 1.2
        p.paragraphSpacingBefore = 8
        switch block.kind {
        case .paragraph:
            // Visual only: a typed "1. " / "- " prefix makes wrapped lines align with the text.
            if hang > 0 { p.headIndent = hang }
        case .heading(let n):
            p.paragraphSpacingBefore = n <= 2 ? 22 : 16
            p.lineHeightMultiple = 1.1
        case .quote:
            p.firstLineHeadIndent = 20; p.headIndent = 20
        case .listItem:
            let first = indentWidth(block.indent)
            p.firstLineHeadIndent = first
            p.headIndent = first + hang
            p.tabStops = [NSTextTab(textAlignment: .left, location: first + hang, options: [:])]
            if continuing { p.paragraphSpacingBefore = 3 }
            // The enlarged bullet must not make its line taller than body text.
            let body = font(kind: .paragraph, flags: [])
            p.maximumLineHeight = ceil((body.ascender - body.descender + body.leading) * p.lineHeightMultiple)
        case .code, .verbatim:
            p.firstLineHeadIndent = 12; p.headIndent = 12; p.tailIndent = -12
            p.lineHeightMultiple = 1.15
            p.paragraphSpacingBefore = continuing ? 0 : 12
        case .rule:
            p.paragraphSpacingBefore = 10
        }
        styleCache[key] = p
        return p
    }

    // MARK: Attributes

    static func foreground(kind: BlockKind, flags: InlineFlags) -> NSColor {
        if kind == .rule { return .clear }
        if kind == .verbatim || kind == .quote || flags.contains(.raw) { return .secondaryLabelColor }
        return .labelColor
    }

    /// Typing attributes for an empty paragraph of `block`.
    static func typingAttributes(for block: Block) -> [NSAttributedString.Key: Any] {
        [.wmdBlock: block, .wmdFlags: InlineFlags([]).number,
         .font: font(kind: block.kind, flags: []),
         .foregroundColor: foreground(kind: block.kind, flags: []),
         .paragraphStyle: paragraphStyle(for: block, continuing: false, hang: 26)]
    }

    /// Re-applies every derived attribute (font, colour, paragraph style, block normalisation) to the
    /// paragraphs touching `range`, plus one paragraph on either side (their spacing depends on us).
    /// Cost is proportional to the edited paragraphs, never to the document.
    static func restyle(_ storage: NSTextStorage, range: NSRange, markDirty: Bool) {
        let ns = storage.string as NSString
        let len = ns.length
        guard len > 0 else { return }
        var r = ns.paragraphRange(for: NSRange(location: min(range.location, len), length: 0))
        let end = min(NSMaxRange(range), len)
        if end > r.upperBound { r = NSUnionRange(r, ns.paragraphRange(for: NSRange(location: end, length: 0))) }
        if r.location > 0 { r = NSUnionRange(r, ns.paragraphRange(for: NSRange(location: r.location - 1, length: 0))) }
        if r.upperBound < len { r = NSUnionRange(r, ns.paragraphRange(for: NSRange(location: r.upperBound, length: 0))) }

        var prevBlock: Block?
        if r.location > 0 {
            let p = ns.paragraphRange(for: NSRange(location: r.location - 1, length: 0))
            prevBlock = storage.attribute(.wmdBlock, at: p.location, effectiveRange: nil) as? Block
        }
        var loc = r.location
        while loc < r.upperBound {
            let pr = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            defer { loc = pr.upperBound }
            if pr.length == 0 { break }

            if markDirty {
                storage.enumerateAttribute(.wmdBlock, in: pr, options: []) { v, _, _ in (v as? Block)?.dirty = true }
            }
            var block = storage.attribute(.wmdBlock, at: pr.location, effectiveRange: nil) as? Block ?? Block(.paragraph)
            // Non-group blocks map to exactly one paragraph: inherited attributes (Return, paste) get a fresh Block.
            if !block.kind.isGroup, let pb = prevBlock, pb === block { block = block.sibling() }
            let continuing = prevBlock.map { $0 === block || ($0.kind == .listItem && block.kind == .listItem && $0.ordered == block.ordered) } ?? false
            prevBlock = block

            var prefix = ""
            if block.kind == .listItem {
                let t = ns.range(of: "\t", options: [], range: NSRange(location: pr.location, length: pr.length))
                if t.location != NSNotFound { prefix = ns.substring(with: NSRange(location: pr.location, length: t.location - pr.location)) }
            }
            storage.addAttribute(.wmdBlock, value: block, range: pr)
            let h = block.kind == .paragraph ? manualPrefixWidth(ns, pr) : hang(forPrefix: prefix)
            storage.addAttribute(.paragraphStyle,
                                 value: paragraphStyle(for: block, continuing: continuing, hang: h),
                                 range: pr)
            let kind = block.kind
            storage.enumerateAttribute(.wmdFlags, in: pr, options: []) { v, run, _ in
                var flags = InlineFlags.from(v)
                if kind.isRaw { flags = [] }
                storage.addAttributes([.font: font(kind: kind, flags: flags),
                                       .foregroundColor: foreground(kind: kind, flags: flags)], range: run)
                if flags.contains(.code) && !kind.isRaw {
                    storage.addAttribute(.backgroundColor, value: codeBackground, range: run)
                } else {
                    storage.removeAttribute(.backgroundColor, range: run)
                }
                if v == nil { storage.addAttribute(.wmdFlags, value: flags.number, range: run) }
            }
            if kind == .listItem, prefix == bullet {
                storage.addAttributes([.font: bulletFont, .baselineOffset: -1.5],
                                      range: NSRange(location: pr.location, length: 1))
            }
        }
    }
}
