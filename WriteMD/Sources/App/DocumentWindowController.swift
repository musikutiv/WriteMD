import AppKit

final class DocumentWindowController: NSWindowController, NSToolbarDelegate, NSTextViewDelegate {
    let textView: EditorTextView
    private let stylePopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 130, height: 24), pullsDown: false)

    private enum Item {
        static let style = NSToolbarItem.Identifier("style")
        static let bold = NSToolbarItem.Identifier("bold")
        static let italic = NSToolbarItem.Identifier("italic")
        static let code = NSToolbarItem.Identifier("code")
        static let link = NSToolbarItem.Identifier("link")
        static let quote = NSToolbarItem.Identifier("quote")
        static let bullets = NSToolbarItem.Identifier("bullets")
        static let numbered = NSToolbarItem.Identifier("numbered")
        static let codeBlock = NSToolbarItem.Identifier("codeblock")
        static let rule = NSToolbarItem.Identifier("rule")
    }
    private var order: [NSToolbarItem.Identifier] {
        [Item.style, .space, Item.bold, Item.italic, Item.code, Item.link, .space,
         Item.quote, Item.bullets, Item.numbered, Item.codeBlock, Item.rule]
    }

    init(model: EditorModel) {
        textView = EditorTextView(storage: model.storage)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 860, height: 720))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        scroll.documentView = textView

        let window = NSWindow(contentRect: scroll.frame,
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: true)
        window.contentView = scroll
        window.minSize = NSSize(width: 420, height: 300)
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unifiedCompact
        super.init(window: window)
        shouldCascadeWindows = true
        textView.delegate = self

        for (i, (title, tag)) in ([("Paragraph", 0)] + (1...6).map { ("Heading \($0)", $0) }).enumerated() {
            stylePopup.addItem(withTitle: title)
            stylePopup.lastItem?.tag = tag
            _ = i
        }
        stylePopup.target = nil
        stylePopup.action = #selector(EditorTextView.wmdSetHeading(_:))
        stylePopup.controlSize = .regular

        let toolbar = NSToolbar(identifier: "WriteMDToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        NotificationCenter.default.addObserver(self, selector: #selector(selectionChanged),
                                               name: NSTextView.didChangeSelectionNotification, object: textView)
        window.makeFirstResponder(textView)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func selectionChanged(_ note: Notification) {
        switch textView.currentBlock?.kind {
        case .heading(let n)?: stylePopup.selectItem(withTag: n)
        case .paragraph?, nil: stylePopup.selectItem(withTag: 0)
        default: stylePopup.select(nil)
        }
    }

    // Links are edited with ⌘K; clicking one in the editor never navigates anywhere.
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool { true }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { order }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { order + [.flexibleSpace] }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        func button(_ symbol: String, _ label: String, _ action: Selector) -> NSToolbarItem {
            let item = NSToolbarItem(itemIdentifier: id)
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            item.label = label
            item.toolTip = label
            item.action = action
            item.target = nil // first responder: the editor
            item.isBordered = true
            return item
        }
        switch id {
        case Item.style:
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = stylePopup
            item.label = "Style"
            return item
        case Item.bold: return button("bold", "Bold", #selector(EditorTextView.wmdToggleBold(_:)))
        case Item.italic: return button("italic", "Italic", #selector(EditorTextView.wmdToggleItalic(_:)))
        case Item.code: return button("chevron.left.forwardslash.chevron.right", "Inline Code", #selector(EditorTextView.wmdToggleCode(_:)))
        case Item.link: return button("link", "Link", #selector(EditorTextView.wmdLink(_:)))
        case Item.quote: return button("text.quote", "Quote", #selector(EditorTextView.wmdToggleQuote(_:)))
        case Item.bullets: return button("list.bullet", "Bulleted List", #selector(EditorTextView.wmdToggleBullets(_:)))
        case Item.numbered: return button("list.number", "Numbered List", #selector(EditorTextView.wmdToggleNumbered(_:)))
        case Item.codeBlock: return button("curlybraces", "Code Block", #selector(EditorTextView.wmdToggleCodeBlock(_:)))
        case Item.rule: return button("minus", "Horizontal Rule", #selector(EditorTextView.wmdInsertRule(_:)))
        default: return nil
        }
    }
}
