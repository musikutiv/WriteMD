import XCTest
import AppKit

final class EditingTests: XCTestCase {

    // MARK: Localised rewrites

    func testEditingOneParagraphLeavesEverythingElseByteIdentical() {
        let src = "# Title #\n\nFirst __odd__ paragraph.\n\n* star item\n* second\n\nSetext\n======\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nLast   one  with   spaces.\n"
        let (m, tv) = makeEditor(src)
        tv.caret(after: "First ")
        tv.type("X")
        let out = m.markdown()
        XCTAssertEqual(out, src.replacingOccurrences(of: "First __odd__ paragraph.", with: "First X**odd** paragraph."))
        // Everything but that one paragraph is untouched. (The edited paragraph is normalised: __ -> *.)
    }

    func testTypingInsideBoldPreservesBold() {
        let (m, tv) = makeEditor("A **bold** word\n")
        tv.caret(after: "bol")
        tv.type("Z")
        XCTAssertEqual(m.markdown(), "A **bolZd** word\n")
    }

    func testEditThenRevertByUndoRestoresOriginalSourceExactly() {
        let src = "__odd__ and *x*\n\nnext\n"
        let (m, tv) = makeEditor(src)
        tv.caret(after: "odd")
        tv.type("Q")
        XCTAssertNotEqual(m.markdown(), src)
        tv.deleteBackward(nil)
        // text identical again -> block is canonical-equal to its origin -> original spelling returns
        XCTAssertEqual(m.markdown(), src)
    }

    // MARK: Manual numbering

    func testManualNumberingIsOrdinaryTextAndNeverRenumbered() {
        let (m, tv) = makeEditor("")
        tv.type("1. First item"); tv.insertNewline(nil)
        tv.type("2. Second item"); tv.insertNewline(nil)
        tv.type("4. Fourth item")
        XCTAssertEqual(tv.string, "1. First item\n2. Second item\n4. Fourth item")
        XCTAssertEqual(m.markdown(), "1. First item\n\n2. Second item\n\n4. Fourth item\n")
        // no list structure was created
        for p in 0..<3 { XCTAssertEqual(tv.block(atParagraphStartOf: tv.string.split(separator: "\n", omittingEmptySubsequences: false).prefix(p).reduce(0) { $0 + $1.count + 1 })?.kind, .paragraph) }
    }

    func testExistingListKeepsGapsAndReturnDoesNotContinueTheList() {
        let (m, tv) = makeEditor("1. First item\n2. Second item\n4. Fourth item\n")
        tv.caret(tv.string.count)
        tv.insertNewline(nil)
        tv.type("5. Fifth")
        XCTAssertEqual(tv.string, "1.\tFirst item\n2.\tSecond item\n4.\tFourth item\n5. Fifth")
        XCTAssertEqual(m.markdown(), "1. First item\n2. Second item\n4. Fourth item\n\n5. Fifth\n")
        let last = tv.block(atParagraphStartOf: tv.string.count - 1)!
        XCTAssertEqual(last.kind, .paragraph)
        let style = tv.textStorage!.attribute(.paragraphStyle, at: tv.string.count - 1, effectiveRange: nil) as! NSParagraphStyle
        XCTAssertEqual(style.firstLineHeadIndent, 0) // only wrapped lines align with the text
    }

    func testNumberedListCommandNumbersOnceAndNothingRenumbersLater() {
        let (m, tv) = makeEditor("alpha\n\nbeta\n\ngamma\n")
        tv.selectAll(nil)
        tv.wmdToggleNumbered(nil)
        XCTAssertEqual(m.markdown(), "1. alpha\n\n2. beta\n\n3. gamma\n")
        // delete the middle item: the others keep their numbers
        tv.select("2.\tbeta\n")
        tv.delete(nil)
        XCTAssertEqual(m.markdown(), "1. alpha\n\n3. gamma\n")
    }

    func testBulletsKeepSourceMarker() {
        let (m, tv) = makeEditor("* star\n* two\n")
        XCTAssertEqual(tv.string, "\u{2022}\tstar\n\u{2022}\ttwo")
        tv.caret(after: "star"); tv.type("!")
        XCTAssertEqual(m.markdown(), "* star!\n* two\n")
    }

    // MARK: Return / Tab / Backspace

    func testReturnInsideParagraphSplitsWithoutChangingStyle() {
        let (m, tv) = makeEditor("Hello world\n")
        tv.caret(after: "Hello")
        tv.insertNewline(nil)
        XCTAssertEqual(tv.string, "Hello\n world")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 6, length: 0))
        XCTAssertEqual(m.markdown(), "Hello\n\n world\n")
    }

    func testReturnAtEndOfHeadingGivesNormalParagraph() {
        let (m, tv) = makeEditor("# Title\n")
        tv.caret(tv.string.count)
        tv.insertNewline(nil)
        tv.type("text")
        XCTAssertEqual(m.markdown(), "# Title\n\ntext\n")
    }

    func testTabInsertsATabAndChangesNothingElse() {
        let (m, tv) = makeEditor("1. one\n2. two\n")
        tv.caret(after: "two")
        tv.insertTab(nil)
        tv.insertBacktab(nil)
        XCTAssertEqual(tv.string, "1.\tone\n2.\ttwo\t")
        XCTAssertEqual(m.markdown(), "1. one\n2. two\t\n")
        XCTAssertEqual(tv.block(atParagraphStartOf: 0)?.kind, .listItem)
    }

    func testBackspaceAtStartOfListTextDoesNotRestructure() {
        let (m, tv) = makeEditor("1. one\n2. two\n")
        tv.caret(after: "2.\t")
        tv.deleteBackward(nil)
        XCTAssertEqual(tv.string, "1.\tone\n2.two")
        XCTAssertEqual(tv.block(atParagraphStartOf: 7)?.kind, .listItem)
        _ = m
    }

    func testCodeBlockReturnKeepsLinesInOneFence() {
        let (m, tv) = makeEditor("```r\nx <- 1\n```\n")
        tv.caret(after: "x <- 1")
        tv.insertNewline(nil)
        tv.type("y <- *2*  ")
        XCTAssertEqual(m.markdown(), "```r\nx <- 1\ny <- *2*  \n```\n")
    }

    func testCodeContentIsNeverEscapedOrReinterpreted() {
        let (m, tv) = makeEditor("```\na\n```\n")
        tv.caret(after: "a")
        tv.type(" **b** _c_ `d` [e](f) \\ <g>  ")
        XCTAssertEqual(m.markdown(), "```\na **b** _c_ `d` [e](f) \\ <g>  \n```\n")
    }

    // MARK: Pasting

    func testPasteIsPlainTextAndLiteral() {
        let (m, tv) = makeEditor("start\n")
        tv.caret(after: "start")
        tv.insertPlain(" **not bold**\r\nsecond line")
        XCTAssertEqual(tv.string, "start **not bold**\nsecond line")
        XCTAssertEqual(m.markdown(), "start \\*\\*not bold\\*\\*\n\nsecond line\n")
        XCTAssertTrue(tv.textStorage!.attribute(.wmdFlags, at: 8, effectiveRange: nil).flatMap { InlineFlags.from($0) }?.isEmpty ?? true)
    }

    // MARK: Formatting commands

    func testBoldItalicSurviveSaveAndReopen() {
        let (m, tv) = makeEditor("make bold and italic words\n")
        tv.select("bold"); tv.wmdToggleBold(nil)
        tv.select("italic"); tv.wmdToggleItalic(nil)
        tv.select("words"); tv.wmdToggleBold(nil); tv.wmdToggleItalic(nil)
        let saved = m.markdown()
        XCTAssertEqual(saved, "make **bold** and *italic* ***words***\n")
        let again = loadModel(saved)
        XCTAssertEqual(again.storage.string, "make bold and italic words")
        func flags(_ s: String) -> InlineFlags {
            let r = (again.storage.string as NSString).range(of: s)
            return InlineFlags.from(again.storage.attribute(.wmdFlags, at: r.location, effectiveRange: nil))
        }
        XCTAssertEqual(flags("bold"), .bold)
        XCTAssertEqual(flags("italic"), .italic)
        XCTAssertEqual(flags("words"), [.bold, .italic])
        XCTAssertEqual(again.markdown(), saved)
    }

    func testBoldTogglesOff() {
        let (m, tv) = makeEditor("a **b** c\n")
        tv.select("b"); tv.wmdToggleBold(nil)
        XCTAssertEqual(m.markdown(), "a b c\n")
    }

    func testBoldSelectionWithTrailingSpaceKeepsValidMarkdown() {
        let (m, tv) = makeEditor("one two three\n")
        tv.select("two "); tv.wmdToggleBold(nil)
        XCTAssertEqual(m.markdown(), "one **two** three\n")
    }

    func testBoldAtCaretAppliesToNextTypedText() {
        let (m, tv) = makeEditor("x\n")
        tv.caret(1)
        tv.wmdToggleBold(nil)
        tv.type("yz")
        XCTAssertEqual(m.markdown(), "x**yz**\n")
    }

    func testInlineCodeAndSpecialCharsEscaping() {
        let (m, tv) = makeEditor("call f now\n")
        tv.select("f"); tv.wmdToggleCode(nil)
        XCTAssertEqual(m.markdown(), "call `f` now\n")
        tv.caret(tv.string.count); tv.type(" 2*3 a*b")
        XCTAssertEqual(m.markdown(), "call `f` now 2\\*3 a\\*b\n")
    }

    func testHeadingsAndToggles() {
        let (m, tv) = makeEditor("Title\n\nBody\n")
        tv.caret(2)
        tv.wmdSetHeading(menuItem(2))
        XCTAssertEqual(m.markdown(), "## Title\n\nBody\n")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 2, length: 0))
        tv.wmdSetHeading(menuItem(2)) // toggles back
        XCTAssertEqual(m.markdown(), "Title\n\nBody\n")
        tv.wmdSetHeading(menuItem(1)); tv.wmdSetParagraph(nil)
        XCTAssertEqual(m.markdown(), "Title\n\nBody\n")
    }

    func testQuoteCodeBlockAndRule() {
        let (m, tv) = makeEditor("one\n\ntwo\n")
        tv.caret(1); tv.wmdToggleQuote(nil)
        XCTAssertEqual(m.markdown(), "> one\n\ntwo\n")
        tv.caret(tv.string.count); tv.wmdToggleCodeBlock(nil)
        XCTAssertEqual(m.markdown(), "> one\n\n```\ntwo\n```\n")
        tv.caret(1); tv.wmdInsertRule(nil)
        XCTAssertEqual(m.markdown(), "> one\n\n---\n\n```\ntwo\n```\n")
        tv.caret(tv.string.count); tv.wmdToggleCodeBlock(nil)
        XCTAssertEqual(m.markdown(), "> one\n\n---\n\ntwo\n")
    }

    func testSettingHeadingOnListItemDropsTheMarker() {
        let (m, tv) = makeEditor("3. item\n")
        tv.caret(4); tv.wmdSetHeading(menuItem(3))
        XCTAssertEqual(m.markdown(), "### item\n")
        XCTAssertEqual(tv.string, "item")
    }

    func testLinkSetAndRemove() {
        let (m, tv) = makeEditor("see docs here\n")
        tv.select("docs")
        var sel = tv.selectedRange()
        tv.setLink("https://example.com/a_b", in: &sel)
        XCTAssertEqual(m.markdown(), "see [docs](https://example.com/a_b) here\n")
        sel = NSRange(location: 4, length: 4)
        tv.setLink(nil, in: &sel)
        XCTAssertEqual(m.markdown(), "see docs here\n")
    }

    func menuItem(_ tag: Int) -> NSMenuItem {
        let i = NSMenuItem(); i.tag = tag; return i
    }

    // MARK: Unsupported constructs survive editing around them

    func testUnsupportedConstructsSurviveNeighbourEdits() {
        let src = "---\ntitle: t\n---\n\nIntro\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n<div>\nhtml *x*\n</div>\n\n    indented code\n\n$$\nx^2\n$$\n\n[1]: http://x.y\n\nOutro\n"
        let (m, tv) = makeEditor(src)
        tv.caret(after: "Intro"); tv.type("!")
        tv.caret(tv.string.count); tv.type("?")
        XCTAssertEqual(m.markdown(), src.replacingOccurrences(of: "Intro", with: "Intro!").replacingOccurrences(of: "Outro", with: "Outro?"))
    }

    func testEditingInsideVerbatimTableKeepsItAsWritten() {
        let src = "| a | b |\n|---|---|\n| 1 | 2 |\n"
        let (m, tv) = makeEditor(src)
        tv.caret(after: "| 1"); tv.type("0")
        XCTAssertEqual(m.markdown(), "| a | b |\n|---|---|\n| 10 | 2 |\n")
    }

    // MARK: Undo / redo

    func testUndoRedoKeepsDocumentConsistent() {
        let src = "# Title\n\nParagraph one.\n\n1. a\n2. b\n"
        let (m, tv) = makeEditor(src)
        let um = tv.undoManager!
        um.groupsByEvent = false

        func step(_ name: String, _ f: () -> Void) {
            um.beginUndoGrouping(); f(); um.endUndoGrouping()
        }
        var states = [m.markdown()]
        tv.caret(after: "Paragraph")
        step("insert") { tv.type("!") }; states.append(m.markdown())
        step("return") { tv.insertNewline(nil) }; states.append(m.markdown())
        tv.select("one")
        step("bold") { tv.wmdToggleBold(nil) }; states.append(m.markdown())
        tv.caret(2)
        step("h2") { tv.wmdSetHeading(menuItem(2)) }; states.append(m.markdown())
        step("rule") { tv.wmdInsertRule(nil) }; states.append(m.markdown())

        XCTAssertEqual(states.count, 6)
        XCTAssertEqual(Set(states).count, 6, "each step must change the document")
        for i in stride(from: states.count - 2, through: 0, by: -1) {
            um.undo()
            XCTAssertEqual(m.markdown(), states[i], "after undo to state \(i)")
        }
        XCTAssertEqual(m.markdown(), src)
        for i in 1..<states.count {
            um.redo()
            XCTAssertEqual(m.markdown(), states[i], "after redo to state \(i)")
        }
    }

    func testTypingIsGroupedIntoOneUndoStep() {
        let (m, tv) = makeEditor("x\n")
        let um = tv.undoManager!
        um.groupsByEvent = false
        tv.caret(1)
        um.beginUndoGrouping()
        for ch in "hello" { tv.type(String(ch)) }
        um.endUndoGrouping()
        XCTAssertEqual(m.markdown(), "xhello\n")
        um.undo()
        XCTAssertEqual(m.markdown(), "x\n")
    }

    // MARK: Cursor / selection stability

    func testSelectionStaysPutDuringInlineFormatting() {
        let (_, tv) = makeEditor("abc def ghi\n")
        tv.select("def")
        let sel = tv.selectedRange()
        tv.wmdToggleBold(nil)
        XCTAssertEqual(tv.selectedRange(), sel)
        tv.wmdToggleItalic(nil)
        XCTAssertEqual(tv.selectedRange(), sel)
        tv.wmdToggleBold(nil)
        XCTAssertEqual(tv.selectedRange(), sel)
    }

    func testCaretDoesNotMoveWhenOtherParagraphsAreEditedProgrammatically() {
        let (m, tv) = makeEditor("one\n\ntwo\n\nthree\n")
        tv.caret(after: "tw")
        let before = tv.selectedRange()
        let st = tv.textStorage!
        st.replaceCharacters(in: NSRange(location: 0, length: 0), with: "") // no-op edit
        XCTAssertEqual(tv.selectedRange(), before)
        tv.type("X")
        XCTAssertEqual(tv.selectedRange().location, before.location + 1)
        XCTAssertEqual(m.markdown(), "one\n\ntwXo\n\nthree\n")
    }

    func testCaretStaysAfterHeadingAndListConversion() {
        let (_, tv) = makeEditor("hello world\n")
        tv.caret(after: "hello ")
        tv.wmdToggleBullets(nil)
        XCTAssertEqual(tv.string, "\u{2022}\thello world")
        XCTAssertEqual(tv.selectedRange().location, 8)
        tv.wmdToggleBullets(nil)
        XCTAssertEqual(tv.string, "hello world")
        XCTAssertEqual(tv.selectedRange().location, 6)
    }

    // MARK: Appearance

    func testHangingIndentUsesParagraphStyleNotSpaces() {
        let long = "1.  " + String(repeating: "A long paragraph that wraps onto the next line. ", count: 4)
        let (_, tv) = makeEditor(long + "\n", width: 420)
        XCTAssertFalse(tv.string.contains("  "))
        let style = tv.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
        XCTAssertEqual(style.firstLineHeadIndent, 0)
        XCTAssertGreaterThan(style.headIndent, 20)
        XCTAssertEqual(style.tabStops.first?.location, style.headIndent)

        let lm = tv.layoutManager!
        lm.ensureLayout(for: tv.textContainer!)
        var frags: [NSRect] = []
        var used: [NSRect] = []
        lm.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: lm.numberOfGlyphs)) { rect, usedRect, _, _, _ in
            frags.append(rect); used.append(usedRect)
        }
        XCTAssertGreaterThan(frags.count, 2)
        // marker sits at the left margin of the first line
        XCTAssertEqual(used[0].minX - frags[0].minX, 0, accuracy: 0.5)
        // text after the tab starts exactly where wrapped lines start
        let textGlyph = lm.glyphIndexForCharacter(at: 3)
        let textX = lm.location(forGlyphAt: textGlyph).x + lm.lineFragmentRect(forGlyphAt: textGlyph, effectiveRange: nil).minX
        let g1 = lm.glyphRange(forCharacterRange: NSRange(location: 0, length: 0), actualCharacterRange: nil)
        _ = g1
        var secondFirstGlyph = 0
        lm.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: lm.numberOfGlyphs)) { _, _, _, gr, stop in
            if gr.location > 0 { secondFirstGlyph = gr.location; stop.pointee = true }
        }
        let wrappedX = lm.location(forGlyphAt: secondFirstGlyph).x + lm.lineFragmentRect(forGlyphAt: secondFirstGlyph, effectiveRange: nil).minX
        XCTAssertEqual(textX, wrappedX, accuracy: 0.5, "wrapped lines must align with the text, not the number")
        XCTAssertEqual(used[2].minX, used[1].minX, accuracy: 0.5)
    }

    func testStyleAfterEditingStaysDerivedNotAccumulated() {
        let (_, tv) = makeEditor("# Head\n\nbody\n")
        let st = tv.textStorage!
        let h = st.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        XCTAssertEqual(h.pointSize, Styler.headingSizes[0])
        tv.caret(after: "bo"); tv.type("x")
        let b = st.attribute(.font, at: st.length - 1, effectiveRange: nil) as! NSFont
        XCTAssertEqual(b.pointSize, Styler.bodySize)
    }
}

final class ManualHangingIndentTests: XCTestCase {
    func testTypedNumberingGetsHangingIndentWithoutBecomingAList() {
        let (m, tv) = makeEditor("")
        tv.type("1.  " + String(repeating: "wrapped words here ", count: 12))
        let st = tv.textStorage!
        let style = st.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
        XCTAssertEqual(style.firstLineHeadIndent, 0)
        XCTAssertGreaterThan(style.headIndent, 10)
        XCTAssertEqual(tv.block(atParagraphStartOf: 0)?.kind, .paragraph)
        XCTAssertTrue(m.markdown().hasPrefix("1.  wrapped"))
        // plain text gets none
        tv.insertNewline(nil); tv.type("no marker here")
        let last = st.attribute(.paragraphStyle, at: st.length - 1, effectiveRange: nil) as! NSParagraphStyle
        XCTAssertEqual(last.headIndent, 0)
    }
}

final class PasteTests: XCTestCase {
    func testMultiLinePasteAtEnd() {
        let (m, tv) = makeEditor("alpha\n\nsecond\n")
        tv.caret(tv.string.count)
        tv.insertPlain("line one\n\nline two\n")
        XCTAssertEqual(tv.string, "alpha\nsecondline one\n\nline two\n")
        XCTAssertTrue(m.markdown().contains("line two"))
    }
}

final class TabHangTests: XCTestCase {
    func testTypedMarkerTabTextHangsAtTabStop() {
        let (m, tv) = makeEditor("")
        tv.type("1.")
        tv.insertTab(nil)
        tv.type(String(repeating: "wrapped words here ", count: 12))
        let st = tv.textStorage!
        let style = st.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
        XCTAssertEqual(style.firstLineHeadIndent, 0)
        XCTAssertGreaterThanOrEqual(style.headIndent, 26)
        XCTAssertEqual(style.tabStops.first?.location, style.headIndent)
        XCTAssertEqual(tv.block(atParagraphStartOf: 0)?.kind, .paragraph)
        XCTAssertTrue(m.markdown().hasPrefix("1.\twrapped"))
    }
}

final class CopyTests: XCTestCase {
    func testWriteSelectionPutsTextOnPasteboard() {
        let (_, tv) = makeEditor("alpha **beta**\n\n1. one\n")
        tv.selectAll(nil)
        let pb = NSPasteboard(name: NSPasteboard.Name("com.musikutiv.writemd.test"))
        pb.clearContents()
        XCTAssertTrue(tv.writeSelection(to: pb, types: tv.writablePasteboardTypes))
        XCTAssertNotNil(pb.string(forType: .string))
        XCTAssertTrue(pb.types?.contains(.rtf) ?? false)
        pb.releaseGlobally()
    }
}
