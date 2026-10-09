# WriteMD

A tiny, native macOS Markdown editor. You edit the *rendered* document directly (headings look like
headings, bold looks bold), the file on disk stays plain Markdown, and the editor never formats anything
on your behalf. Think TextEdit with `.md` as its file format.

Swift + AppKit (`NSTextView`/`NSTextStorage`, TextKit 1). No web view, no JavaScript, no network, no
background processes, no dependencies. Sandboxed, without the network entitlement.

## Behaviour you can rely on

- **No automatic formatting.** Typing `1.` or `-` does nothing special. Return never continues a list,
  Tab inserts a tab character, Backspace never restructures anything, nothing renumbers. A document with
  `1. 2. 4.` stays `1. 2. 4.`
- **Return** starts a new plain paragraph (a new line in a code block, a new quote paragraph in a quote).
  After a heading the new paragraph is plain.
- **Paste** is always plain text, literal (`**x**` stays visible asterisks). Paste and Match Style is the same.
- **Open + Save without edits is byte-identical.** Each block remembers its exact source; only blocks
  you edit are rewritten. CRLF, BOM, final newline and blank-line spacing are preserved.
- **Hanging indents** are real paragraph indents + a tab stop, never spaces.
- Explicit list commands create list items once; numbers are ordinary text you can change.

## Shortcuts

| | |
|---|---|
| Bold / Italic / Code / Link | ⌘B / ⌘I / ⌘E / ⌘K |
| Paragraph / Heading 1–6 | ⌘0 / ⌘1 … ⌘6 (again = back to paragraph) |
| Quote / Bullets / Numbers / Code block | ⌥⌘Q / ⌥⌘U / ⌥⌘O / ⌥⌘C |
| Horizontal rule | ⌥⌘- |

Files: `.md`, `.markdown` (and `.Rmd`, `.qmd`; nothing is ever executed). UTF-8 only. Saving is always
explicit (no autosave-in-place).

## Build

```sh
brew install xcodegen      # once
scripts/build.sh           # Release app -> build/Build/Products/Release/WriteMD.app
scripts/build.sh test      # unit tests
```

Ad-hoc signed; no Developer account needed. First launch of a copied build: right-click → Open, or
`xattr -cr WriteMD.app`.

## Limitations (see docs/ARCHITECTURE.md)

Tables, HTML, YAML front matter, indented code, math blocks and reference definitions are shown as
monospace *verbatim* blocks and saved exactly as written (editable as text, not as tables). Images and
inline HTML show as literal source. A block you edit is re-serialized: emphasis is normalised to `**`/`*`,
`#` closing sequences and `> ` spacing are normalised. Two paragraphs you type are separated by a blank
line, as Markdown requires. Mixed line endings become the dominant style when a file is saved after edits.
