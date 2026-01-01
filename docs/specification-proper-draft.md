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
- "6. Escape processing (semantic)": DRAFT
  - "6.1 Scope": DRAFT
  - "6.2 Control character policy (semantic)": DRAFT
  - "6.3 Supported escapes in string literals": DRAFT
    - "6.3.1 Unicode escape `\\u{H...}`": DRAFT
  - "6.4 Invalid escapes": DRAFT
  - "6.5 Inline escape-text tokens": DRAFT
- "7. Semantic document model": DRAFT
  - "7.1 Document structure": DONE
  - "7.2 Inline text construction and normalization": DONE
  - "7.3 Attribute uniqueness": DONE
  - "7.4 Attribute validity": DONE
  - "7.5 Identifiers and References": DONE
  - "7.6 Built-in element recognition": DONE
- "8. Elements and attributes"
  - "8.1 Built-in elements and list mode"
    - "8.1.1 Inline vs block": DONE
    - "8.1.2 List-body mode per built-in element": DRAFT
  - "8.2 Element catalog (normative)": DRAFT
    - "8.2.1 `hdoc` (header)": DONE
    - "8.2.2 Headings: `h1`, `h2`, `h3`": DRAFT
    - "8.2.3 Paragraph blocks: `p`, `note`, `warning`, `danger`, `tip`, `quote`, `spoiler`": DRAFT
    - "8.2.4 Lists: `ul`, `ol`": DRAFT
    - "8.2.5 List item: `li`": DRAFT
    - "8.2.6 Figure: `img`": DRAFT
    - "8.2.7 Preformatted: `pre`": DRAFT
    - "8.2.8 Table of contents: `toc`": DRAFT
    - "8.2.9 Tables: `table`": DRAFT
    - "8.2.10 `columns` (table header row)": DRAFT
    - "8.2.11 `row` (table data row)": DRAFT
    - "8.2.12 `group` (table row group)": DRAFT
    - "8.2.13 `td` (table cell)": DRAFT
    - "8.2.14 `title` (document title)": DRAFT
    - "8.2.15 Footnote dump: `footnotes`": DRAFT
  - "8.3 Inline elements"
    - "8.3.1 `\\em`": DRAFT
    - "8.3.2 `\\mono`": DRAFT
    - "8.3.3 `\\strike`, `\\sub`, `\\sup`": DRAFT
    - "8.3.4 `\link`": DRAFT
    - "8.3.5 `\\date`, `\\time`, `\\datetime`": DRAFT
    - "8.3.6 `\ref`": DRAFT
    - "8.3.7 `\footnote`": DRAFT
- "9. Attribute types and date/time formats": DRAFT
  - "9.1 Common attribute types": DRAFT
  - "9.2 Date / time lexical formats (normative)": DRAFT
    - "9.2.1 Date": DRAFT
    - "9.2.2 Time": DRAFT
    - "9.2.3 Datetime": DRAFT
  - "9.3 `fmt` values": DRAFT
- "10. Non-normative guidance for tooling": DRAFT
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

Unless explicitly stated, rules in chapters 3-5 are **syntax** rules; rules in chapters 6-9 are **semantic** rules.

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

A semantic validator **MAY** reject TABs in source text (see §6.2).

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
- Attribute keys are identifiers with hyphen-separated segments (see §5.1 and §9.1).

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

Built-in elements and their list modes are defined in §8.1.

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

Semantic escape decoding and validation is specified in §6.

## 6. Escape processing (semantic)

> TODO: This chapter must be split into two chapters:
>
> - "Inline Text Escape Processing"
> - "String Literal Escape Processing"
>
> This includes renumbering all chapters and their references for the markdown spec.
>
> Chapter "6.1 Scope" will be removed then.

### 6.1 Scope

Escape sequences are recognized only in:

1. String literals (node bodies of the `"..."` form and attribute values).
2. Inline escape-text tokens emitted by the parser: `\\\\`, `\\{`, `\\}`.

No other syntax performs escape decoding.

### 6.2 Control character policy (semantic)

> TODO: The same rules as in §3 are applied, except that `TAB` is also additionally forbidden after escaping.

- A semantic validator **MAY** reject TAB (U+0009) in source text.
- Regardless of whether TAB is accepted in source text, TAB **MUST** be rejected in the **resolved value of any string literal** (quoted node bodies and attribute values). This includes TAB that appears literally between quotes and TAB produced via `\u{...}`.

Apart from LF/CR line terminators and TAB (U+0009) in source text, a semantically valid document **MUST NOT** contain other Unicode control characters (General Category `Cc`). Resolved string-literal values are restricted by the rules above (TAB is always forbidden there).

### 6.3 Supported escapes in string literals

A semantic validator/decoder **MUST** accept exactly:

| Escape      | Decodes to                  |
| ----------- | --------------------------- |
| `\\\\`      | U+005C (`\\`)               |
| `\\"`       | U+0022 (`"`)                |
| `\\n`       | U+000A (LF)                 |
| `\\r`       | U+000D (CR)                 |
| `\\u{H...}` | Unicode scalar value U+H... |

#### 6.3.1 Unicode escape `\\u{H...}`

- 1-6 hex digits
- value in `0x0..0x10FFFF`
- not in `0xD800..0xDFFF` (surrogates)
- must not decode to a forbidden control character (§6.2)

### 6.4 Invalid escapes

A semantic validator/decoder **MUST** reject a string literal that contains:

- any other escape (`\t`, `\\xHH`, `\0`, etc.)
- an unterminated escape (string ends after `\`)
- malformed `\u{...}` (missing braces, empty, non-hex, >6 digits)
- out-of-range or surrogate code points
- forbidden control characters produced by `\u{...}`

### 6.5 Inline escape-text tokens

> TODO: Move to chapter "Inline Text Escape Processing"

In inline-list bodies, the parser emits three special text tokens:

- `\\`
- `\{`
- `\}`

During semantic text construction, implementations **MUST** decode these to literal `\`, `{`, `}`.

> TODO: The following sentence is unclear. The intent is: "When parsing, tooling should not perform ad-hoc conversion of escape sequences, so the output can be rendered again as-is. The escape sequences must always be display their escaped variant."

Tooling that aims to preserve author intent **SHOULD** preserve whether braces were written as balanced groups vs escaped brace tokens.

## 7. Semantic document model

### 7.1 Document structure

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


### 7.2 Inline text construction and normalization

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

### 7.3 Attribute uniqueness

- Within a node, attribute keys **MUST** be unique (case-sensitive).

### 7.4 Attribute validity

- Attributes **MUST** be allowed on the element they appear on.
- Required attributes **MUST** be present.
- Attributes not defined for an element **MUST** be rejected.

### 7.5 Identifiers and References

HyperDoc defines two separate namespaces for identifiers to allow cross-referencing within a document: the **Block Namespace** and the **Footnote Namespace**.

Identifiers in both namespaces are case-sensitive and share the same syntax: they **MUST** be a non-empty sequence of one or more characters, and **MUST NOT** contain any whitespace or Unicode control characters (General Category `Cc`).

#### 7.5.1 Block Namespace (`id` and `\ref(ref)`)

The Block Namespace is used for referencing top-level block elements like headings, figures, or tables.

- **Definition**: An identifier is added to the Block Namespace using the `id` attribute.
  - The `id` attribute is only allowed on **top-level block elements** (direct children of the document, not nested inside another node).
  - `id` values **MUST** be unique across the document's Block Namespace.

- **Reference**: An identifier in the Block Namespace is referenced using the `\ref` inline element.
  - `\ref(ref="...")` **MUST** reference an `id` that exists in the Block Namespace.

#### 7.5.2 Footnote Namespace (`\footnote(key)` and `\footnote(ref)`)

The Footnote Namespace is used for defining and referencing reusable footnotes.

- **Definition**: An identifier is added to the Footnote Namespace using the `key` attribute on a `\footnote` element that has a body.
  - `\footnote(key="..."){...}` defines a footnote and associates it with an identifier.
  - `key` values **MUST** be unique across the document's Footnote Namespace.

- **Reference**: An identifier in the Footnote Namespace is referenced using a `\footnote` element that has no body.
  - `\footnote(ref="...");` **MUST** reference a `key` that has been defined in the Footnote Namespace.

### 7.6 Built-in element recognition

- Built-in element names are defined in §8.
- Unknown elements are syntactically valid (parseable), but semantically invalid.

## 8. Elements and attributes

### 8.1 Built-in elements and list mode

#### 8.1.1 Inline vs block

- Any element name starting with `\` is an **inline element**.
- Any element name not starting with `\` is a **block element**.

#### 8.1.2 List-body mode per built-in element

When a built-in element uses a `{ ... }` list body, it is parsed in the mode below:

- **Inline-list mode:** `title`, `h1`, `h2`, `h3`, `p`, `img`, `pre`, `group`, and all inline elements (`\em`, `\mono`, `\link`, `\ref`, `\footnote`, `\date`, `\time`, `\datetime`, ...).
- **Block-list mode:** `ul`, `ol`, `li`, `table`, `columns`, `row`, `td`, `note`, `warning`, `danger`, `tip`, `quote`, `spoiler`.

- Containers (`ul`, `ol`, `table`, `row`, `columns`) naturally contain nested nodes.
- Text blocks (`title`, `p`, headings, etc.) contain inline text streams.
- `li`, `td`, and admonition blocks contain either blocks or a single string/verbatim body; representing blocks implies block-list mode.
- Built-in elements with empty bodies are also parsed in Inline-list mode so accidental `{ ... }` usage stays balanced and formatters can recover consistently (e.g., `toc;`, `footnotes;`).

#### 8.1.3 Shorthand Body Promotion

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

### 8.2 Top-Level Block Elements

#### 8.2.1 `hdoc` (header)

- **Role:** document header
- **Body:** `;` (empty)
- **Attributes:**
  - `version` (required): must be `"2.0"`
  - `lang` (optional)
  - `title` (optional)
  - `author` (optional)
  - `date` (optional): datetime lexical format (§9.2.3)
  - `tz` (optional): default timezone for time/datetime values (§9.2)

#### 8.2.2 `title` (document title)

- **Role:** document-level display title
- **Body:** inline text
- **Attributes:** `lang` (optional)

Semantic constraints:

- `title` **MUST** be a top-level block element.
- `title` **MUST** appear at most once.
- If present, `title` **MUST** be the second node in the document (after `hdoc`).
- `title` **MUST NOT** have an `id` attribute.

#### 8.2.3 Table of contents: `toc`

- **Role:** Generates a table of contents.
- **Body:** `;` (empty)
- **Attributes:** `depth` (optional Integer in {1,2,3}; default 3), `lang` (optional), `id` (optional)

Semantic constraints:
- `toc` **MUST** be a top-level block element (a direct child of the document).

#### 8.2.4 Footnote dump: `footnotes`

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

### 8.3 General Text Block Elements

In this chapter, an "inline text" body is one of:

- a string body (`"..."`)
- a verbatim body (`:`)
- an inline-list body (`{ ... }` parsed in Inline-list mode)

Only an empty body (`;`) is not "inline text".

#### 8.3.1 Headings: `h1`, `h2`, `h3`

- **Role:** block heading levels 1-3
- **Body:** inline text
- **Attributes:** `lang` (optional), `id` (optional; top-level only)

#### 8.3.2 Paragraph: `p`

- **Role:** A standard paragraph of text.
- **Body:** inline text
- **Attributes:** `lang` (optional), `id` (optional; top-level only)

#### 8.3.3 Admonition Blocks: `note`, `warning`, `danger`, `tip`, `quote`, `spoiler`

- **Role:** A block that renders with a distinct style to draw the reader's attention.
- **Body:** A block-list containing zero or more General Text Block Elements. Per the Shorthand Body Promotion rule (§ 8.1.3), a string or verbatim body may be provided, which will be treated as a single contained paragraph.
- **Attributes:** `lang` (optional), `id` (optional; top-level only)

#### 8.3.4 Unordered List: `ul`

- **Body:** block-list containing `li` (at least one)
- **Attributes:** `lang` (optional), `id` (optional; top-level only)

#### 8.3.5 Ordered List: `ol`

- **Body:** block-list containing `li` (at least one)
- **Attributes:**
  - `lang` (optional)
  - `id` (optional; top-level only)
  - `first` (optional Integer ≥ 0; default 1): number of the first list item

#### 8.3.6 Figure: `img`

- **Body:** inline text caption/description (may be empty)
- **Attributes:**
  - `path` (required, non-empty; relative to the current file location)
  - `alt` (optional, non-empty)
  - `lang` (optional)
  - `id` (optional; top-level only)

#### 8.3.7 Preformatted: `pre`

- **Body:** inline text
- **Attributes:** `syntax` (optional), `lang` (optional), `id` (optional; top-level only)

#### 8.3.8 Tables: `table`

- **Body:** block-list containing:
  - optional `columns`, then
  - zero or more `row` and `group` nodes
- **Attributes:** `lang` (optional), `id` (optional; top-level only)

Table layout rules:

- **Column Count:** The number of columns in a table is determined by the `columns` element. It is the sum of the `colspan` values of the `td` cells within the `columns` row. If `columns` is absent, the column count is determined by the first `row` element in the same way. All `columns` and `row` elements in a table **MUST** resolve to the same effective column count.

- **Row Headers (`row(title)`):** A `row` element may have a `title` attribute, which creates a *row header*. This header is rendered as an implicit, additional first column for that row. This "row header column" does **not** contribute to the table's main column count. If any `row` in the table has a `title`, renderers **MUST** reserve space for a leading row header column throughout the table. This leading column will be blank for `columns`, `group`, and any `row` without a `title`.

- **Group Headers (`group`):** A `group` element acts as a heading that spans all columns of the table. Semantically, `group { ... }` is equivalent to a `row` containing a single `td` with a `colspan` attribute equal to the table's column count. A `group` does not have a `title` and does not render a cell in the row header column.

### 8.4 Structural Elements

#### 8.4.1 List item: `li`

- **Body:** either
  - a block-list of block elements, or
  - a single string body, or
  - a verbatim body
- **Attributes:** `lang` (optional)

#### 8.4.2 `columns` (table header row)

- **Role:** Defines the labels for the columns of a table. The number of cells in this element (taking `colspan` into account) defines the table's column count.
- **Body:** block-list containing `td` (at least one)
- **Attributes:** `lang` (optional)

#### 8.4.3 `row` (table data row)

- **Role:** Defines a row of data in a table.
- **Body:** block-list containing `td` (at least one)
- **Attributes:**
  - `title` (optional string): If present, creates a header cell for the row in an implicit leading column.
  - `lang` (optional)

#### 8.4.4 `group` (table row group)

- **Role:** A heading row that spans all table columns.
- **Body:** inline text
- **Attributes:** `lang` (optional)

#### 8.4.5 `td` (table cell)

- **Role:** A single cell within a table row.
- **Body:** either
  - a block-list of block elements, or
  - a single string body, or
  - a verbatim body
- **Attributes:** `colspan` (optional Integer ≥ 1; default 1), `lang` (optional)

### 8.5 Inline elements

Inline elements appear only in inline-list bodies (or inside string/verbatim, depending on renderer).

#### 8.5.1 `\\em`

- **Role:** emphasis
- **Body:** inline text
- **Attributes:** `lang` (optional)

#### 8.5.2 `\\mono`

- **Role:** monospaced span
- **Body:** inline text
- **Attributes:** `syntax` (optional), `lang` (optional)

#### 8.5.3 `\\strike`, `\\sub`, `\\sup`

- **Role:** strike-through / subscript / superscript
- **Body:** inline text
- **Attributes:** `lang` (optional)

#### 8.5.4 `\link`

- **Role:** foreign hyperlink (external or non-validated target)
- **Body:** inline text
- **Attributes:**
  - `uri` (**required**)
  - `lang` (optional)

Notes:

- `\link` is used for hyperlinks that are not validated as interior document references.
- Interior references use `\ref(ref="...")`.


#### 8.5.5 `\\date`, `\\time`, `\\datetime`

- **Role:** localized date/time rendering
- **Body:** must be plain text, a single string, or verbatim (no nested inline elements)
- **Attributes:** `fmt` (optional; per element), `lang` (optional)

#### 8.5.6 `\ref`

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

- `\ref(ref="X");` (implicit body) is semantically invalid and **MUST** be rejected.
- `\ref(ref="X"){...}` remains valid.

When computing `<name>` for headings, inline footnote/citation markers **SHOULD NOT** contribute to the plaintext (i.e., their marker text is ignored).

#### 8.5.7 `\footnote`

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

Marker rendering (normative):

- A renderer **SHALL** render a regular footnote marker as `\sup{\link{\d+}}`.
- A renderer **SHALL** render a citation marker as `\sup{\link{[\d+]}}`.


## 9. Attribute types and date/time formats

> TODO: Attributes should be documented well and not only be mentioned in the element catalog.
>       This chapter shall document attributes and their types, including detailled descriptions for both.

> TODO: Specify that leading and trailing whitespay is allowed but discouraged.
>       Non-fatal diagnostics **MUST** be emitted for that.
>       Leading and trailing whitespace must be stripped.

### 9.1 Common attribute types

- **Version:** must be `2.0`.
- **Integer:** ASCII decimal digits; leading zeros allowed but discouraged.
- **Reference:** non-empty; must not contain whitespace or control characters.
- **Language tag:** BCP 47 (RFC 5646).
- **Timezone offset:** `Z` or `±HH:MM`.
- **URI/IRI:** per RFC 3987.

### 9.2 Date / time lexical formats (normative)

These formats are a conservative intersection of RFC 3339 and ISO 8601.

#### 9.2.1 Date

`YYYY-MM-DD`

- `YYYY`: one or more digits
- `MM`: `01`-`12`
- `DD`: `01`-`31`

#### 9.2.2 Time

`hh:mm:ss` with a required time zone unless a default `tz` is defined in `hdoc`.

- `hh`: `00`-`23`
- `mm`: `00`-`59`
- `ss`: `00`-`59`
- optional fraction: `.` followed by 1,2,3,6, or 9 digits
- zone:
  - `Z`, or
  - `+hh:mm` / `-hh:mm` (two-digit hour/minute)

If `hdoc(tz="...")` is present, a time value **MAY** omit the zone.

#### 9.2.3 Datetime

`YYYY-MM-DD` `T` `hh:mm:ss` (with optional fraction and required zone, unless `hdoc.tz` is present)

If `hdoc(tz="...")` is present, a datetime value **MAY** omit the zone. This is permitted specifically for `hdoc(date="...")` and for `\datetime` bodies.

### 9.3 `fmt` values

> TODO: `fmt` values need a proper description of what the expected output is.
>       The output is using the `lang` context of the \date, \time, \datetime element and
>       we provide examples in german and english for each `fmt` option.

> TODO: This chapter shall be split into:
>
> - `fmt` for `\date`
> - `fmt` for `\time`
> - `fmt` for `\datetime`

- `\date(fmt=...)`: `year`, `month`, `day`, `weekday`, `short`, `long`, `relative`, `iso`
- `\time(fmt=...)`: `short`, `long`, `rough`, `relative`, `iso`
- `\datetime(fmt=...)`: `short`, `long`, `relative`, `iso`
- `\ref(fmt=...)`: `full`, `name`, `index`

Defaults when omitted:

- `\date(fmt=...)`: default `short`
- `\time(fmt=...)`: default `short`
- `\datetime(fmt=...)`: default `short`
- `\ref(fmt=...)`: default `full`

## 10. Non-normative guidance for tooling

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
