# HyperDoc 2.0

**Status:** Cleaned-up draft.

## 0. Chapter Status

Chapters that are marked FROZEN must not be changed by AI agents.

FROZEN:  No changes allowed.
DONE:    Semantics are correct, language might need improvement.
DRAFT:   Current semantics are not finalized yet.
MISSING: Chapter needs to be added still.

If a chapter is marked DONE or FROZEN, the status applies to all of its sub-chapters unless a sub-chapter is explicitly listed with a different status.

- "1. Introduction": DONE
- "2. Conformance and terminology": FROZEN
- "3. Document encoding (byte- and line-level)": DONE
- "4. Syntactic model": DONE
- "5. Grammar and additional syntax rules"
  - "5.1 Grammar (EBNF)": DRAFT
  - "5.2 Deterministic list-mode disambiguation": DONE
  - "5.3 Maximal munch": FROZEN
  - "5.4 Inline-list brace balancing and backslash dispatch": DONE
  - "5.5 String literals (syntax)": DRAFT
- "6. Inline Text Escape Processing (semantic)": DRAFT
  - "6.1 Inline escape-text tokens": DRAFT
- "7. String Literal Escape Processing (semantic)": DRAFT
  - "7.1 Control character policy (semantic)": DRAFT
  - "7.2 Supported escapes in string literals": DRAFT
    - "7.2.1 Unicode escape `\\u{H...}`": DRAFT
  - "7.3 Invalid escapes": DRAFT
- "8. Semantic document model": DRAFT
  - "8.1 Document structure": DONE
  - "8.2 Inline text construction and normalization": DONE
  - "8.3 Attribute uniqueness": DONE
  - "8.4 Attribute validity": DONE
  - "8.5 Identifiers and References": DONE
  - "8.6 Built-in element recognition": DONE
- "9. Elements and attributes"
  - "9.1 Built-in elements and list mode"
    - "9.1.1 Inline vs block": DONE
    - "9.1.2 List-body mode per built-in element": DRAFT
  - "9.2 Element catalog (normative)": DRAFT
    - "9.2.1 `hdoc` (header)": DONE
    - "9.2.2 Headings: `h1`, `h2`, `h3`": DRAFT
    - "9.2.3 Paragraph blocks: `p`, `note`, `warning`, `danger`, `tip`, `quote`, `spoiler`": DRAFT
    - "9.2.4 Lists: `ul`, `ol`": DRAFT
    - "9.2.5 List item: `li`": DRAFT
    - "9.2.6 Figure: `img`": DRAFT
    - "9.2.7 Preformatted: `pre`": DRAFT
    - "9.2.8 Table of contents: `toc`": DRAFT
    - "9.2.9 Tables: `table`": DRAFT
    - "9.2.10 `columns` (table header row)": DRAFT
    - "9.2.11 `row` (table data row)": DRAFT
    - "9.2.12 `group` (table row group)": DRAFT
    - "9.2.13 `td` (table cell)": DRAFT
    - "9.2.14 `title` (document title)": DRAFT
    - "9.2.15 Footnote dump: `footnotes`": DRAFT
  - "9.3 Inline elements"
    - "9.3.1 `\\em`": DRAFT
    - "9.3.2 `\\mono`": DRAFT
    - "9.3.3 `\\strike`, `\\sub`, `\\sup`": DRAFT
    - "9.3.4 `\link`": DRAFT
    - "9.3.5 `\\date`, `\\time`, `\\datetime`": DRAFT
    - "9.3.6 `\ref`": DRAFT
    - "9.3.7 `\footnote`": DRAFT
- "10. Attribute types and date/time formats": DRAFT
  - "10.1 Common attribute types": DRAFT
  - "10.2 Date / time lexical formats (normative)": DRAFT
    - "10.2.1 Date": DRAFT
    - "10.2.2 Time": DRAFT
    - "10.2.3 Datetime": DRAFT
  - "10.3 `fmt` values": DRAFT
- "11. Non-normative guidance for tooling": DRAFT
- "Appendix A. Example": DRAFT
- "Appendix B. Element Overview": MISSING
- "Appendix C. Attribute Overview": MISSING

---

## 1. Introduction

HyperDoc 2.0 ("HyperDoc") is a plain-text markup language for hypertext documents.

Design goals:

- Deterministic, unambiguous parsing.
- Convenient authoring in plain text.
- Round-trippable formatting (tooling can rewrite without losing information).

## 2. Conformance and terminology

The key words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** are to be interpreted as described in RFC 2119.

A document can be:

- **Syntactically valid**: conforms to the grammar and additional syntax rules.
- **Semantically valid**: syntactically valid **and** conforms to semantic rules (elements, attributes, escape decoding, IDs/refs, etc.).

Unless explicitly stated, rules in chapters 3-5 are **syntax** rules; rules in chapters 6-10 are **semantic** rules.

## 3. Document encoding (byte- and line-level)

### 3.1 Character encoding

- A HyperDoc document **MUST** be encoded as UTF-8.
- A HyperDoc document **MUST NOT** contain invalid UTF-8 byte sequences.

#### UTF-8 BOM

- A UTF-8 BOM (`EF BB BF`) **SHOULD NOT** be used.
- Tooling **MAY** accept a BOM and treat it as whitespace at the beginning of the document.

### 3.2 Line endings

- Lines **MUST** be terminated by either:
  - `<LF>` (U+000A), or
  - `<CR><LF>` (U+000D U+000A).
- A bare `<CR>` **MUST NOT** appear except as part of `<CR><LF>`.

A document **MAY** mix `<LF>` and `<CR><LF>` line endings, but tooling **SHOULD** normalize to a single convention when rewriting documents.

The canonical line ending emitted by tooling **SHOULD** be `<LF>`.

### 3.3 Control characters in source text

- A syntactically valid document **MAY** contain `<TAB>` (U+0009).
- Other Unicode control characters (General Category `Cc`) **MUST NOT** appear in source text, except:
  - U+000A (LF) and
  - U+000D (CR) as part of a valid line ending.
- Surrogate characters (Plane "unassigned", U+D800…U+DFFF) **MUST NOT** appear in the source text. A conforming parser **MUST** reject them.

A semantic validator **MAY** reject TABs in source text (see §7.1).

### 3.4 Unicode text

Apart from the restrictions above, arbitrary Unicode scalar values are allowed.

### 3.5 Recommendations for directionality (non-normative)

HyperDoc does not define special handling for right-to-left scripts or bidirectional layout.

Authors **SHOULD** keep each paragraph primarily in a single writing system/directionality where practical. Tooling **MAY** warn when paragraphs contain bidi override/formatting characters.

## 4. Syntactic model

A HyperDoc document is a sequence of **nodes**.

Each node has:

- a **name** (identifier),
- an optional **attribute list** `(key="value", ...)`,
- and a mandatory **body**.

### 4.1 Bodies

A body is one of:

- `;` - empty body
- `"..."` - string literal body
- `:` - verbatim body (zero or more `|` lines; empty verbatim bodies **MUST** emit a diagnostic)
- `{ ... }` - list body

### 4.2 List bodies and modes

A list body `{ ... }` is parsed in one of two modes:

- **Block-list mode**: contains nested nodes.
- **Inline-list mode**: contains an inline token stream of text items and inline nodes.

The grammar is intentionally ambiguous; a deterministic external rule selects a mode (see §5.2).

### 4.3 Attributes (syntax)

- Attribute lists are comma-separated `(key="value", ...)`.
- Trailing commas are allowed.
- Attribute values are **string literals** (see §5.5).
- Attribute keys are identifiers with hyphen-separated segments (see §5.1 and §10.1).

## 5. Grammar and additional syntax rules

### 5.1 Grammar (EBNF)

The grammar below is syntax-only.

```ebnf
document        ::= ws , { node , ws } , EOF ;

node            ::= node_name , ws , [ attribute_list , ws ] , body ;

body            ::= ";" | string_literal | verbatim_body | list_body ;

list_body       ::= "{" , list_content , "}" ;
list_content    ::= inline_content | block_content ;

attribute_list  ::= "(" , ws ,
                    [ attribute , { ws , "," , ws , attribute } , [ ws , "," ] ] ,
                    ws , ")" ;
attribute       ::= attr_key , ws , "=" , ws , string_literal ;

block_content   ::= ws , { node , ws } ;

inline_content  ::= ws , { inline_item , ws } ;
inline_item     ::= word | escape_text | inline_node | inline_group ;
inline_group    ::= "{" , inline_content , "}" ;

escape_text     ::= "\\" , ( "\\" | "{" | "}" ) ;
inline_node     ::= inline_name , ws , [ attribute_list , ws ] , body ;

(* Identifiers *)
node_name       ::= [ "\\" ] , ident_char , { ident_char } ;
inline_name     ::= "\\" , ident_char , { ident_char } ;
attr_key        ::= key_seg , { "-" , key_seg } ;

ident_char      ::= "A".."Z" | "a".."z" | "0".."9" | "_" ;
key_seg         ::= ident_char , { ident_char } ;

string_literal  ::= '"' , { string_unit } , '"' ;

(* Words *)
word            ::= word_char , { word_char } ;

(* word_char matches any Unicode scalar value except:
    - whitespace
    - '{' or '}'
    - '\\' (because '\\' begins escape_text or inline_node)
*)
word_char       ::= ? any scalar value except WS, "{", "}", "\\" ? ;

(* String literals (syntax only; no escape validation here) *)
string_unit     ::= string_char | "\\" , escaped_char ;
string_char     ::= ? any scalar value except '"', "\\", control characters (Unicode category Cc) ? ;
escaped_char    ::= ? any scalar value except control characters (Unicode category Cc) ? ;

(* Verbatim lines *)
verbatim_body   ::= ":" , { ws , piped_line } ;
(* An empty verbatim body (no piped_line) is syntactically valid, but tooling MUST emit a diagnostic. *)
piped_line      ::= "|" , { not_line_end } , line_terminator ;
not_line_end    ::= ? any scalar value except CR and LF ? ;
line_terminator ::= LF | ( CR , LF ) | EOF ;

(* Whitespace *)
ws              ::= { WS } ;
WS              ::= " " | "\t" | LF | ( CR , LF ) ;
CR              ::= "\r" ;
LF              ::= "\n" ;
```

### 5.2 Deterministic list-mode disambiguation

Before parsing the contents of any `{ ... }` list body, the parser **MUST** choose exactly one list mode.

The mode is determined solely from the **node name token**:

1. If the node name begins with `\`, the parser **MUST** choose **Inline-list mode**.
2. Else, if the node name is a recognized built-in with a specified list mode, the parser **MUST** choose that mode.
3. Otherwise (unknown node name), the parser **MUST** choose **Inline-list mode**.

Built-in elements and their list modes are defined in §9.1.

### 5.3 Maximal munch

When reading `node_name`, `inline_name`, and `attr_key`, parsers **MUST** consume the longest possible sequence of allowed identifier characters.

### 5.4 Inline-list brace balancing and backslash dispatch

In Inline-list mode:

- Literal braces are structural (`inline_group`) and therefore **must be balanced**.
- If braces cannot be balanced, they **must** be written as escape-text tokens `\{` and `\}`.
- A backslash in inline content is interpreted as:
  - one of the three escape-text tokens `\\`, `\{`, `\}`, or
  - the start of an inline node otherwise.

### 5.5 String literals (syntax)

String literals are delimited by `"` and are parsed without interpreting escape *meaning*.

Syntactic rules:

- The literal starts with `"` and ends at the next `"` that is not consumed as the escaped character after a backslash.
- A string literal **MUST NOT** contain any Unicode control characters (General Category `Cc`), including TAB, LF, and CR.
- A backslash (`\`) **MUST NOT** be the last character before the closing `"` (unterminated escape).
- The closing `"` **MUST** appear before end-of-file.

The following reference algorithm is authoritative:

```pseudo
assert next() == '"'
while(not eof()):
  char = next()
  if char == '\\':
    if eof(): abort() # backslash in last position
    esc = next() # escaped character (meaning is not interpreted here)
    if is_control(esc): abort() # includes CR, LF, TAB and all other control characters
  elif char == '"':
    return # end of string literal
  elif is_control(char): # includes CR, LF, TAB and all other control characters
    abort() # invalid character
abort() # eof before closing '"'
```

Semantic escape decoding and validation is specified in §7.

## 6. Inline Text Escape Processing (semantic)

Escape decoding in inline-list bodies applies only to the three escape-text tokens produced by the parser (§5.4).

### 6.1 Inline escape-text tokens

In inline-list bodies, the parser emits three special text tokens:

- `\\`
- `\{`
- `\}`

During semantic inline-text construction (§8.2), implementations **MUST** decode these to literal `\`, `{`, `}`.

Tooling that aims to preserve author intent **SHOULD** preserve whether braces were written as balanced groups vs escaped brace tokens, because these spellings are not semantically equivalent in the inline parse tree.

## 7. String Literal Escape Processing (semantic)

Escape sequences are recognized only in string literals (node bodies of the `"..."` form and attribute values). No other syntax performs string-literal escape decoding.

### 7.1 Control character policy (semantic)

- A semantic validator **MAY** reject TAB (U+0009) in source text.
- After decoding escapes in any string literal, the resolved value **MUST NOT** contain any Unicode control character (General Category `Cc`) except:
  - LF (U+000A), and
  - CR (U+000D) only when immediately followed by LF (U+000A) (i.e. as part of a CRLF sequence U+000D U+000A).
- TAB (U+0009) is always forbidden in resolved string-literal values, including when produced via `\u{...}`.

String literals are syntactically forbidden from containing literal control characters (§5.5); therefore LF/CRLF can only appear in resolved values via `\n`, `\r`, or `\u{...}`.

### 7.2 Supported escapes in string literals

A semantic validator/decoder **MUST** accept exactly:

| Escape     | Decodes to                  |
| ---------- | --------------------------- |
| `\\`       | U+005C (`\`)                |
| `\"`       | U+0022 (`"`)                |
| `\n`       | U+000A (LF)                 |
| `\r`       | U+000D (CR)                 |
| `\u{H...}` | Unicode scalar value U+H... |

#### 7.2.1 Unicode escape `\u{H...}`

- 1-6 hex digits
- value in `0x0..0x10FFFF`
- not in `0xD800..0xDFFF` (surrogates)
- must not decode to a forbidden control character (§7.1)

### 7.3 Invalid escapes

A semantic validator/decoder **MUST** reject a string literal that contains:

- any other escape (`\t`, `\\xHH`, `\0`, etc.)
- an unterminated escape (string ends after `\`)
- malformed `\u{...}` (missing braces, empty, non-hex, >6 digits)
- out-of-range or surrogate code points
- forbidden control characters produced by `\u{...}`

## 8. Semantic document model

### 8.1 Document structure

- A semantically valid document **MUST** contain exactly one `hdoc` header node.
- The `hdoc` node **MUST** be the first node in the document.
- The `hdoc` node **MUST NOT** appear anywhere else.
- The `hdoc` node **MUST** have an empty body (`;`).

#### Document title

- A document **MAY** contain one `title` node (document-level title).
- If present, `title` **MUST** be the second node in the document (i.e., the first node after `hdoc`).
- `title` **MUST** be a top-level block element (direct child of the document).
- `title` **MUST NOT** have an `id` attribute.

`hdoc(title="...")` and `title { ... }` interact as follows:

- If exactly one of `hdoc(title="...")` or `title { ... }` is present, implementations **SHOULD** treat the single value as both:
  - the document metadata title, and
  - the document display title.
  If the single value is `title { ... }`, tooling **SHOULD** derive a plaintext title (via inline-text construction) for use as metadata where needed.

- If both are present, tooling **SHOULD** compare their plaintext forms:
  - If they match, tooling **SHOULD** emit a diagnostic hint that `hdoc(title)` is redundant.

- If neither is present, tooling **MAY** emit a diagnostic hint that the document has no title.


### 8.2 Inline text construction and normalization

Many elements (e.g. `p`, headings, and inline elements) produce **inline text** for rendering. Inline text is constructed from one of:

- a string body (`"..."`),
- a verbatim body (`:`), or
- an inline-list body (`{ ... }` in Inline-list mode).

Semantic processing **MUST** construct inline text as a sequence of **spans**, where each span has:

- a Unicode string, and
- an attribute set (e.g. emphasis/monospace/link, language overrides, etc.).

Processing rules:

1. **Parse → tree:** Parsing preserves `ws` and yields an inline tree (text items, inline nodes, and inline groups).
2. **Tree → spans:** Convert the inline tree into a sequence of spans.
3. **Span merging:** Adjacent spans with identical attribute sets **MUST** be merged.
4. **Whitespace normalization (non-`pre` only):** For elements other than `pre`, the resulting text (across all spans) **MUST** be normalized so that:
   - any run of whitespace is collapsed to a single U+0020 SPACE, and
   - leading and trailing whitespace is removed.

The renderer **MUST** see the post-normalization result.

**String and verbatim bodies:** When a string body or verbatim body is converted into spans, it is treated as a single text source (no nested inline nodes) and then processed using the same rules above, including whitespace normalization for non-`pre` elements.

### 8.3 Attribute uniqueness

- Within a node, attribute keys **MUST** be unique (case-sensitive).

### 8.4 Attribute validity

- Attributes **MUST** be allowed on the element they appear on.
- Required attributes **MUST** be present.
- Attributes not defined for an element **MUST** be rejected.

### 8.5 Identifiers and References

HyperDoc defines two separate namespaces for identifiers to allow cross-referencing within a document: the **Block Namespace** and the **Footnote Namespace**.

Identifiers in both namespaces are case-sensitive and share the same syntax: they **MUST** be a non-empty sequence of one or more characters, and **MUST NOT** contain any whitespace or Unicode control characters (General Category `Cc`).

#### 8.5.1 Block Namespace (`id` and `\ref(ref)`)

The Block Namespace is used for referencing top-level block elements like headings, figures, or tables.

- **Definition**: An identifier is added to the Block Namespace using the `id` attribute.
  - The `id` attribute is only allowed on **top-level block elements** (direct children of the document, not nested inside another node).
  - `id` values **MUST** be unique across the document's Block Namespace.

- **Reference**: An identifier in the Block Namespace is referenced using the `\ref` inline element.
  - `\ref(ref="...")` **MUST** reference an `id` that exists in the Block Namespace.

#### 8.5.2 Footnote Namespace (`\footnote(key)` and `\footnote(ref)`)

The Footnote Namespace is used for defining and referencing reusable footnotes.

- **Definition**: An identifier is added to the Footnote Namespace using the `key` attribute on a `\footnote` element that has a body.
  - `\footnote(key="..."){...}` defines a footnote and associates it with an identifier.
  - `key` values **MUST** be unique across the document's Footnote Namespace.

- **Reference**: An identifier in the Footnote Namespace is referenced using a `\footnote` element that has no body.
  - `\footnote(ref="...");` **MUST** reference a `key` that has been defined in the Footnote Namespace.

### 8.6 Built-in element recognition

- Built-in element names are defined in §9.
- Unknown elements are syntactically valid (parseable), but semantically invalid.

## 9. Elements and attributes

### 9.1 Built-in elements and list mode

#### 9.1.1 Inline vs block

- Any element name starting with `\` is an **inline element**.
- Any element name not starting with `\` is a **block element**.

#### 9.1.2 List-body mode per built-in element

When a built-in element uses a `{ ... }` list body, it is parsed in the mode below:

- **Inline-list mode:** `title`, `h1`, `h2`, `h3`, `p`, `img`, `pre`, `group`, and all inline elements (`\em`, `\mono`, `\link`, `\ref`, `\footnote`, `\date`, `\time`, `\datetime`, ...).
- **Block-list mode:** `ul`, `ol`, `li`, `table`, `columns`, `row`, `td`, `note`, `warning`, `danger`, `tip`, `quote`, `spoiler`.

- Containers (`ul`, `ol`, `table`, `row`, `columns`) naturally contain nested nodes.
- Text blocks (`title`, `p`, headings, etc.) contain inline text streams.
- `li`, `td`, and admonition blocks contain either blocks or a single string/verbatim body; representing blocks implies block-list mode.
- Built-in elements with empty bodies are also parsed in Inline-list mode so accidental `{ ... }` usage stays balanced and formatters can recover consistently (e.g., `toc;`, `footnotes;`).

#### 9.1.3 Shorthand Body Promotion

If a block element's list body can contain general text block elements (such as `p`, `pre`, `ol`, `ul`, etc.), its body **MAY** instead be written as a shorthand string or verbatim literal.

When a shorthand body is used, it is semantically equivalent to a block-list body containing a single `p` (paragraph) node whose own body is the original string or verbatim content.

For example, `li "some text"` is semantically identical to:

```hdoc
li {
  p "some text"
}
```

This promotion is a feature for convenience and applies only to the following elements:
- `li`
- `td`
- `note`
- `warning`
- `danger`
- `tip`
- `quote`
- `spoiler`

### 9.2 Top-Level Block Elements

#### 9.2.1 `hdoc` (header)

- **Role:** document header
- **Body:** `;` (empty)
- **Attributes:**
  - `version` (required): must be `"2.0"`
  - `lang` (optional)
  - `title` (optional)
  - `author` (optional)
  - `date` (optional): datetime lexical format (§10.2.3)
  - `tz` (optional): default timezone for time/datetime values (§10.2)

#### 9.2.2 `title` (document title)

- **Role:** document-level display title
- **Body:** inline text
- **Attributes:** `lang` (optional)

Semantic constraints:

- `title` **MUST** be a top-level block element.
- `title` **MUST** appear at most once.
- If present, `title` **MUST** be the second node in the document (after `hdoc`).
- `title` **MUST NOT** have an `id` attribute.

#### 9.2.3 Table of contents: `toc`

- **Role:** Generates a table of contents.
- **Body:** `;` (empty)
- **Attributes:** `depth` (optional Integer in {1,2,3}; default 3), `lang` (optional), `id` (optional)

Semantic constraints:
- `toc` **MUST** be a top-level block element (a direct child of the document).

#### 9.2.4 Footnote dump: `footnotes`

- **Role:** collect and render accumulated footnotes
- **Body:** `;` (empty)
- **Attributes:**
  - `kind` (optional; one of `footnote`, `citation`)
  - `lang` (optional)

Semantics:

- `footnotes;` collects and renders all footnotes of all kinds accumulated since the previous `footnotes(...)` node (or since start of document if none appeared yet).
- `footnotes(kind="footnote");` collects and renders only `kind="footnote"` entries accumulated since the previous `footnotes(...)` node.
- `footnotes(kind="citation");` collects and renders only `kind="citation"` entries accumulated since the previous `footnotes(...)` node.
- Each invocation of `footnotes(...)` **MUST** advance the “collection cursor” for subsequent `footnotes(...)` nodes (i.e., each dump emits only the accumulated entries since the last dump, not the whole-document set).
- `footnotes` **MUST NOT** emit a heading; headings are authored via `h1`/`h2`/`h3`.
- Tooling **SHOULD** emit a warning if any `\footnote(...)` is present in the document but no `footnotes(...)` node appears.

### 9.3 General Text Block Elements

In this chapter, an "inline text" body is one of:

- a string body (`"..."`)
- a verbatim body (`:`)
- an inline-list body (`{ ... }` parsed in Inline-list mode)

Only an empty body (`;`) is not "inline text".

#### 9.3.1 Headings: `h1`, `h2`, `h3`

- **Role:** block heading levels 1-3
- **Body:** inline text
- **Attributes:** `lang` (optional), `id` (optional; top-level only)

#### 9.3.2 Paragraph: `p`

- **Role:** A standard paragraph of text.
- **Body:** inline text
- **Attributes:** `lang` (optional), `id` (optional; top-level only)

#### 9.3.3 Admonition Blocks: `note`, `warning`, `danger`, `tip`, `quote`, `spoiler`

- **Role:** A block that renders with a distinct style to draw the reader's attention.
- **Body:** A block-list containing zero or more General Text Block Elements. Per the Shorthand Body Promotion rule (§9.1.3), a string or verbatim body may be provided, which will be treated as a single contained paragraph.
- **Attributes:** `lang` (optional), `id` (optional; top-level only)

#### 9.3.4 Unordered List: `ul`

- **Body:** block-list containing `li` (at least one)
- **Attributes:** `lang` (optional), `id` (optional; top-level only)

#### 9.3.5 Ordered List: `ol`

- **Body:** block-list containing `li` (at least one)
- **Attributes:**
  - `lang` (optional)
  - `id` (optional; top-level only)
  - `first` (optional Integer ≥ 0; default 1): number of the first list item

#### 9.3.6 Figure: `img`

- **Body:** inline text caption/description (may be empty)
- **Attributes:**
  - `path` (required, non-empty; relative to the current file location)
  - `alt` (optional, non-empty)
  - `lang` (optional)
  - `id` (optional; top-level only)

#### 9.3.7 Preformatted: `pre`

- **Body:** inline text
- **Attributes:** `syntax` (optional), `lang` (optional), `id` (optional; top-level only)

#### 9.3.8 Tables: `table`

- **Body:** block-list containing:
  - optional `columns`, then
  - zero or more `row` and `group` nodes
- **Attributes:** `lang` (optional), `id` (optional; top-level only)

Table layout rules:

- **Column Count:** The number of columns in a table is determined by the `columns` element. It is the sum of the `colspan` values of the `td` cells within the `columns` row. If `columns` is absent, the column count is determined by the first `row` element in the same way. All `columns` and `row` elements in a table **MUST** resolve to the same effective column count.

- **Row Headers (`row(title)`):** A `row` element may have a `title` attribute, which creates a *row header*. This header is rendered as an implicit, additional first column for that row. This "row header column" does **not** contribute to the table's main column count. If any `row` in the table has a `title`, renderers **MUST** reserve space for a leading row header column throughout the table. This leading column will be blank for `columns`, `group`, and any `row` without a `title`.

- **Group Headers (`group`):** A `group` element acts as a heading that spans all columns of the table. Semantically, `group { ... }` is equivalent to a `row` containing a single `td` with a `colspan` attribute equal to the table's column count. A `group` does not have a `title` and does not render a cell in the row header column.

### 9.4 Structural Elements

#### 9.4.1 List item: `li`

- **Body:** either
  - a block-list of block elements, or
  - a single string body, or
  - a verbatim body
- **Attributes:** `lang` (optional)

#### 9.4.2 `columns` (table header row)

- **Role:** Defines the labels for the columns of a table. The number of cells in this element (taking `colspan` into account) defines the table's column count.
- **Body:** block-list containing `td` (at least one)
- **Attributes:** `lang` (optional)

#### 9.4.3 `row` (table data row)

- **Role:** Defines a row of data in a table.
- **Body:** block-list containing `td` (at least one)
- **Attributes:**
  - `title` (optional string): If present, creates a header cell for the row in an implicit leading column.
  - `lang` (optional)

#### 9.4.4 `group` (table row group)

- **Role:** A heading row that spans all table columns.
- **Body:** inline text
- **Attributes:** `lang` (optional)

#### 9.4.5 `td` (table cell)

- **Role:** A single cell within a table row.
- **Body:** either
  - a block-list of block elements, or
  - a single string body, or
  - a verbatim body
- **Attributes:** `colspan` (optional Integer ≥ 1; default 1), `lang` (optional)

### 9.5 Inline elements

Inline elements appear only in inline-list bodies (or inside string/verbatim, depending on renderer).

#### 9.5.1 `\\em`

- **Role:** emphasis
- **Body:** inline text
- **Attributes:** `lang` (optional)

#### 9.5.2 `\\mono`

- **Role:** monospaced span
- **Body:** inline text
- **Attributes:** `syntax` (optional), `lang` (optional)

#### 9.5.3 `\\strike`, `\\sub`, `\\sup`

- **Role:** strike-through / subscript / superscript
- **Body:** inline text
- **Attributes:** `lang` (optional)

#### 9.5.4 `\link`

- **Role:** foreign hyperlink (external or non-validated target)
- **Body:** inline text
- **Attributes:**
  - `uri` (**required**)
  - `lang` (optional)

Notes:

- `\link` is used for hyperlinks that are not validated as interior document references.
- Interior references use `\ref(ref="...")`.


#### 9.5.5 `\\date`, `\\time`, `\\datetime`

- **Role:** localized date/time rendering
- **Body:** must be plain text, a single string, or verbatim (no nested inline elements)
- **Attributes:** `fmt` (optional; per element), `lang` (optional)

#### 9.5.6 `\ref`

- **Role:** validated interior reference (to a top-level `id`)
- **Body:** inline text (optional; may be empty)
- **Attributes:**
  - `ref` (**required**; must reference an existing `id`)
  - `fmt` (optional; one of `full`, `name`, `index`; default `full`)
  - `lang` (optional)

Semantics:

- `\ref(ref="X")` **MUST** resolve to a top-level element with `id="X"`, otherwise it is semantically invalid.
- If `\ref` has a non-empty body, the body **MUST** be used as the rendered link text.
- If `\ref` has an empty body (`;`), the renderer **MUST** synthesize link text from the referenced target and `fmt`:

  - `fmt="full"`: renders `"<index> <name>"` (default)
  - `fmt="name"`: renders `"<name>"`
  - `fmt="index"`: renders `"<index>"`

Target-derived values:

- For heading targets (`h1`, `h2`, `h3`), `<name>` is the heading’s constructed plaintext inline text.
- For heading targets, `<index>` is the heading’s hierarchical number within the document (e.g. `3.` / `3.2.` / `3.2.1.`).

If the referenced target is not a heading:

> TODO: Also add semantics for `ref(ref);` with `img` (Figure X.) and `table` (Table X.).
>       This requires the introduction of counters for these tags, and allow auto-numbering.

- `\ref(ref="X");` (implicit body) is semantically invalid and **MUST** be rejected.
- `\ref(ref="X"){...}` remains valid.

When computing `<name>` for headings, inline footnote/citation markers **SHOULD NOT** contribute to the plaintext (i.e., their marker text is ignored).

#### 9.5.7 `\footnote`

- **Role:** footnote/citation marker and definition
- **Body:** inline text (required for defining form; empty for reference form)
- **Attributes:**
  - `key` (optional; defines a named footnote)
  - `ref` (optional; references a previously defined named footnote)
  - `kind` (optional; one of `footnote`, `citation`; default `footnote`)
  - `lang` (optional)

Attribute rules:

- `key` and `ref` are mutually exclusive.
- `kind` is only valid on the defining form (a `\footnote` with a non-empty body). A `\footnote(ref="...");` **MUST NOT** specify `kind`.

Semantics:

- `\footnote{...}` defines an anonymous footnote entry at the marker position.
- `\footnote(key="X"){...}` defines a named footnote entry in the footnote namespace and emits its marker at the marker position.
- `\footnote(ref="X");` emits a marker for the previously defined named footnote `X`.
- Each `kind` has an independent numeric namespace: footnotes and citations are numbered separately.
- A renderer **MAY** hyperlink markers and dumped entries back-and-forth.


## 10. Attribute types and date/time formats

> TODO: Attributes should be documented well and not only be mentioned in the element catalog.
>       This chapter shall document attributes and their types, including detailled descriptions for both.

> TODO: Specify that leading and trailing whitespay is allowed but discouraged.
>       Non-fatal diagnostics **MUST** be emitted for that.
>       Leading and trailing whitespace must be stripped.

### 10.1 Common attribute types

- **Version:** must be `2.0`.
- **Integer:** ASCII decimal digits; leading zeros allowed but discouraged.
- **Reference:** non-empty; must not contain whitespace or control characters.
- **Language tag:** BCP 47 (RFC 5646).
- **Timezone offset:** `Z` or `±HH:MM`.
- **URI/IRI:** per RFC 3987.

### 10.2 Date / time lexical formats (normative)

These formats are a conservative intersection of RFC 3339 and ISO 8601.

#### 10.2.1 Date

`YYYY-MM-DD`

- `YYYY`: one or more digits
- `MM`: `01`-`12`
- `DD`: `01`-`31`

#### 10.2.2 Time

`hh:mm:ss` with an optional fraction and an optional zone.

- `hh`: `00`-`23`
- `mm`: `00`-`59`
- `ss`: `00`-`59`
- optional fraction: `.` followed by 1,2,3,6, or 9 digits
- zone:
  - `Z`, or
  - `+hh:mm` / `-hh:mm` (two-digit hour/minute)

Normative rules:

- If `hdoc(tz="...")` is present, a time value **MAY** omit the zone; if omitted, the effective zone **MUST** be `hdoc.tz`.
- If `hdoc(tz="...")` is not present, a time value **MUST** specify a zone.
- If a time value specifies a zone, that zone **MUST** be used regardless of `hdoc.tz`.

#### 10.2.3 Datetime

`YYYY-MM-DD` `T` `hh:mm:ss` with an optional fraction and an optional zone.

The time component (including fraction and zone syntax) uses the same rules as §10.2.2.

Normative rules:

- If `hdoc(tz="...")` is present, a datetime value **MAY** omit the zone; if omitted, the effective zone **MUST** be `hdoc.tz`.
- If `hdoc(tz="...")` is not present, a datetime value **MUST** specify a zone.
- If a datetime value specifies a zone, that zone **MUST** be used regardless of `hdoc.tz`.

### 10.3 `fmt` values

Some inline elements accept a `fmt` attribute that controls localized formatting of their value.

The `fmt` value **MUST** be one of the values explicitly listed for the element; any other value **MUST** be rejected as semantically invalid.

#### 10.3.1 Language context

Formatting uses the element’s **language context**.

The base language context is the element’s **effective language tag** (§10.4.1). This means `lang` is inherited from parent elements, and top-level elements inherit their language tag from `hdoc(lang="...")`.

Tooling **MAY** allow users to override the language context and/or localized formatting preferences (e.g. force 24-hour time, force a preferred date ordering). If such an override is active, it **SHALL** replace the base language context for the purpose of all formatting in this section.

If there is no language context after applying user overrides, or if the implementation has no matching localized formatting data for the selected language context, then implementations **MUST** fall back to locale-independent formatting as follows:

- For `\date`:
  - `fmt="iso"` and `fmt="year"` proceed normally.
  - `fmt="day"` **MUST** render the day-of-month as decimal digits (`DD`), without an ordinal suffix.
  - `fmt="month"` **MUST** render the month as decimal digits (`MM`).
  - `fmt="weekday"` **MUST** render the ISO weekday number (`1`=Monday … `7`=Sunday).
  - `fmt="short"`, `fmt="long"`, and `fmt="relative"` **MUST** behave as if `fmt="iso"` was specified.
- For `\time` and `\datetime`:
  - if `fmt="iso"`, formatting proceeds normally, and
  - otherwise, the implementation **MUST** behave as if `fmt="iso"` was specified.

The examples below use `en-US` and `de-DE` language tags, but the exact output of localized formats (punctuation, capitalization, abbreviations, and choice of words) is implementation-defined.

#### 10.3.2 Time zone context

For `\time` and `\datetime`, formatting uses the value’s **effective zone**:

- If the value explicitly specifies a zone, that zone **MUST** be the effective zone.
- Otherwise, the effective zone **MUST** be `hdoc.tz` (see §10.2.2 and §10.2.3).

#### 10.3.3 `fmt` values for `\date`

The body of `\date` **MUST** be a date in the lexical format of §10.2.1.

Supported values:

| Value             | Meaning (normative)                                                                      | Example output (`en-US`) | Example output (`de-DE`) |
| ----------------- | ---------------------------------------------------------------------------------------- | ------------------------ | ------------------------ |
| `iso`             | Render the date in the lexical format of §10.2.1.                                        | `2026-09-13`             | `2026-09-13`             |
| `short` (default) | Render the date in a numeric, locale-appropriate short form.                             | `9/13/2026`              | `13.09.2026`             |
| `long`            | Render the date in a locale-appropriate long form (month name, full year).               | `September 13, 2026`     | `13. September 2026`     |
| `relative`        | Render a relative description of the date compared to “today”.                           | `in 3 days`              | `in 3 Tagen`             |
| `year`            | Render only the year component.                                                          | `2026`                   | `2026`                   |
| `month`           | Render only the month component in a locale-appropriate form (typically a month name).   | `September`              | `September`              |
| `day`             | Render only the day-of-month component in a locale-appropriate form (may be an ordinal). | `13th`                   | `13.`                    |
| `weekday`         | Render the weekday name for that date.                                                   | `Saturday`               | `Samstag`                |

The `relative` examples are non-normative and assume “today” is `2026-09-10` in the renderer’s date context.

#### 10.3.4 `fmt` values for `\time`

The body of `\time` **MUST** be a time in the lexical format of §10.2.2.

Supported values:

| Value             | Meaning (normative)                                                             | Example output (`en-US`) | Example output (`de-DE`) |
| ----------------- | ------------------------------------------------------------------------------- | ------------------------ | ------------------------ |
| `iso`             | Render the time in the lexical format of §10.2.2, including the effective zone. | `13:36:00+02:00`         | `13:36:00+02:00`         |
| `short` (default) | Render the time with minute precision in a locale-appropriate form.             | `1:36 PM`                | `13:36`                  |
| `long`            | Render the time with second precision; include the fractional part if present.  | `1:36:00 PM`             | `13:36:00`               |
| `rough`           | Render a coarse day-period description (e.g. morning/afternoon/evening).        | `afternoon`              | `Nachmittag`             |

#### 10.3.5 `fmt` values for `\datetime`

The body of `\datetime` **MUST** be a datetime in the lexical format of §10.2.3. The time component uses the same formatting rules as §10.3.4.

Supported values:

| Value             | Meaning (normative)                                                                 | Example output (`en-US`)         | Example output (`de-DE`)       |
| ----------------- | ----------------------------------------------------------------------------------- | -------------------------------- | ------------------------------ |
| `iso`             | Render the datetime in the lexical format of §10.2.3, including the effective zone. | `2026-09-13T13:36:00+02:00`      | `2026-09-13T13:36:00+02:00`    |
| `short` (default) | Render date and time with minute precision in a locale-appropriate short form.      | `9/13/2026, 1:36 PM`             | `13.09.2026, 13:36`            |
| `long`            | Render date and time with second precision; include the fractional part if present. | `September 13, 2026, 1:36:00 PM` | `13. September 2026, 13:36:00` |
| `relative`        | Render a relative description compared to the current datetime.                     | `20 minutes ago`                 | `vor 20 Minuten`               |

The `relative` examples are non-normative and assume the effective zone is `+02:00`, the value is `2026-09-13T13:36:00+02:00`, and “now” is `2026-09-13T13:56:00+02:00`.

#### 10.3.6 `fmt` values for `\ref`

The `fmt` attribute on `\ref` controls how synthesized link text is produced when the `\ref` body is empty (§9.5.6). It does not affect `\ref` nodes with a non-empty body.

| Value            | Meaning (normative)        | Example                       |
| ---------------- | -------------------------- | ----------------------------- |
| `full` (default) | Render `"<index> <name>"`. | `§10.3.6 fmt values for \ref` |
| `name`           | Render `"<name>"`.         | `fmt values for \ref`         |
| `index`          | Render `"<index>"`.        | `§10.3.6`                     |

### 10.4 `lang` attribute

The `lang` attribute assigns a BCP 47 language tag (§10.1) to an element.

#### 10.4.1 Effective language tag

Each element has an **effective language tag**, computed as follows:

1. If the element has a `lang` attribute, its value **SHALL** be the effective language tag.
2. Otherwise, if the element has a parent element, the effective language tag **SHALL** be inherited from the parent element.
3. Otherwise (for top-level elements), if the document header has `hdoc(lang="...")`, that language tag **SHALL** be the effective language tag.
4. Otherwise, the element has no effective language tag.

This inheritance allows documents to mix language contexts across nested elements (e.g. an English document that contains a German `quote` with an Italian paragraph inside), and keeps localized date/time values in their local context.

## 11. Non-normative guidance for tooling

- Formatters should normalize line endings to LF.
- Provide diagnostics for discouraged patterns (leading/trailing whitespace in attribute values, leading zeros, mixed directionality, etc.).
- For typo recovery, treat unknown nodes as inline-list mode (§5.2).
- Emit a warning when `\footnote(...)` occurs in a document but no `footnotes(...)` node appears.
- Emit a diagnostic hint when neither `hdoc(title="...")` nor `title { ... }` is present.
- Emit a diagnostic when both `hdoc(title="...")` and `title { ... }` are present but their plaintext forms differ.

---

## Appendix A. Example

```hdoc
hdoc(version="2.0", title="Example", lang="en");

h1 "Introduction"

p { This is my first HyperDoc 2.0 document! }

pre(syntax="c"):
| #include <stdio.h>
| int main(int argc, char *argv[]) {
|   printf("Hello, World!");
|   return 0;
| }
```
