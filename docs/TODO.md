# Specification TODOs

## Tasks

- Assign semantics to node types, paragraph kinds, ...
- Specify "syntax" proper
- Add links to RFCs where possible
- Span attribute semantics are referenced but not fully defined. §8.2 introduces spans with an “attribute set (e.g. emphasis/monospace/link…)” but the spec never fully defines the canonical attribute keys, nesting behavior (e.g., \em inside \mono), or how lang overrides interact at span level. That’s a major interoperability risk because renderers may differ even if parsers agree. 
- Refine that `hdoc(title)` is metadata while `title{}` is rendered rich text
- Ambiguity of Inline Unicode:
  - Finding: String literals ("...") support \u{...} escapes (§7.2.1). Inline text streams (bodies of p, h1) do not (§6.1 only lists \\, \{, \}).
  - Issue: Authors cannot enter invisible characters (like Non-Breaking Space U+00A0 or Zero Width Space U+200B) into a paragraph without pasting the raw invisible character, which is brittle and invisible in editors.
- Issue: "Lexical" implies only regex-level matching. It does not strictly forbid 2023-02-31. For a strict format, "Semantic" validity (Gregorian correctness) should be enforced to prevent invalid metadata.

## Potential Future Features

### `hr;` or `break;`

Purpose: Explicit scene/topic breaks within prose (equivalent to HTML <hr>).

Attributes:
  id (optional; top-level only)
Body:
  ; (empty)
Constraints:
  - MUST be top-level or inside block containers that allow general text blocks
  - MUST NOT appear inside inline contexts

Rationale:
  Common typographic convention for section breaks that are less formal than headings. Currently missing; authors might abuse pre: or empty paragraphs as workarounds.

### `\plain`

Finding: Attributes like lang are supported on \em, \mono, etc. However, if an author needs to mark a plain-text span as a different language (e.g., "The word Angst (German) means...") without applying italics or monospace, there is no element to hold the lang attribute.

### `table{title{}}` or `table(caption="")` + `img(caption="")`

x(caption) composes well with `\ref(ref)`.

table title is good for accesibility.

### `\br;` inline

Introduce \br for Hard Line Breaks: Since whitespace normalization collapses \n to space, there is currently no way to force a line break within a paragraph (e.g., for postal addresses or poetry) without using pre. Adding a \br inline element would resolve this semantic gap.

### `appendix` element

- Support "appendix{}" in addition to h1,h2,h3 which is a h1-level chapter that renders as "A. B. C." instead of "1. 2. 3."

### Abbreviations

- \abbrev(title="Antiblockiersystem"){ABS} defines a new abbreviation
- \abbrev{ABS} references an existing abbreviation
- \abbrev(title) can only be set once.
- glossary; emits a glossary/definition list of all abbreviations

### Definition Lists

- deflist {structural} is a definition list
- term {inline} defines a new term, must be followed by a 
- def { blocks } definition for the term

### Glossary

- \indexed{Word} adds a new entry to the index.
- index; emits an index with refs to all `\index`ed words.

### Formal Whitespace Processing Algorithm

Write a formal definition of the whitespace processing algorithm so it can be easily replicated.

### Formal Language Schema

Recommendation 5: Add Appendix with Formal Schema
Rationale: Current spec requires reading entire document to understand element relationships. Machine-readable schema would enable automatic validation and tooling.
Provide RelaxNG Compact syntax schema defining:

### Highlighted Lines and Line Numbering

Rationale: Technical documentation needs to emphasize specific code lines (tutorials, diffs, explanations).
pre(syntax="python", highlight="2,4-6"):
| def factorial(n):
|     if n == 0:  # Base case
|         return 1
|     else:
|         return n * factorial(n-1)  # Recursive case
also: enable line numbers

### Attribution

```hdoc
quote {
  p "Premature optimization is the root of all evil."
  attribution "Donald Knuth"
}
```

## Rejected Features

- `\kbd{…}` is just `\mono(syntax="kbd"){…}`
- `include(path="...")` is rejected for unbounded document content growth
- `code` is just `\mono(syntax="…")`
- `details/summary` is just HTML with dynamic changing page layout, ever tried printing this?
- `\math`, `equation{…}` have too high implementation complexity and have high requirements on fonts, font renderers and layout engines.
