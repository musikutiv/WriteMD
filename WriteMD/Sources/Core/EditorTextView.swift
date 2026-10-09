import AppKit

/// NSTextView configured as a quiet Markdown editor: no automatic formatting of any kind.
final class EditorTextView: NSTextView {
    static let maxContentWidth: CGFloat = 760

    convenience init(storage: NSTextStorage) {
        let lm = NSLayoutManager()
        lm.allowsNonContiguousLayout = true
        let tc = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        tc.widthTracksTextView = true
        storage.addLayoutManager(lm)
        lm.addTextContainer(tc)
        self.init(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: tc)
        configure()
    }

    private func configure() {
        isRichText = true
        allowsUndo = true
        isEditable = true
        isSelectable = true
        usesFontPanel = false
        usesRuler = false
        importsGraphics = false
        allowsImageEditing = false
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticTextCompletionEnabled = false
        smartInsertDeleteEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isHorizontallyResizable = false
        isVerticallyResizable = true
        autoresizingMask = [.width]
        minSize = NSSize(width: 0, height: 0)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textContainerInset = NSSize(width: 48, height: 32)
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        insertionPointColor = .labelColor
        linkTextAttributes = [.foregroundColor: Styler.linkColor, .underlineStyle: 0]
        font = Styler.font(kind: .paragraph, flags: [])
        typingAttributes = Styler.typingAttributes(for: Block(.paragraph))
        registerForDraggedTypes([.fileURL])
    }

    // MARK: Layout

    /// Centre a readable column in wide windows. Off when printing.
    var centersContent = true

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard centersContent else { return }
        let w = max(24, (newSize.width - EditorTextView.maxContentWidth) / 2)
        if abs(textContainerInset.width - w) > 0.5 { textContainerInset = NSSize(width: w, height: 32) }
    }

    // MARK: Plain, predictable input

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [.rtf, .string] }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard let s = pboard.string(forType: .string) else { return false }
        insertPlain(s)
        return true
    }

    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }
    override func pasteAsRichText(_ sender: Any?) { pasteAsPlainText(sender) }

    override func pasteAsPlainText(_ sender: Any?) {
        guard let s = NSPasteboard.general.string(forType: .string) else { return }
        insertPlain(s)
    }

    /// Inserts text with the attributes at the caret, normalising line endings. No Markdown is interpreted.
    func insertPlain(_ s: String) {
        let clean = s.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
            .replacingOccurrences(of: "\u{85}", with: "\n")
        insertText(clean, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    override func insertTab(_ sender: Any?) {
        insertText("\t", replacementRange: NSRange(location: NSNotFound, length: 0))
    }
    override func insertBacktab(_ sender: Any?) { /* never restructures anything */ }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            for url in urls {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            }
            return true
        }
        return super.performDragOperation(sender)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) { return .copy }
        return super.draggingEntered(sender)
    }

    // MARK: Helpers

    var storageOrNil: NSTextStorage? { textStorage }

    func block(atParagraphStartOf location: Int) -> Block? {
        guard let st = textStorage, st.length > 0 else { return nil }
        let loc = min(location, st.length - 1)
        let pr = (st.string as NSString).paragraphRange(for: NSRange(location: loc, length: 0))
        return st.attribute(.wmdBlock, at: pr.location, effectiveRange: nil) as? Block
    }

    /// Block kind of the paragraph containing the caret / selection start.
    var currentBlock: Block? {
        guard let st = textStorage else { return nil }
        let loc = selectedRange().location
        if loc >= st.length && loc > 0 && (st.string as NSString).character(at: loc - 1) == 10 {
            return nextBlock(after: block(atParagraphStartOf: loc - 1), tailIsEmpty: true)
        }
        return block(atParagraphStartOf: loc)
    }

    /// The block a new paragraph gets when Return is pressed in `old` (never continues lists).
    func nextBlock(after old: Block?, tailIsEmpty: Bool) -> Block {
        guard let old = old else { return Block(.paragraph) }
        switch old.kind {
        case .code, .verbatim: return old
        case .quote: return Block(.quote)
        case .heading(let n): return tailIsEmpty ? Block(.paragraph) : Block(.heading(n))
        default: return Block(.paragraph)
        }
    }

    private func replace(_ range: NSRange, with new: NSAttributedString, select: NSRange, action: String) {
        guard let st = textStorage else { return }
        breakUndoCoalescing()
        guard shouldChangeText(in: range, replacementString: new.string) else { return }
        st.beginEditing()
        st.replaceCharacters(in: range, with: new)
        st.endEditing()
        didChangeText()
        setSelectedRange(select)
        undoManager?.setActionName(action)
        breakUndoCoalescing()
    }

    // MARK: Return

    override func insertNewline(_ sender: Any?) {
        guard let st = textStorage, !hasMarkedText(), isEditable else { super.insertNewline(sender); return }
        let ns = st.string as NSString
        let sel = selectedRange()
        var sStart = 0, sEnd = 0, sCE = 0
        ns.getParagraphStart(&sStart, end: &sEnd, contentsEnd: &sCE, for: NSRange(location: sel.location, length: 0))
        var eStart = 0, eEnd = 0, eCE = 0
        ns.getParagraphStart(&eStart, end: &eEnd, contentsEnd: &eCE, for: NSRange(location: sel.upperBound, length: 0))

        let old = block(atParagraphStartOf: sStart) ?? Block(.paragraph)
        let head = NSMutableAttributedString(attributedString: st.attributedSubstring(from: NSRange(location: sStart, length: sel.location - sStart)))
        let tail = NSMutableAttributedString(attributedString: st.attributedSubstring(from: NSRange(location: sel.upperBound, length: max(0, eCE - sel.upperBound))))
        let hadTerminator = eEnd > eCE

        let newBlock = nextBlock(after: old, tailIsEmpty: tail.length == 0)
        if newBlock !== old { newBlock.trailer = old.trailer }
        tail.addAttribute(.wmdBlock, value: newBlock, range: tail.wmdFullRange)
        let plain: [NSAttributedString.Key: Any] = [.wmdFlags: InlineFlags([]).number]
        let out = NSMutableAttributedString(attributedString: head)
        out.append(NSAttributedString(string: "\n", attributes: plain.merging([.wmdBlock: old]) { $1 }))
        out.append(tail)
        if hadTerminator { out.append(NSAttributedString(string: "\n", attributes: plain.merging([.wmdBlock: newBlock]) { $1 })) }

        let region = NSRange(location: sStart, length: eEnd - sStart)
        replace(region, with: out, select: NSRange(location: sStart + head.length + 1, length: 0), action: "Typing")
        typingAttributes = Styler.typingAttributes(for: newBlock)
    }

    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) { insertNewline(sender) }
    override func insertParagraphSeparator(_ sender: Any?) { insertNewline(sender) }

    // MARK: Typing attributes in a trailing empty paragraph

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if !stillSelecting { refreshTypingAttributes() }
    }

    private func refreshTypingAttributes() {
        guard let st = textStorage, selectedRange().length == 0 else { return }
        let loc = selectedRange().location
        if loc == st.length, loc > 0, (st.string as NSString).character(at: loc - 1) == 10 {
            let prev = block(atParagraphStartOf: loc - 1)
            typingAttributes = Styler.typingAttributes(for: nextBlock(after: prev, tailIsEmpty: true))
        } else if st.length == 0 {
            typingAttributes = Styler.typingAttributes(for: Block(.paragraph))
        }
    }

    // MARK: Drawing of block decorations

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let lm = layoutManager, let tc = textContainer, let st = textStorage, st.length > 0 else { return }
        let origin = textContainerOrigin
        let glyphs = lm.glyphRange(forBoundingRect: rect.offsetBy(dx: -origin.x, dy: -origin.y), in: tc)
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let width = tc.size.width - 2 * tc.lineFragmentPadding

        st.enumerateAttribute(.wmdBlock, in: chars, options: []) { value, run, _ in
            guard let block = value as? Block else { return }
            switch block.kind {
            case .code, .verbatim, .quote, .rule: break
            default: return
            }
            // A block may extend beyond this run if split by the visible range: use the full effective range.
            var full = NSRange()
            _ = st.attribute(.wmdBlock, at: run.location, longestEffectiveRange: &full, in: NSRange(location: 0, length: st.length))
            var rectUnion = NSRect.null
            let g = lm.glyphRange(forCharacterRange: full, actualCharacterRange: nil)
            lm.enumerateLineFragments(forGlyphRange: g) { r, _, _, _, _ in rectUnion = rectUnion.union(r) }
            guard !rectUnion.isNull else { return }
            // The first line fragment includes the paragraph's "space before"; the decoration should not.
            let before = full.location == 0 ? 0 : (st.attribute(.paragraphStyle, at: full.location, effectiveRange: nil) as? NSParagraphStyle)?
                .paragraphSpacingBefore ?? 0
            var area = NSRect(x: origin.x + tc.lineFragmentPadding, y: origin.y + rectUnion.minY + before,
                              width: width, height: max(2, rectUnion.height - before))
            switch block.kind {
            case .code, .verbatim:
                area = area.insetBy(dx: 0, dy: -4)
                Styler.codeBackground.setFill()
                NSBezierPath(roundedRect: area, xRadius: 6, yRadius: 6).fill()
            case .quote:
                Styler.quoteBar.setFill()
                NSBezierPath(roundedRect: NSRect(x: area.minX + 4, y: area.minY + 2, width: 3, height: area.height - 4),
                             xRadius: 1.5, yRadius: 1.5).fill()
            case .rule:
                Styler.ruleColor.setFill()
                NSRect(x: area.minX, y: area.midY, width: area.width, height: 1.5).fill()
            default: break
            }
        }
    }
}
