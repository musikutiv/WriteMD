# Architecture

## Why NSTextView
A native attributed-text editor gives caret, selection, undo, spelling, find, input methods and
accessibility for free, with tiny memory. contenteditable would add a browser engine and make cursor and
undo fidelity depend on DOM edits. TextKit 1 is used (explicit `NSLayoutManager`) for predictable
paragraph layout and non-contiguous layout on long documents.

## Document model
Markdown is never regenerated per keystroke. The text storage contains *rendered* text only. Every paragraph
carries a `Block` (kind, original source, trailing whitespace); inline state is a flags attribute
(bold/italic/code/raw/escaped) plus `.link`. Fonts, colours and paragraph styles are *derived* by
`Styler.restyle`, run only on the edited paragraph ±1 after each edit.

Saving (`EditorModel.markdown`): consecutive paragraphs form units (one per block; code/verbatim lines
share a Block). A clean unit emits its original source. A dirty unit is re-serialized; if that equals the
serialization of its own original source (e.g. edit then undo) the original text is emitted. Separators come
from the original trailing whitespace, upgraded to a blank line only next to new/changed blocks.

## Lists
A list marker is literal text (`4.\t…`; bullets show `•` and remember their source char). Hanging indent =
`headIndent` + tab stop. Nothing renumbers, ever. Typed `1.`/`#` at paragraph start is saved verbatim
(and so becomes structure when reopened).

## Risks / decisions
- Return/format commands replace whole paragraphs inside one `shouldChangeText` so undo restores blocks.
- Typing attributes in a trailing empty paragraph are recomputed on selection change.
- Block parser is conservative: anything uncertain becomes a verbatim block.
- Not implemented: table editing, images, nested blocks inside quotes/list items, task-list checkboxes.
