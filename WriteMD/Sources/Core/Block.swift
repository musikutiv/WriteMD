import AppKit

extension NSAttributedString.Key {
    /// The `Block` a paragraph belongs to (set on every character of the paragraph, incl. its newline).
    static let wmdBlock = NSAttributedString.Key("com.musikutiv.writemd.block")
    /// `InlineFlags.rawValue` as NSNumber.
    static let wmdFlags = NSAttributedString.Key("com.musikutiv.writemd.flags")
}

/// Inline state of a text run. Markdown delimiters are never stored in the text; they only exist in the file.
struct InlineFlags: OptionSet {
    let rawValue: Int
    static let bold = InlineFlags(rawValue: 1)
    static let italic = InlineFlags(rawValue: 2)
    static let code = InlineFlags(rawValue: 4)
    /// Source text shown literally (images, inline HTML, math, ...). Never escaped when saving.
    static let raw = InlineFlags(rawValue: 8)
    /// Character was written with a backslash escape in the source. Re-escaped when saving.
    static let escaped = InlineFlags(rawValue: 16)

    static func from(_ value: Any?) -> InlineFlags {
        InlineFlags(rawValue: (value as? NSNumber)?.intValue ?? 0)
    }
    var number: NSNumber { InlineFlags.numbers[rawValue] ?? NSNumber(value: rawValue) }
    private static let numbers: [Int: NSNumber] = Dictionary(uniqueKeysWithValues: (0..<32).map { ($0, NSNumber(value: $0)) })
}

enum BlockKind: Equatable {
    case paragraph
    case heading(Int)
    case quote
    case listItem
    /// Fenced code block. One editor paragraph per line, all sharing one `Block`.
    case code
    /// Anything we do not interpret (tables, HTML, YAML front matter, indented code, ...). Lines kept verbatim.
    case verbatim
    case rule

    /// Kinds whose editor paragraphs (lines) share one Block instance and form one Markdown block.
    var isGroup: Bool { self == .code || self == .verbatim }
    /// Kinds whose text is Markdown *source*, not rendered text.
    var isRaw: Bool { self == .code || self == .verbatim || self == .rule }
}

/// Describes the Markdown block a paragraph came from / belongs to.
/// Treated as immutable after creation, except for the monotonic `dirty` flag, so that
/// undo can restore attributes that reference older Blocks without surprises.
final class Block: NSObject {
    let kind: BlockKind

    // List items: the marker is *text* in the editor ("4.\t..."); these remember the source layout.
    var indent = ""
    var spacing = " "
    var marker = "-"
    var ordered = false
    /// Setext heading underline ("===" / "---") if the heading was written that way.
    var setext: String?
    // Fenced code
    var fenceOpen = "```"
    var fenceClose: String? = "```"

    /// Original Markdown of this block (without the blank lines that follow it).
    var origin: String?
    /// Whitespace between this block and the next in the original file ("\n\n", "\n", ...).
    var trailer: String
    /// Index of the block in the file at load time (-1: created in the editor).
    var seq = -1
    /// Set when anything in/near the block was edited. Clean blocks are saved byte-for-byte from `origin`.
    var dirty = false

    init(_ kind: BlockKind) {
        self.kind = kind
        self.trailer = kind == .listItem ? "\n" : "\n\n"
    }

    /// A new block of `kind` that keeps list layout details and (for non-group kinds) the origin,
    /// so that toggling a style back and forth saves the original text again.
    func derived(_ kind: BlockKind) -> Block {
        let b = Block(kind)
        b.indent = indent; b.spacing = spacing; b.marker = marker; b.ordered = ordered
        b.trailer = trailer
        if !self.kind.isGroup && !kind.isGroup {
            b.origin = origin; b.seq = seq
            if case .heading = kind { b.setext = setext }
        }
        b.dirty = true
        return b
    }

    /// Fresh sibling with the same kind but no origin (used when a paragraph is split).
    func sibling() -> Block {
        let b = Block(kind)
        b.indent = indent; b.spacing = spacing; b.marker = marker; b.ordered = ordered
        b.trailer = trailer
        b.dirty = true
        return b
    }
}

extension NSAttributedString {
    var wmdFullRange: NSRange { NSRange(location: 0, length: length) }
}
