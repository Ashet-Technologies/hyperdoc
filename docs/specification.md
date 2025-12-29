# HyperDoc 2.0

This specification describes the document markup language "HyperDoc 2.0", that tries to be a simple to parse, easy to write markup language for hypertext documents.

It sits in a space where it's unambigious to parse, but still relatively convenient to write.

## Syntax Overview

```hdoc
hdoc(version="2.0");

h1 "Introduction"

p {
  This is my first HyperDoc 2.0 document!
}

pre(syntax="c"):
| #include <stdio.h>
| int main(int argc, char *argv[]) {
|   printf("Hello, World!");
|   return 0;
| }
```

## Document encoding

This section defines the required byte-level encoding and line structure of HyperDoc documents.

### Character encoding

- A HyperDoc document **MUST** be encoded as **UTF-8**.
- A HyperDoc document **MUST NOT** contain invalid UTF-8 byte sequences.

**Byte Order Mark (BOM):**

- A UTF-8 BOM (the byte sequence `EF BB BF`) **SHOULD NOT** be used. Tooling **MAY** accept it and treat it as U+FEFF at the beginning of the document.

### Line endings

- Lines **MUST** be terminated by either:
  - `<LF>` (U+000A), or
  - `<CR><LF>` (U+000D U+000A).
- A bare `<CR>` **MUST NOT** appear except as part of a `<CR><LF>` sequence.

A document **MAY** mix `<LF>` and `<CR><LF>` line endings, but tooling **SHOULD** normalize to a single convention when rewriting documents.

The canonical line ending emitted by tooling **SHOULD** be `<LF>`.

### Control characters

- The only permitted control character **within a line** is:
  - `<TAB>` (U+0009).
- Apart from line terminators (`<LF>` and `<CR>` only as part of `<CR><LF>`), all other Unicode control characters (General Category `Cc`) **MUST NOT** appear anywhere in a HyperDoc document.

### Unicode text

- Apart from the restrictions above, arbitrary Unicode text is allowed.

### Recommendations for writing systems and directionality (non-normative)

HyperDoc does not define special handling for right-to-left scripts, bidirectional layout, or writing system segmentation. For readability and to reduce ambiguity across renderers and editors:

- Authors **SHOULD** keep each paragraph primarily in a **single writing system/directionality** where practical.
- Tooling **MAY** warn when a paragraph mixes strongly different directional scripts or contains invisible bidirectional formatting characters (e.g., bidi overrides/isolates), since these can be confusing in editors and reviews.

## Syntax

This chapter defines the **syntactic structure** of HyperDoc documents: how characters form tokens, how tokens form **nodes**, and how nodes nest. It intentionally does **not** define meaning (required elements, allowed attributes per node type, ID/refs, allowed escape sequences, etc.). Those are handled in later chapters as **semantic validity** rules.

A HyperDoc document is a sequence of **nodes**. Each node has:

- a **node name** (identifier),
- an optional **attribute list** `(key="value", ...)`,
- and a mandatory **body**, which is one of:
  - `;` empty body,
  - `"..."` string literal body,
  - `:` verbatim body (one or more `|` lines),
  - `{ ... }` list body.

A list body `{ ... }` is parsed in one of two modes:

- **Block-list mode**: the list contains nested nodes.
- **Inline-list mode**: the list contains a token stream of text items, escape tokens, inline nodes, and balanced brace groups.

The grammar below is syntax-only and intentionally leaves the choice between block-list and inline-list content to an **external disambiguation rule**.

### Grammar (EBNF)

```ebnf
(* ---------- Top level ---------- *)

document        ::= ws , { node , ws } , EOF ;

(* ---------- Nodes ---------- *)

node            ::= node_name , ws , [ attribute_list , ws ] , body ;

body            ::= empty_body
                  | string_body
                  | verbatim_body
                  | list_body ;

empty_body      ::= ";" ;

string_body     ::= string_literal ;

verbatim_body   ::= ":" , { ws , piped_line } ;

list_body       ::= "{" , list_content , "}" ;

(*
  IMPORTANT: list_content is intentionally ambiguous.
  A conforming parser chooses either inline_content or block_content by an
  EXTERNAL rule (see “Disambiguation for list bodies”).
*)
list_content    ::= inline_content | block_content ;


(* ---------- Attributes ---------- *)

attribute_list  ::= "(" , ws ,
                    [ attribute ,
                      { ws , "," , ws , attribute } ,
                      [ ws , "," ]          (* trailing comma allowed *)
                    ] ,
                    ws , ")" ;

attribute       ::= attr_key , ws , "=" , ws , string_literal ;

(*
  Attribute keys may include '-' and ':' in addition to node-name characters.
*)
attr_key        ::= attr_key_char , { attr_key_char } ;

attr_key_char   ::= "A"…"Z" | "a"…"z" | "0"…"9" | "_" | "-" | "\" ;


(* ---------- Block-list content ---------- *)

block_content   ::= ws , { node , ws } ;


(* ---------- Inline-list content ---------- *)

inline_content  ::= ws , { inline_item , ws } ;

inline_item     ::= word
                  | escape_text
                  | inline_node
                  | inline_group ;

(*
  Balanced braces in inline content are represented as inline_group.
  If braces cannot be balanced, they must be written as \{ and \}.
*)
inline_group    ::= "{" , inline_content , "}" ;

(*
  Backslash dispatch inside inline content:
  - If next char is one of '\', '{', '}', emit escape_text.
  - Otherwise begin an inline_node.
*)
escape_text     ::= "\" , ( "\" | "{" | "}" ) ;

inline_node     ::= inline_name , ws , [ attribute_list , ws ] , body ;

(*
  Inline node names start with '\' and then continue with node-name characters.
*)
inline_name     ::= "\" , node_name_char_no_backslash , { node_name_char } ;


(* ---------- Words / node names ---------- *)

(*
  Node names intentionally do NOT include ':' because ':' is also a body marker
  (e.g. 'p:' for verbatim body) and adjacency is allowed.
*)
node_name       ::= node_name_char , { node_name_char } ;

node_name_char  ::= "A"…"Z" | "a"…"z" | "0"…"9" | "_" | "-" | "\" ;

node_name_char_no_backslash
                ::= "A"…"Z" | "a"…"z" | "0"…"9" | "_" | "-" ;

word            ::= word_char , { word_char } ;

(*
  word_char matches any Unicode scalar value except:
  - whitespace
  - '{' or '}'
  - '\' (because '\' begins escape_text or inline_node)
*)
word_char       ::= ? any scalar value except WS, "{", "}", "\" ? ;


(* ---------- String literals (syntax only; no escape validation here) ---------- *)

string_literal  ::= "\"" , { string_unit } , "\"" ;

(*
  string_unit is permissive enough that malformed escapes remain parsable,
  BUT forbids escaping control characters (including LF/CR/TAB).
  Raw TAB is allowed as a normal string_char.
*)
string_unit     ::= string_char | "\" , escaped_noncontrol ;

string_char     ::= ? any scalar value except '"', '\', LF, CR ? ;

escaped_noncontrol
                ::= ? any scalar value except control chars (Unicode category Cc) ? ;


(* ---------- Verbatim lines ---------- *)

piped_line      ::= "|" , { not_line_end } , line_terminator ;

not_line_end    ::= ? any scalar value except CR and LF ? ;

line_terminator ::= LF | CR , LF | EOF ;


(* ---------- Whitespace ---------- *)

ws              ::= { WS } ;

WS              ::= " " | "\t" | CR | LF ;

CR              ::= "\r" ;
LF              ::= "\n" ;
```

### Additional syntax rules and notes (normative)

#### 1) Maximal-munch for identifiers

When reading `node_name`, `inline_name`, and `attr_key`, parsers **MUST** consume the **longest possible** sequence of allowed identifier characters (maximal munch). This is required because `\` is a legal identifier character and must not be arbitrarily split.

#### 2) Disambiguation for list bodies (external chooser)

The production `list_content ::= inline_content | block_content` is resolved by a deterministic, non-backtracking rule:

1. Before parsing the content of a `{ ... }` list body, the parser **MUST** choose exactly one list mode: **Inline-list mode** or **Block-list mode**.
2. The mode is determined solely from the syntactic **node name token** (not attributes, not body contents, not document state).
3. Required behavior (recovery-friendly):
   - If the node name begins with `\`, the parser **MUST** choose **Inline-list mode**.
   - If the node name is recognized as a built-in name with a specified list mode, the parser **MUST** choose that mode.
   - Otherwise (unknown / misspelled / unsupported node name), the parser **MUST** choose **Inline-list mode**.

This rule ensures unknown nodes accept rich inline content for typo recovery (e.g. `prre { ... }`).

#### 3) Inline-list mode: brace balancing and escape-text tokens

In **Inline-list mode**:

- `{` and `}` that appear as literal characters in the inline stream are represented structurally as `inline_group` and therefore **must be balanced**.
- If braces cannot be balanced, they **must** be written using the escape-text tokens `\{` and `\}`.
- A backslash in inline content is interpreted as:
  - one of the three **escape-text tokens** `\\`, `\{`, `\}`, or
  - the start of an `inline_node` otherwise.

The escape-text tokens exist primarily so the three characters `\`, `{`, `}` can be represented literally within inline content without always starting an inline node.

#### 4) String literals are syntax-only at this stage

String literals are delimited by `"` and parsed without interpreting escape meanings. This is intentional: documents with malformed or unknown escape sequences remain **syntactically valid**, allowing formatters and other tooling to round-trip source reliably.

However, the following are **syntactically invalid** inside string literals:

- raw LF or CR characters (line breaks are not allowed within `"..."`),
- a backslash immediately followed by a **control character** (Unicode General Category `Cc`), which includes TAB.

(Separately: which escape sequences are *semantically* valid is defined later.)

#### 5) Verbatim bodies are line-oriented

In a verbatim body (`:`):

- The body consists of zero or more `piped_line` entries.
- Each `piped_line` starts with `|` after optional whitespace skipping.
- The content of a verbatim line is everything up to the line terminator; it is not tokenized into nodes.

A file ending without a final newline is syntactically allowed (`EOF` as a line terminator), though tooling may warn.

#### 6) Syntactic validity vs semantic validity

A document is **syntactically valid** if it matches the grammar and the additional syntax rules above (maximal munch, list-mode disambiguation, inline brace balancing, and the string-literal constraints).

A syntactically valid document may still be **semantically invalid**. Semantic validation is defined later and may include rules such as required header nodes, attribute constraints, reference resolution, allowed escape sequences, encoding policy, and disallowed control characters in source text.

## Escape encoding

This chapter defines how **escape sequences are interpreted** to produce decoded Unicode text. Escape processing is part of **semantic validation**: a document may be syntactically valid even if it contains unknown or malformed escapes, but it is not semantically valid unless all escapes decode successfully under the rules below.

HyperDoc documents are UTF-8 text. Unless explicitly stated otherwise, all “characters” in this chapter refer to Unicode scalar values.

### Scope

Escape sequences are recognized in two places:

1. **STRING literals** (the `"..."` body form, and attribute values which are also STRING literals).
2. **Inline escape-text tokens** inside inline-list bodies: `\\`, `\{`, `\}` (these are emitted as text spans by the parser and can be decoded to literal characters during semantic processing).

No other part of the syntax performs escape decoding (not node names, not verbatim bodies, not block-list structure).

## Control character policy

HyperDoc forbids control characters except **LF** and **CR**.

- A semantically valid document **MUST NOT** contain any Unicode control characters (General Category `Cc`) anywhere **except**:
  - U+000A LINE FEED (LF)
  - U+000D CARRIAGE RETURN (CR)

This rule applies both to:

- the raw document text (source), and
- any decoded text produced from escapes.

Implications:

- TAB (U+0009) is forbidden, including if introduced via `\u{9}`.
- NUL (U+0000) is forbidden, including if introduced via `\u{0}`.

(Structural line breaks in the file may be LF or CRLF or CR as allowed by the syntax rules; decoded strings may contain LF/CR only via escapes.)

### String literal escape sequences

#### Overview

Within a STRING literal, a backslash (`\`) begins an escape sequence. The set of valid escapes is deliberately small.

A semantic validator/decoder **MUST** accept exactly the escape forms listed below and **MUST** reject all others.

#### Supported escapes (STRING literals)

The following escapes are valid inside STRING literals:

| Escape     | Decodes to                   |
| ---------- | ---------------------------- |
| `\\`       | U+005C REVERSE SOLIDUS (`\`) |
| `\"`       | U+0022 QUOTATION MARK (`"`)  |
| `\n`       | U+000A LINE FEED (LF)        |
| `\r`       | U+000D CARRIAGE RETURN (CR)  |
| `\u{H...}` | Unicode scalar value U+H...  |

No other escapes exist. In particular, `\0`, `\xHH`, `\e`, and similar are not part of HyperDoc.

#### Unicode escape `\u{H...}`

`H...` is a non-empty sequence of hexadecimal digits (`0–9`, `A–F`, `a–f`) representing a Unicode code point in hexadecimal.

Rules:

- The hex sequence **MUST** contain **1 to 6** hex digits.
- The value **MUST** be within `0x0 .. 0x10FFFF` inclusive.
- The value **MUST NOT** be in the surrogate range `0xD800 .. 0xDFFF`.
- The value **MUST NOT** decode to a forbidden control character (see Control character policy). The only allowed controls are LF and CR.

Notes:

- Leading zeros are allowed (`\u{000041}` is `A`).
- `\u{20}` is ASCII space. (`\u{032}` is U+0032, the digit `"2"`, because the digits are hexadecimal.)

#### Invalid escapes (STRING literals)

A semantic validator/decoder **MUST** reject a document (or at least reject that literal) if any STRING literal contains:

- an unknown escape (e.g. `\q`, `\uFFFF`, `\x20`, `\t`, `\b`, …),
- an unterminated escape (string ends immediately after `\`),
- a malformed Unicode escape (`\u{}`, missing `{`/`}`, non-hex digits, more than 6 hex digits),
- a Unicode escape outside the valid scalar range or within the surrogate range,
- a Unicode escape that produces a forbidden control character.

#### Canonical encoding recommendations (non-normative)

For authors and formatters:

- Prefer `\\` and `\"` for literal backslash and quote.
- Prefer `\n` and `\r` for LF/CR instead of `\u{A}` / `\u{D}`.
- Prefer the shortest hex form for `\u{...}` without leading zeros unless alignment/readability benefits.

### Inline escape-text tokens in inline-list bodies

Inside **inline-list bodies**, the syntax defines three special two-character text tokens:

- `\\`
- `\{`
- `\}`

These exist so that inline content can contain literal `\`, `{`, and `}` without always starting an inline node (`\name{...}`) or requiring brace balancing.

#### Decoding rule

During semantic text construction, an implementation **MAY** decode these tokens as:

- `\\` → `\`
- `\{` → `{`
- `\}` → `}`

This decoding is independent of STRING literal escapes: these tokens occur in inline text streams, not inside `"..."` literals.

#### Round-tripping note (normative intent)

A formatter or tooling that aims to preserve the author’s intent **SHOULD** preserve the distinction between:

- a literal `{`/`}` that is part of a balanced inline group, and
- an escaped brace token `\{`/`\}` that was used to avoid imbalance.

This distinction matters for reliable reconstruction and for edits that may reflow or restructure inline content.

### Interaction with syntax

- Escape decoding is performed **after** syntactic parsing.
- Syntactic parsing of STRING literals is delimiter-based and does not validate escape *meaning*.
- Semantic validation determines whether escapes are valid and produces the decoded Unicode text.

This separation is intentional: it allows autoformatters to parse and rewrite documents that may contain malformed escapes without losing information, while still allowing strict validators to enforce the escape rules above.

## Semantic Validity

> TO BE DONE.
>
> - Attribute uniqueness
> - Attribute must be defined on a node
> - Non-optional attributes must be present
> - id is only valid on top-level nodes
> - id must be unique
> - id is case sensitive
> - ref must point to an existing id

## Element Overview

| Element                                                     | Element Type | Allowed Children             | Attributes                                         |
| ----------------------------------------------------------- | ------------ | ---------------------------- | -------------------------------------------------- |
| *Document*                                                  | Document     | `hdoc`, Blocks               |                                                    |
| `hdoc`                                                      | Header       | -                            | `lang`, `title`, `version`, `author`, `date`, `tz` |
| `h1`, `h2`, `h3`                                            | Block        | Text Body                    | `lang`, \[`id`\]                                   |
| `p`, `note`, `warning`, `danger`, `tip`, `quote`, `spoiler` | Block        | Text Body                    | `lang`, \[`id`\]                                   |
| `ul`                                                        | Block        | `li` ≥ 1                     | `lang`, \[`id`\]                                   |
| `ol`                                                        | Block        | `li` ≥ 1                     | `lang`, \[`id`\], `first`                          |
| `img`                                                       | Block        | Text Body                    | `lang`, \[`id`\], `alt`, `path`                    |
| `pre`                                                       | Block        | Text Body                    | `lang`, \[`id`\], `syntax`                         |
| `toc`                                                       | Block        | -                            | `lang`, \[`id`\], `depth`                          |
| `table`                                                     | Block        | Table Rows                   | `lang`, \[`id`\]                                   |
| `li`                                                        | List Item    | Blocks, String, Verbatim     | `lang`                                             |
| `td`                                                        | Table Cell   | Blocks, String, Verbatim     | `lang`, `colspan`                                  |
| `columns`                                                   | Table Row    | `td` ≥ 1                     | `lang`                                             |
| `group`                                                     | Table Row    | Text Body                    | `lang`,                                            |
| `row`                                                       | Table Row    | `td` ≥ 1                     | `lang`, `title`                                    |
| `\em`                                                       | Text Body    | Text Body                    | `lang`                                             |
| `\mono`                                                     | Text Body    | Text Body                    | `lang`, `syntax`                                   |
| `\strike`                                                   | Text Body    | Text Body                    | `lang`                                             |
| `\sub`, `\sup`                                              | Text Body    | Text Body                    | `lang`                                             |
| `\link`                                                     | Text Body    | Text Body                    | `lang`, (`ref` \| `uri`)                           |
| `\date`, `\time`, `\datetime`                               | Text Body    | Plain Text, String, Verbatim | `lang`, `fmt`                                      |
| *Plain Text*                                                | Text Body    | -                            |                                                    |
| *String*                                                    | Text Body    | -                            |                                                    |
| *Verbatim*                                                  | Text Body    | -                            |                                                    |

Notes:

- The attribute `id` is only allowed when the element is a top-level element (direct child of the document)
- The attributes `ref` and `uri` on a `\link` are mutually exclusive
- `\date`, `\time` and `\datetime` cannot contain other text body items except for plain text, string or verbatim content.

## Attribute Overview

| Attribute | Required | Allowed Values                                                                               | Description                                                                     |
| --------- | -------- | -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `version` | Yes      | `2.0`                                                                                        | Describes the version of this HyperDoc document.                                |
| `lang`    | No       | [BCP 47 Language Tag](https://datatracker.ietf.org/doc/html/rfc5646)                         | Defines the language of the elements contents.                                  |
| `title`   | No       | *Any*                                                                                        | Sets the title of the document or the table row.                                |
| `author`  | No       | *Any*                                                                                        | Sets the author of the document.                                                |
| `date`    | No       | A date-time value using the format specified below                                           | Sets the authoring date of the document.                                        |
| `id`      | No       | Non-empty                                                                                    | Sets a reference which can be linked to with `\link(ref="...")`.                |
| `first`   | No       | Decimal integer numbers ≥ 0                                                                  | Sets the number of the first list item.                                         |
| `alt`     | No       | Non-empty                                                                                    | Sets the alternative text shown when an image cannot be loaded.                 |
| `path`    | Yes      | Non-empty file path to an image file                                                         | Defines the file path where the image file can be found.                        |
| `syntax`  | No       | *See element documentation*                                                                  | Hints the syntax highlighter how how the elements context shall be highlighted. |
| `depth`   | No       | `1`, `2` or `3`                                                                              | Defines how many levels of headings shall be included.                          |
| `colspan` | No       | Decimal integer numbers ≥ 1                                                                  | Sets how many columns the table cell spans.                                     |
| `ref`     | No       | Any value present in an `id` attribute.                                                      | References any `id` inside this document.                                       |
| `uri`     | No       | [Internationalized Resource Identifier (IRI)](https://datatracker.ietf.org/doc/html/rfc3987) | Links to a foreign document with a URI.                                         |
| `fmt`     | No       | *See element documentation*                                                                  | Defines how the date/time value shall be displayed.                             |
| `tz`      | No       | `Z` for UTC or a `±HH:MM` timezone offset.                                                   | Defines the default timezone for time/datetime values.                          |

## Semantic Structure

All elements have these attributes:

| Attribute | Function                                                                                                                                          |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lang`    | Marks the (human) language of the contents of that element. This must be an [IETF language tag](https://en.wikipedia.org/wiki/IETF_language_tag). |

## Top-Level / Block Elements

All top-level elements have these attributes:

| Attribute | Function                                                                         |
| --------- | -------------------------------------------------------------------------------- |
| `id`      | Marks a target for a `\link(ref="...")`. Must be unique throughout the document. |

### Headings: `h1`, `h2`, `h3`

**Allowed Items:** Inline Text

These elements are all rendered as headings of different levels.

- `h1` is the top-level heading.
- `h2` is the level below `h1`.
- `h3` is the level below `h2`.

### Paragraphs: `p`, `note`, `warning`, `danger`, `tip`, `quote`, `spoiler`

**Allowed Items:** Inline Text

These elements are all rendered as paragraphs.

The type of the paragraph includes a semantic hint:

- `p`: A normal paragraph.
- `note`: A paragraph that informs the reader. This is typically rendered with a blue/white color hint. The associated icon is a white i in a blue box/circle.
- `warning`: A paragraph that warns the reader. This is typically rendered with a yellow/black color hint. The associated icon is a yellow triangle with a black exclamation mark.
- `danger`: A paragraph that warns the of danger. This is typically rendered with a red/white color hint. The associated icon is a red octagon with a white exclamation mark.
- `tip`: A paragraph that gives the reader a tip. The associated icon is a lightbulb.
- `quote`: A paragraph that quotes a foreign source. This is typically rendered with a small indentation and a distinct font.
- `spoiler`: A paragraph that contains information the reader about things they might not want to know. This is typically visually hidden/blurred so it's unreadable until a reader action is performed.

### Lists: `ul`, `ol`

**Allowed Items:** `li`

- `ul` is an unordered list rendered with typically either dashes or dots as list enumerators.
- `ol` is an ordered list rendered with typically either roman or arabic numerals as list enumerators.

#### Ordered List `ol`

| Attribute | Function                                                                                                                    |
| --------- | --------------------------------------------------------------------------------------------------------------------------- |
| `first`   | An integer string that is the number of the *first* item of the list. Allows paragraph breaks between a single joined list. |

### Figures: `img`

**Allowed Items:** Inline Text

| Attribute | Function                                                                                                                                           |
| --------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `alt`     | A textual description of the image contents for vision-impaired users. Similar to the [HTML alt tag](https://en.wikipedia.org/wiki/Alt_attribute). |
| `path`    | A path relative to the current file that points to an image file that should be shown.                                                             |

This element shows a full-width image or figure. Its contents are the figure description.

If the contents are empty, the figure may be rendered in a simpler form.

### Preformatted: `pre`

**Allowed Items:** Inline Text

| Attribute | Function                                                                                                |
| --------- | ------------------------------------------------------------------------------------------------------- |
| `syntax`  | If present, hints a syntax highlighter that this preformatted block contains programming language code. |

In contrast to all other block types, a `pre` block retains whitespace and line-break information and lays out the text as-is.

It does not allow automatic line break insertion or word-wrapping.

If a pre contains inline elements, these will still be parsed and apply their styles to the text spans.

### Table Of Contents: `toc`

**Allowed Items:** *none*

| Attribute | Function                                                                       |
| --------- | ------------------------------------------------------------------------------ |
| `depth`   | String `1`, `2` or `3`. Defines how many levels of headings shall be included. |

Renders a table of contents for the current document.

This element allows no child items.

## Lists

### List Items `li`

**Allowed Items:** Block Elements *or* String Content.

These elements wrap a sequence of blocks that will be rendered for this list item.

It also allows a string to be used as it's content directly, this will be equivalent to having a nested paragraph with that strings content:

```
ul {
  li { p { This is a normal item. } }
  li "This is a normal item."
}
```

will have two identical list items.

### Tables: `table`

**Allowed Items:** `columns`, `row`, `group`

Tables are made up of an optional header row (`columns`) followed by a sequence of `row` and `group` elements.

- `columns` defines the header labels and the column count.
- `row` defines a data row.
- `group` provides a section heading that applies to subsequent rows until the next group or the end of the table.

All `row` and `columns` elements must resolve to the same number of columns after applying `colspan`.
If a `row` uses the `title` attribute or a `group` is present, renderers must reserve a leading title column.
In that case, the header row should have an empty leading cell before the column headers.

## Table Elements

### Column Headers: `columns`

**Allowed Items:** `td`

This element contains the header cells for each column.

### Rows: `row`

**Allowed Items:** `td`

| Attribute | Function                                                                     |
| --------- | ---------------------------------------------------------------------------- |
| `title`   | A title caption for this row. If present, will be shown left of all columns. |

### Row Groups: `group`

**Allowed Items:** Inline Text

A *row group* is a row that contains a single heading-style cell that labels the rows below.

### Cells: `td`

**Allowed Items:** Block Elements *or* String Content.

| Attribute | Function                                                  |
| --------- | --------------------------------------------------------- |
| `colspan` | Integer string defining how many columns this cell spans. |

This element contains the contents of a table cell.

Like `li`, a `td` can either contain a single string or a nested block sequence.

## Inline Text

These elements are all allowed inside a paragraph-like content and can typically be nested.

*Inline Text* can either be a string literal, a literal block or a list.

If the text is a list, it allows the use of inline elements like `\em` or `\mono`.

### Plain Text

This is normal plain text and has no special meaning.

### Emphasis: `em`

**Nesting:** Yes

Formats the text as emphasised. This is typically bold or italic rendering.

### Monospaced: `mono`

**Nesting:** Yes

| Attribute | Function                                                                                  |
| --------- | ----------------------------------------------------------------------------------------- |
| `syntax`  | If present, hints a syntax highlighter that this span contains programming language code. |

Formats the text in a monospaced font. This is useful for code-like structures.

### Strike-through: `strike`

**Nesting:** Yes

Renders the text with a horizontal line through the text, striking it out.

### Sub/Superscript: `sub`, `sup`

**Nesting:** Yes

Renders the text a bit smaller and moved upwards (`sup`) or downwards (`sub`) to allow sub- or superscript rendering.

### Linking: `link`

**Nesting:** Yes

| Attribute | Function                                                                                                 |
| --------- | -------------------------------------------------------------------------------------------------------- |
| `ref`     | Points the link to a top-level block with the `id` of this `ref` attribute. Mutually exclusive to `uri`. |
| `uri`     | Points the link to the resource inside the `uri`. Mutually exclusive to `ref`.                           |

Adds a hyperlink to the contents. This allows a reader to navigate by typically clicking the link.

### Localized Date/Time: `date`, `time`, `datetime`

**Nesting:** No

| Element    | Attribute | Function                                                                                                    |
| ---------- | --------- | ----------------------------------------------------------------------------------------------------------- |
| `date`     | `fmt`     | `year`, `month`, `day`, `weekday`, `short`, `long`, `relative`, `iso` (raw ISO 8601).                       |
| `time`     | `fmt`     | `short`, `long`, `rough`, `relative`, `iso` (raw ISO 8601).                                                 |
| `datetime` | `fmt`     | `short` (localized date+time), `long` (localized date+time with seconds), `relative`, `iso` (raw ISO 8601). |

Renders a [ISO 8601](https://en.wikipedia.org/wiki/ISO_8601#Combined_date_and_time_representations) date, time or date+time in a localized manner.

## Date/Time Formatting

All date/time values MUST use the formats defined in this section. This is a conservative, interoperable intersection between [RFC3339](https://datatracker.ietf.org/doc/html/rfc3339) and [ISO 8601](https://en.wikipedia.org/wiki/ISO_8601), so values that conform here are valid under both specifications. Digits are ASCII decimal unless stated otherwise.

### Date Format

Date strings MUST follow `YYYY-MM-DD`.

- `YYYY` is a year with one or more digits.
- `MM` is a two-digit month in the range `01` to `12`.
- `DD` is a two-digit day in the range `01` to `31`.
- The `-` separators are mandatory.

Examples: `2025-12-25`, `1-01-01`.

### Time Format

Time strings MUST follow `hh:mm:ss` with a required time zone.

- `hh`, `mm`, `ss` are two-digit hour, minute, second fields.
- Hour MUST be in `00` to `23`, minute and second MUST be in `00` to `59`.
- An optional fractional seconds component MAY follow the seconds field as `.` plus
  1, 2, 3, 6, or 9 digits.
- The fractional separator MUST be `.`. Comma is not allowed.
- A time zone is required when no `tz` attribute is present on the header node and
  MUST be either `Z` (UTC) or a numeric offset in the form `+hh:mm` or `-hh:mm` with two-digit hour/minute fields.
- Offset hours MUST be in `00` to `23`, offset minutes MUST be in `00` to `59`.

Examples: `22:30:46Z`, `22:30:46.136+01:00`, `21:30:46.136797358-05:30`, `22:30:46` (only with `tz` attribute).

### Date/Time Format

Date/time strings MUST combine a date and time with a literal `T`.

- Format: `YYYY-MM-DD` + `T` + `hh:mm:ss` (with optional fraction and required zone).

Examples: `2025-12-25T22:31:50.13+01:00`, `2025-12-25T21:31:43Z`.
