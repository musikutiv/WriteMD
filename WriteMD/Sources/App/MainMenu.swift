import AppKit

/// The menu bar, built in code (no nib/storyboard: smaller bundle, faster launch).
enum MainMenu {
    static func install() {
        let main = NSMenu()
        main.addItem(menuItem(appMenu()))
        main.addItem(menuItem(fileMenu()))
        main.addItem(menuItem(editMenu()))
        main.addItem(menuItem(formatMenu()))
        main.addItem(menuItem(viewMenu()))
        let window = windowMenu()
        main.addItem(menuItem(window))
        NSApp.mainMenu = main
        NSApp.windowsMenu = window
    }

    private static func menuItem(_ submenu: NSMenu) -> NSMenuItem {
        let i = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        i.submenu = submenu
        return i
    }

    @discardableResult
    private static func add(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
                            _ mods: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = key.isEmpty ? [] : mods
        i.tag = tag
        menu.addItem(i)
        return i
    }

    private static func appMenu() -> NSMenu {
        let m = NSMenu(title: "WriteMD")
        add(m, "About WriteMD", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        m.addItem(.separator())
        add(m, "Hide WriteMD", #selector(NSApplication.hide(_:)), "h")
        add(m, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        add(m, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        m.addItem(.separator())
        add(m, "Quit WriteMD", #selector(NSApplication.terminate(_:)), "q")
        return m
    }

    private static func fileMenu() -> NSMenu {
        let m = NSMenu(title: "File")
        add(m, "New", #selector(NSDocumentController.newDocument(_:)), "n")
        add(m, "Open…", #selector(NSDocumentController.openDocument(_:)), "o")
        let recent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        add(recentMenu, "Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:)))
        recent.submenu = recentMenu
        m.addItem(recent)
        m.addItem(.separator())
        add(m, "Close", #selector(NSWindow.performClose(_:)), "w")
        add(m, "Save", #selector(NSDocument.save(_:)), "s")
        add(m, "Save As…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift])
        add(m, "Revert to Saved", #selector(NSDocument.revertToSaved(_:)))
        m.addItem(.separator())
        add(m, "Page Setup…", #selector(NSDocument.runPageLayout(_:)), "p", [.command, .shift])
        add(m, "Print…", #selector(NSDocument.printDocument(_:)), "p")
        return m
    }

    private static func editMenu() -> NSMenu {
        let m = NSMenu(title: "Edit")
        add(m, "Undo", Selector(("undo:")), "z")
        add(m, "Redo", Selector(("redo:")), "z", [.command, .shift])
        m.addItem(.separator())
        add(m, "Cut", #selector(NSText.cut(_:)), "x")
        add(m, "Copy", #selector(NSText.copy(_:)), "c")
        add(m, "Paste", #selector(NSText.paste(_:)), "v")
        add(m, "Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift])
        add(m, "Delete", #selector(NSText.delete(_:)))
        add(m, "Select All", #selector(NSText.selectAll(_:)), "a")
        m.addItem(.separator())

        let find = NSMenu(title: "Find")
        add(find, "Find…", #selector(NSResponder.performTextFinderAction(_:)), "f", tag: NSTextFinder.Action.showFindInterface.rawValue)
        add(find, "Find Next", #selector(NSResponder.performTextFinderAction(_:)), "g", tag: NSTextFinder.Action.nextMatch.rawValue)
        add(find, "Find Previous", #selector(NSResponder.performTextFinderAction(_:)), "g", [.command, .shift], tag: NSTextFinder.Action.previousMatch.rawValue)
        add(find, "Jump to Selection", #selector(NSResponder.centerSelectionInVisibleArea(_:)), "j")
        let findItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        findItem.submenu = find
        m.addItem(findItem)

        let spelling = NSMenu(title: "Spelling and Grammar")
        add(spelling, "Show Spelling and Grammar", #selector(NSText.showGuessPanel(_:)), ":")
        add(spelling, "Check Document Now", #selector(NSText.checkSpelling(_:)), ";")
        add(spelling, "Check Spelling While Typing", #selector(NSTextView.toggleContinuousSpellChecking(_:)))
        add(spelling, "Check Grammar With Spelling", #selector(NSTextView.toggleGrammarChecking(_:)))
        let spellItem = NSMenuItem(title: "Spelling and Grammar", action: nil, keyEquivalent: "")
        spellItem.submenu = spelling
        m.addItem(spellItem)
        m.addItem(.separator())
        add(m, "Emoji & Symbols", #selector(NSApplication.orderFrontCharacterPalette(_:)), " ", [.command, .control])
        return m
    }

    private static func formatMenu() -> NSMenu {
        let m = NSMenu(title: "Format")
        add(m, "Bold", #selector(EditorTextView.wmdToggleBold(_:)), "b")
        add(m, "Italic", #selector(EditorTextView.wmdToggleItalic(_:)), "i")
        add(m, "Code", #selector(EditorTextView.wmdToggleCode(_:)), "e")
        add(m, "Link…", #selector(EditorTextView.wmdLink(_:)), "k")
        m.addItem(.separator())
        add(m, "Paragraph", #selector(EditorTextView.wmdSetParagraph(_:)), "0")
        for n in 1...6 { add(m, "Heading \(n)", #selector(EditorTextView.wmdSetHeading(_:)), "\(n)", tag: n) }
        m.addItem(.separator())
        add(m, "Quote", #selector(EditorTextView.wmdToggleQuote(_:)), "q", [.command, .option])
        add(m, "Bulleted List", #selector(EditorTextView.wmdToggleBullets(_:)), "u", [.command, .option])
        add(m, "Numbered List", #selector(EditorTextView.wmdToggleNumbered(_:)), "o", [.command, .option])
        add(m, "Code Block", #selector(EditorTextView.wmdToggleCodeBlock(_:)), "c", [.command, .option])
        add(m, "Horizontal Rule", #selector(EditorTextView.wmdInsertRule(_:)), "-", [.command, .option])
        return m
    }

    private static func viewMenu() -> NSMenu {
        let m = NSMenu(title: "View")
        add(m, "Hide Toolbar", #selector(NSWindow.toggleToolbarShown(_:)), "t", [.command, .option])
        add(m, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        return m
    }

    private static func windowMenu() -> NSMenu {
        let m = NSMenu(title: "Window")
        add(m, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        add(m, "Zoom", #selector(NSWindow.performZoom(_:)))
        m.addItem(.separator())
        add(m, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        return m
    }
}
