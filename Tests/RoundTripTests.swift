import XCTest

/// Opening and saving without edits must reproduce the file byte for byte.
final class RoundTripTests: XCTestCase {
    func assertStable(_ s: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(roundTrip(s), s, file: file, line: line)
    }

    func testEmptyAndTiny() {
        assertStable("")
        assertStable("\n")
        assertStable("\n\n\n")
        assertStable("x")
        assertStable("x\n")
        assertStable("x\n\n\n")
        assertStable("\n\nleading blank lines\n")
        assertStable("   \n")
    }

    func testParagraphsAndInline() {
        assertStable("Plain paragraph with **bold**, *italic*, __bold__, _italic_, ***both***, `code` and `` a`b ``.\n")
        assertStable("Line one\nline two  \nline three\\\nline four\n\nSecond paragraph\n")
        assertStable("A [link](http://example.com \"Title\") and ![image](a_b*c.png) and <span>html</span> and <http://x.y/a_b_c>.\n")
        assertStable("Math $x_i * y_j$ and $$a*b*c$$ and 2 * 3 and snake_case_name and \\* escaped \\_ chars.\n")
        assertStable("Footnote[^1] and [ref][1] and [bare].\n\n[1]: http://example.com\n[^1]: The note.\n")
        assertStable("   indented paragraph\n   continues here\n")
    }

    func testHeadings() {
        assertStable("# H1\n\n## H2 ##\n\n###### H6\n\n#\n\n#Not a heading\n")
        assertStable("Setext One\n==========\n\nSetext Two\n----------\n\nafter\n")
        assertStable("# Tight\ntext right after\n")
    }

    func testListsKeepTheirNumbersAndLayout() {
        assertStable("1. First item\n2. Second item\n4. Fourth item\n")
        assertStable("1.  Two spaces\n2.  after the marker\n")
        assertStable("- a\n- b\n  continued\n    - nested\n\n- loose\n")
        assertStable("* star\n+ plus\n- dash\n")
        assertStable("10) ten\n11) eleven\n")
        assertStable("1. one\n\n   second paragraph of item\n\n2. two\n")
        assertStable("- [ ] todo\n- [x] done\n")
        assertStable("3. starts at three\n3. and stays three\n")
        assertStable("text\n- list right after text\n")
    }

    func testQuotesRulesTablesHTML() {
        assertStable("> quoted\n> more\n\n> > nested\n\n>\n> blank above\n")
        assertStable("---\n\n***\n\n- - -\n\n___\n")
        assertStable("| a | b |\n|---|:-:|\n| 1 | 2 |\n\ntext\n")
        assertStable("a | b\n--|--\n1 | 2\n")
        assertStable("<div class=\"x\">\n*not emphasis*\n\n</div>\n\n<!-- comment\n\nspanning -->\n\ntext\n")
    }

    func testCodeIsPreservedExactly() {
        assertStable("```python\ndef f(x):\n\treturn  x *  2   \n\n\n    # spaces\n```\n")
        assertStable("~~~\ntilde\n~~~\n")
        assertStable("````\n```\nnested fence\n```\n````\n")
        assertStable("```\nunclosed fence\nstill code\n")
        assertStable("```\n```\n")
        assertStable("    indented code\n    more\n\nafter\n")
        assertStable("- item\n\n      code in item\n")
    }

    func testFrontMatterAndRMarkdown() {
        assertStable("---\ntitle: \"A: b\"\nauthor: me\n---\n\n# Hi\n\n```{r setup, include=FALSE}\nknitr::opts_chunk$set(echo = TRUE)\n```\n\nInline `r 1+1` code.\n")
        assertStable("---\ntitle: x\n---\n")
        assertStable("---\nnot closed front matter\n\ntext\n")
    }

    func testLineEndingsBomAndFinalNewline() {
        assertStable("a\r\n\r\nb\r\n")
        assertStable("a\r\n- b\r\n- c")
        assertStable("\u{FEFF}# bom\n")
        assertStable("no final newline")
        assertStable("two blank lines at end\n\n\n")
    }

    func testBadUTF8IsRefused() {
        let m = EditorModel()
        XCTAssertThrowsError(try m.load(data: Data([0xFF, 0xFE, 0x41])))
    }

    func testUnicodeAndEmoji() {
        assertStable("# Größe 日本語 🎉\n\nÄpfel **fett** 😀 *kursiv*\n\n- 🍎 eins\n- 🍐 zwei\n")
    }

    func testLargeDocumentRoundTrips() {
        var s = ""
        for i in 0..<2000 {
            s += "## Section \(i)\n\nParagraph \(i) with **bold** and *italic* and `code`.\n\n1. one\n2. two\n4. four\n\n```r\nx <- \(i)\n```\n\n"
        }
        assertStable(s)
    }
}
