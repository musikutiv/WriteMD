import AppKit

final class WriteMDDocument: NSDocument {
    let model = EditorModel()

    // Saving is always an explicit user action; nothing rewrites the file behind the user's back.
    override class var autosavesInPlace: Bool { false }
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController(model: model))
    }

    override func read(from data: Data, ofType typeName: String) throws {
        try model.load(data: data)
        undoManager?.removeAllActions()
    }

    override func data(ofType typeName: String) throws -> Data {
        model.data()
    }

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        let info = (printInfo.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
        info.dictionary().addEntries(from: printSettings.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value })
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let copy = EditorTextView(storage: NSTextStorage(attributedString: model.storage))
        copy.centersContent = false
        copy.textContainerInset = .zero
        copy.isEditable = false
        copy.setFrameSize(NSSize(width: width, height: 100))
        copy.sizeToFit()
        return NSPrintOperation(view: copy, printInfo: info)
    }
}
