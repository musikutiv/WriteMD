import XCTest
import AppKit

func loadModel(_ s: String) -> EditorModel {
    let m = EditorModel()
    try! m.load(data: Data(s.utf8))
    return m
}

func roundTrip(_ s: String) -> String {
    String(decoding: loadModel(s).data(), as: UTF8.self)
}

/// Text view hosted in an (unshown) window, like the real editor, so undo and layout behave normally.
func makeEditor(_ markdown: String, width: CGFloat = 600) -> (EditorModel, EditorTextView) {
    _ = NSApplication.shared
    let m = loadModel(markdown)
    let tv = EditorTextView(storage: m.storage)
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: 800))
    scroll.hasVerticalScroller = true
    scroll.documentView = tv
    let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled, .resizable], backing: .buffered, defer: true)
    window.contentView = scroll
    window.isReleasedWhenClosed = false
    tv.setFrameSize(NSSize(width: width, height: 800))
    windows.append(window)
    return (m, tv)
}
private var windows: [NSWindow] = []

extension EditorTextView {
    func type(_ s: String) { insertText(s, replacementRange: NSRange(location: NSNotFound, length: 0)) }
    func caret(_ loc: Int, _ len: Int = 0) { setSelectedRange(NSRange(location: loc, length: len)) }
    func caret(after needle: String) {
        let r = (string as NSString).range(of: needle)
        precondition(r.location != NSNotFound, "\(needle) not found in \(string)")
        setSelectedRange(NSRange(location: r.upperBound, length: 0))
    }
    func select(_ needle: String) {
        let r = (string as NSString).range(of: needle)
        precondition(r.location != NSNotFound, "\(needle) not found")
        setSelectedRange(r)
    }
}
