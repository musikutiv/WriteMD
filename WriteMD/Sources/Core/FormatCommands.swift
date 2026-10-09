import AppKit

enum BlockTarget: Equatable {
    case paragraph, heading(Int), quote, bullet, numbered, code
}

extension EditorTextView {
    // MARK: Inline

    @objc func wmdToggleBold(_ sender: Any?) { toggleInline(.bold) }
    @objc func wmdToggleItalic(_ sender: Any?) { toggleInline(.italic) }
    @objc func wmdToggleCode(_ sender: Any?) { toggleInline(.code) }

    private func isInlineEditable(_ block: Block?) -> Bool { !(block?.kind.isRaw ?? false) }

    func toggleInline(_ flag: InlineFlags) {
        guard let st = textStorage else { return }
        let sel = selectedRange()
        if sel.length == 0 {
            guard isInlineEditable(currentBlock) else { return }
            var ta = typingAttributes
            var f = InlineFlags.from(ta[.wmdFlags])
            if f.contains(flag) { f.remove(flag) } else { f.insert(flag) }
            ta[.wmdFlags] = f.number
            typingAttributes = ta
            return
        }
        var runs: [(NSRange, InlineFlags)] = []
        var all = true
        st.enumerateAttributes(in: sel, options: []) { attrs, r, _ in
            guard self.isInlineEditable(attrs[.wmdBlock] as? Block) else { return }
            let f = InlineFlags.from(attrs[.wmdFlags])
            if !f.contains(flag) { all = false }
            runs.append((r, f))
        }
        guard !runs.isEmpty else { return }
        breakUndoCoalescing()
        guard shouldChangeText(in: sel, replacementString: nil) else { return }
        st.beginEditing()
        for (r, f) in runs {
            var nf = f
            if all { nf.remove(flag) } else { nf.insert(flag) }
            st.addAttribute(.wmdFlags, value: nf.number, range: r)
        }
        st.endEditing()
        didChangeText()
        undoManager?.setActionName(flag == .bold ? "Bold" : flag == .italic ? "Italic" : "Code")
        breakUndoCoalescing()
    }

    @objc func wmdLink(_ sender: Any?) {
        guard let st = textStorage, let window = window else { return }
        var sel = selectedRange()
        let existing = sel.location < st.length ? st.attribute(.link, at: sel.location, effectiveRange: nil) as? String : nil
        let alert = NSAlert()
        alert.messageText = "Link"
        alert.informativeText = "Address for the selected text. Leave empty to remove the link."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = existing ?? ""
        field.placeholderString = "https://"
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .alertFirstButtonReturn else { return }
            let dest = field.stringValue.trimmingCharacters(in: .whitespaces)
            self.setLink(dest.isEmpty ? nil : dest, in: &sel)
        }
        field.becomeFirstResponder()
    }

    func setLink(_ dest: String?, in sel: inout NSRange) {
        guard let st = textStorage else { return }
        breakUndoCoalescing()
        if sel.length == 0 {
            guard let dest = dest else { return }
            let attrs: [NSAttributedString.Key: Any] = typingAttributes.merging([.link: dest]) { $1 }
            let ins = NSAttributedString(string: dest, attributes: attrs)
            guard shouldChangeText(in: sel, replacementString: dest) else { return }
            st.replaceCharacters(in: sel, with: ins)
            didChangeText()
            setSelectedRange(NSRange(location: sel.location + ins.length, length: 0))
            return
        }
        guard shouldChangeText(in: sel, replacementString: nil) else { return }
        st.beginEditing()
        if let dest = dest { st.addAttribute(.link, value: dest, range: sel) } else { st.removeAttribute(.link, range: sel) }
        st.endEditing()
        didChangeText()
        undoManager?.setActionName("Link")
        breakUndoCoalescing()
    }

    // MARK: Block styles

    @objc func wmdSetParagraph(_ sender: Any?) { applyBlock(.paragraph) }
    @objc func wmdSetHeading(_ sender: Any?) {
        let isPopup = sender is NSPopUpButton
        let tag = (sender as? NSMenuItem)?.tag ?? (sender as? NSPopUpButton)?.selectedItem?.tag ?? 1
        applyBlock(tag == 0 ? .paragraph : .heading(tag), toggle: !isPopup)
    }
    @objc func wmdToggleQuote(_ sender: Any?) { applyBlock(.quote) }
    @objc func wmdToggleBullets(_ sender: Any?) { applyBlock(.bullet) }
    @objc func wmdToggleNumbered(_ sender: Any?) { applyBlock(.numbered) }
    @objc func wmdToggleCodeBlock(_ sender: Any?) { applyBlock(.code) }

    private func matches(_ b: Block, _ t: BlockTarget) -> Bool {
        switch t {
        case .paragraph: return b.kind == .paragraph
        case .heading(let n): return b.kind == .heading(n)
        case .quote: return b.kind == .quote
        case .bullet: return b.kind == .listItem && !b.ordered
        case .numbered: return b.kind == .listItem && b.ordered
        case .code: return b.kind == .code
        }
    }

    /// Paragraph ranges (with terminator) touched by the selection.
    private func selectedParagraphs() -> [NSRange] {
        guard let st = textStorage else { return [] }
        let ns = st.string as NSString
        let sel = selectedRange()
        let last = sel.length > 0 ? sel.upperBound - 1 : sel.location
        var result: [NSRange] = []
        var loc = ns.paragraphRange(for: NSRange(location: min(sel.location, ns.length), length: 0)).location
        while true {
            let pr = ns.paragraphRange(for: NSRange(location: min(loc, ns.length), length: 0))
            result.append(pr)
            if pr.upperBound > last || pr.upperBound >= ns.length { break }
            loc = pr.upperBound
        }
        return result
    }

    /// Source-faithful content of a paragraph, independent of its current block kind.
    private func body(of pr: NSRange, block: Block) -> NSAttributedString {
        guard let st = textStorage else { return NSAttributedString() }
        let ns = st.string as NSString
        var s = 0, e = 0, ce = 0
        ns.getParagraphStart(&s, end: &e, contentsEnd: &ce, for: NSRange(location: pr.location, length: 0))
        let content = NSRange(location: s, length: ce - s)
        let attr = st.attributedSubstring(from: content)
        switch block.kind {
        case .listItem:
            let t = (attr.string as NSString).range(of: "\t")
            if t.location == NSNotFound { return attr }
            return attr.attributedSubstring(from: NSRange(location: NSMaxRange(t), length: attr.length - NSMaxRange(t)))
        case .code, .verbatim, .rule:
            let text = attr.string.replacingOccurrences(of: "\u{2028}", with: "\n")
            let out = NSMutableAttributedString()
            for run in InlineParser.parse(text) {
                var attrs: [NSAttributedString.Key: Any] = [.wmdFlags: run.flags.number]
                if let l = run.link { attrs[.link] = l }
                out.append(NSAttributedString(string: run.text, attributes: attrs))
            }
            return out
        default:
            return attr
        }
    }

    func applyBlock(_ requested: BlockTarget, toggle: Bool = true) {
        guard let st = textStorage, isEditable else { return }
        let paras = selectedParagraphs()
        guard let first = paras.first, let lastP = paras.last else { return }
        let ns = st.string as NSString
        let region = NSRange(location: first.location, length: lastP.upperBound - first.location)

        struct Item { var block: Block; var body: NSAttributedString; var terminated: Bool; var oldPrefix: Int; var start: Int }
        var items: [Item] = []
        for pr in paras {
            let b = (pr.location < st.length ? st.attribute(.wmdBlock, at: pr.location, effectiveRange: nil) as? Block : nil) ?? Block(.paragraph)
            var s = 0, e = 0, ce = 0
            ns.getParagraphStart(&s, end: &e, contentsEnd: &ce, for: NSRange(location: pr.location, length: 0))
            let bd = body(of: pr, block: b)
            let prefix = (b.kind == .listItem ? (ce - s) - bd.length : 0)
            items.append(Item(block: b, body: bd, terminated: e > ce, oldPrefix: prefix, start: s))
        }
        let target: BlockTarget = toggle && requested != .paragraph && items.allSatisfy({ matches($0.block, requested) }) ? .paragraph : requested

        let out = NSMutableAttributedString()
        var newStarts: [Int] = []
        var newPrefixes: [Int] = []
        var number = 1
        var sharedCode: Block?
        let plain: [NSAttributedString.Key: Any] = [.wmdFlags: InlineFlags([]).number]

        func append(_ content: NSAttributedString, prefix: String, block: Block, terminated: Bool) {
            newStarts.append(out.length)
            newPrefixes.append(prefix.count)
            let piece = NSMutableAttributedString()
            if !prefix.isEmpty { piece.append(NSAttributedString(string: prefix, attributes: plain)) }
            piece.append(content)
            piece.addAttribute(.wmdBlock, value: block, range: piece.wmdFullRange)
            out.append(piece)
            if terminated { out.append(NSAttributedString(string: "\n", attributes: plain.merging([.wmdBlock: block]) { $1 })) }
        }

        for (idx, it) in items.enumerated() {
            let terminated = it.terminated || idx < items.count - 1
            let old = it.block
            switch target {
            case .paragraph, .heading, .quote:
                let kind: BlockKind
                switch target { case .heading(let n): kind = .heading(n); case .quote: kind = .quote; default: kind = .paragraph }
                if old.kind == .rule {
                    append(it.body, prefix: "", block: Block(kind), terminated: terminated)
                } else if kind.isRaw { continue }
                else { append(it.body, prefix: "", block: old.derived(kind), terminated: terminated) }
            case .bullet, .numbered:
                if old.kind == .rule { append(it.body, prefix: "", block: Block(.paragraph), terminated: terminated); continue }
                let b = old.derived(.listItem)
                b.ordered = target == .numbered
                if old.kind != .listItem { b.indent = ""; b.spacing = " "; b.marker = "-" }
                let prefix = target == .numbered ? "\(number).\t" : "\(Styler.bullet)\t"
                number += 1
                append(it.body, prefix: prefix, block: b, terminated: terminated)
            case .code:
                if sharedCode == nil { let c = Block(.code); c.trailer = old.trailer; sharedCode = c }
                let md = InlineSerializer.markdown(it.body)
                let lines = md.split(separator: "\n", omittingEmptySubsequences: false)
                for (li, line) in lines.enumerated() {
                    let t = terminated || li < lines.count - 1
                    append(NSAttributedString(string: String(line), attributes: plain), prefix: "", block: sharedCode!, terminated: t)
                }
            }
        }
        if out.length == 0 && region.length == 0 { return }

        // Map selection: keep caret/selection at the same place inside the text.
        func map(_ loc: Int) -> Int {
            for (i, it) in items.enumerated().reversed() where loc >= it.start {
                let bodyOffset = max(0, loc - it.start - it.oldPrefix)
                let ns2 = out.string as NSString
                let start = i < newStarts.count ? newStarts[i] : 0
                var s = 0, e = 0, ce = 0
                ns2.getParagraphStart(&s, end: &e, contentsEnd: &ce, for: NSRange(location: min(start, ns2.length), length: 0))
                let pre = i < newPrefixes.count ? newPrefixes[i] : 0
                return min(start + pre + bodyOffset, ce)
            }
            return region.location
        }
        let sel = selectedRange()
        let newSel = NSRange(location: map(sel.location), length: sel.length == 0 ? 0 : max(0, map(sel.upperBound) - map(sel.location)))

        let name: String
        switch target {
        case .paragraph: name = "Paragraph"
        case .heading(let n): name = "Heading \(n)"
        case .quote: name = "Quote"
        case .bullet: name = "Bulleted List"
        case .numbered: name = "Numbered List"
        case .code: name = "Code Block"
        }
        replaceRegion(region, with: out, select: newSel, action: name)
    }

    private func replaceRegion(_ range: NSRange, with new: NSAttributedString, select: NSRange, action: String) {
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

    // MARK: Horizontal rule

    @objc func wmdInsertRule(_ sender: Any?) {
        guard let st = textStorage, isEditable else { return }
        let ns = st.string as NSString
        var s = 0, e = 0, ce = 0
        ns.getParagraphStart(&s, end: &e, contentsEnd: &ce, for: NSRange(location: selectedRange().location, length: 0))
        let cur = (s < st.length ? st.attribute(.wmdBlock, at: s, effectiveRange: nil) as? Block : nil) ?? Block(.paragraph)
        let plain: [NSAttributedString.Key: Any] = [.wmdFlags: InlineFlags([]).number]
        let rule = Block(.rule)
        let ins = NSMutableAttributedString()
        // The new newline terminates the current paragraph; "---" is a new rule paragraph.
        ins.append(NSAttributedString(string: "\n", attributes: plain.merging([.wmdBlock: cur]) { $1 }))
        ins.append(NSAttributedString(string: "---", attributes: plain.merging([.wmdBlock: rule]) { $1 }))
        let atEnd = e >= st.length && ce == e
        if atEnd { ins.append(NSAttributedString(string: "\n", attributes: plain.merging([.wmdBlock: rule]) { $1 })) }
        let at = NSRange(location: ce, length: 0)
        replaceRegion(at, with: ins, select: NSRange(location: ce + ins.length + (atEnd ? 0 : 1), length: 0), action: "Horizontal Rule")
    }

    // MARK: Menu validation

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        let b = currentBlock
        if let mi = item as? NSMenuItem {
            switch item.action {
            case #selector(wmdSetHeading(_:)): mi.state = b?.kind == .heading(mi.tag) ? .on : .off
            case #selector(wmdSetParagraph(_:)): mi.state = b?.kind == .paragraph ? .on : .off
            case #selector(wmdToggleQuote(_:)): mi.state = b?.kind == .quote ? .on : .off
            case #selector(wmdToggleBullets(_:)): mi.state = (b?.kind == .listItem && b?.ordered == false) ? .on : .off
            case #selector(wmdToggleNumbered(_:)): mi.state = (b?.kind == .listItem && b?.ordered == true) ? .on : .off
            case #selector(wmdToggleCodeBlock(_:)): mi.state = b?.kind == .code ? .on : .off
            case #selector(wmdToggleBold(_:)), #selector(wmdToggleItalic(_:)), #selector(wmdToggleCode(_:)):
                let flag: InlineFlags = item.action == #selector(wmdToggleBold(_:)) ? .bold
                    : item.action == #selector(wmdToggleItalic(_:)) ? .italic : .code
                let f = InlineFlags.from(selectedRange().length == 0 ? typingAttributes[.wmdFlags]
                    : textStorage?.attribute(.wmdFlags, at: selectedRange().location, effectiveRange: nil))
                mi.state = f.contains(flag) ? .on : .off
                return isEditable
            default: break
            }
        }
        let actions: [Selector] = [#selector(wmdSetHeading(_:)), #selector(wmdSetParagraph(_:)), #selector(wmdToggleQuote(_:)),
                                   #selector(wmdToggleBullets(_:)), #selector(wmdToggleNumbered(_:)), #selector(wmdToggleCodeBlock(_:)),
                                   #selector(wmdInsertRule(_:)), #selector(wmdLink(_:))]
        if let a = item.action, actions.contains(a) { return isEditable }
        return super.validateUserInterfaceItem(item)
    }
}
