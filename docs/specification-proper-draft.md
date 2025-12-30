# HyperDoc 2.0

**Status:** Cleaned-up draft.

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

Unless explicitly stated, rules in chapters 3–5 are **syntax** rules; rules in chapters 6–9 are **semantic** rules.

## 3. Document encoding (byte- and line-level)

### 3.1 Character encoding

- A HyperDoc document **MUST** be encoded as UTF-8.
- A HyperDoc document **MUST NOT** contain invalid UTF-8 byte sequences.

**UTF-8 BOM**

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

- `;` — empty body
- `"..."` — string literal body
- `:` — verbatim body (one or more `|` lines)
- `{ ... }` — list body

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

(* verbatim_body and ws productions match the source spec. *)
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
- If braces cannot be balanced, they **must** be written as escape-text tokens `\\{` and `\\}`.
- A backslash in inline content is interpreted as:
  - one of the three escape-text tokens `\\\\`, `\\{`, `\\}`, or
  - the start of an inline node otherwise.

### 5.5 String literals (syntax)

String literals are delimiter-based and do **not** validate escape *meaning*.

Syntactically invalid inside `"..."`:

- raw LF or CR
- a backslash immediately followed by a control character (Unicode `Cc`) — **note:** this includes TAB.

## 6. Escape processing (semantic)

### 6.1 Scope

Escape sequences are recognized only in:

1. String literals (node bodies of the `"..."` form and attribute values).
2. Inline escape-text tokens emitted by the parser: `\\\\`, `\\{`, `\\}`.

No other syntax performs escape decoding.

### 6.2 Control character policy (semantic)

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

- 1–6 hex digits
- value in `0x0..0x10FFFF`
- not in `0xD800..0xDFFF` (surrogates)
- must not decode to a forbidden control character (§6.2)

### 6.4 Invalid escapes

A semantic validator/decoder **MUST** reject a string literal that contains:

- any other escape (`\\t`, `\\xHH`, `\\0`, etc.)
- an unterminated escape (string ends after `\\`)
- malformed `\\u{...}` (missing braces, empty, non-hex, >6 digits)
- out-of-range or surrogate code points
- forbidden control characters produced by `\\u{...}`

### 6.5 Inline escape-text tokens

In inline-list bodies, the parser emits three special text tokens:

- `\\\\`
- `\\{`
- `\\}`

During semantic text construction, implementations **MAY** decode these to literal `\\`, `{`, `}`.

Tooling that aims to preserve author intent **SHOULD** preserve whether braces were written as balanced groups vs escaped brace tokens.

## 7. Semantic document model

### 7.1 Document structure

- A semantically valid document **MUST** contain exactly one `hdoc` header node.
- The `hdoc` node **MUST** be the first node in the document.
- The `hdoc` node **MUST NOT** appear anywhere else.
- The `hdoc` node **MUST** have an empty body (`;`).

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

### 7.5 IDs and references

- `id` is allowed only on **top-level block elements** (direct children of the document; not inside another node).
- `id` values **MUST** be non-empty and **MUST** be unique (case-sensitive) across the document.
- `\link(ref="...")` **MUST** reference an existing `id`.

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

- **Inline-list mode:** `h1`, `h2`, `h3`, `p`, `note`, `warning`, `danger`, `tip`, `quote`, `spoiler`, `img`, `pre`, `group`, and all inline elements (`\em`, `\mono`, `\link`, `\date`, `\time`, `\datetime`, ...).
- **Block-list mode:** `ul`, `ol`, `li`, `table`, `columns`, `row`, `td`.

- Containers (`ul`, `ol`, `table`, `row`, `columns`) naturally contain nested nodes.
- Text blocks (`p`, headings, etc.) contain inline text streams.
- `li` and `td` contain either blocks or a single string/verbatim; representing blocks implies block-list mode.

### 8.2 Element catalog (normative)

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

#### 8.2.2 Headings: `h1`, `h2`, `h3`

- **Role:** block heading levels 1–3
- **Body:** inline text (string body or inline-list body)
- **Attributes:** `lang` (optional), `id` (optional; top-level only)

#### 8.2.3 Paragraph blocks: `p`, `note`, `warning`, `danger`, `tip`, `quote`, `spoiler`

- **Role:** paragraph-like block with semantic hint
- **Body:** inline text (string body or inline-list body)
- **Attributes:** `lang` (optional), `id` (optional; top-level only)

#### 8.2.4 Lists: `ul`, `ol`

- **Body:** block-list containing `li` (at least one)
- **Attributes:** `lang` (optional), `id` (optional; top-level only)

`ol` additional attribute:

- `first` (optional Integer ≥ 0; default 1): number of the first list item

#### 8.2.5 List item: `li`

- **Body:** either
  - a block-list of block elements, or
  - a single string body, or
  - a verbatim body
- **Attributes:** `lang` (optional)

#### 8.2.6 Figure: `img`

- **Body:** inline text caption/description (may be empty)
- **Attributes:**
  - `path` (required, non-empty)
  - `alt` (optional, non-empty recommended)
  - `lang` (optional)
  - `id` (optional; top-level only)

#### 8.2.7 Preformatted: `pre`

- **Body:** either
  - verbatim body (`:`) for literal lines (**recommended**), or
  - inline text body (string or inline-list); whitespace is preserved (no trimming/collapse)
- **Attributes:** `syntax` (optional), `lang` (optional), `id` (optional; top-level only)

#### 8.2.8 Table of contents: `toc`

- **Body:** `;` (empty)
- **Attributes:** `depth` (optional Integer in {1,2,3}; default 3), `lang` (optional), `id` (optional; top-level only)

#### 8.2.9 Tables: `table`

- **Body:** block-list containing:
  - optional `columns`, then
  - zero or more `row` and `group` nodes
- **Attributes:** `lang` (optional), `id` (optional; top-level only)

Table layout rules:

- `columns` defines header labels and the column count.
- Each `row` defines a data row.
- Each `group` acts as a section heading for subsequent rows.
- After applying `td.colspan`, all `row` and `columns` entries **MUST** resolve to the same effective column count.
- If any `row` has a `title` attribute **or** any `group` is present, renderers **MUST** reserve a leading title column.
  - In that case, `columns` **SHOULD** include an empty leading header cell.

#### 8.2.10 `columns` (table header row)

- **Body:** block-list containing `td` (at least one)
- **Attributes:** `lang` (optional)

#### 8.2.11 `row` (table data row)

- **Body:** block-list containing `td` (at least one)
- **Attributes:** `title` (optional string), `lang` (optional)

#### 8.2.12 `group` (table row group)

- **Body:** inline text
- **Attributes:** `lang` (optional)

#### 8.2.13 `td` (table cell)

- **Body:** either
  - a block-list of block elements, or
  - a single string body, or
  - a verbatim body
- **Attributes:** `colspan` (optional Integer ≥ 1; default 1), `lang` (optional)

### 8.3 Inline elements

Inline elements appear only in inline-list bodies (or inside string/verbatim, depending on renderer).

#### 8.3.1 `\\em`

- **Role:** emphasis
- **Body:** inline text
- **Attributes:** `lang` (optional)

#### 8.3.2 `\\mono`

- **Role:** monospaced span
- **Body:** inline text
- **Attributes:** `syntax` (optional), `lang` (optional)

#### 8.3.3 `\\strike`, `\\sub`, `\\sup`

- **Role:** strike-through / subscript / superscript
- **Body:** inline text
- **Attributes:** `lang` (optional)

#### 8.3.4 `\\link`

- **Role:** hyperlink
- **Body:** inline text
- **Attributes:**
  - `ref` or `uri` (**exactly one required**)
  - `lang` (optional)

#### 8.3.5 `\\date`, `\\time`, `\\datetime`

- **Role:** localized date/time rendering
- **Body:** must be plain text, a single string, or verbatim (no nested inline elements)
- **Attributes:** `fmt` (optional; per element), `lang` (optional)

## 9. Attribute types and date/time formats

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
- `MM`: `01`–`12`
- `DD`: `01`–`31`

#### 9.2.2 Time

`hh:mm:ss` with a required time zone unless a default `tz` is defined in `hdoc`.

- `hh`: `00`–`23`
- `mm`: `00`–`59`
- `ss`: `00`–`59`
- optional fraction: `.` followed by 1,2,3,6, or 9 digits
- zone:
  - `Z`, or
  - `+hh:mm` / `-hh:mm` (two-digit hour/minute)

If `hdoc(tz="...")` is present, a time value **MAY** omit the zone.

#### 9.2.3 Datetime

`YYYY-MM-DD` `T` `hh:mm:ss` (with optional fraction and required zone, unless `hdoc.tz` is present)

If `hdoc(tz="...")` is present, a datetime value **MAY** omit the zone. This is permitted specifically for `hdoc(date="...")` and for `\datetime` bodies.

### 9.3 `fmt` values


- `\\date(fmt=...)`: `year`, `month`, `day`, `weekday`, `short`, `long`, `relative`, `iso`
- `\\time(fmt=...)`: `short`, `long`, `rough`, `relative`, `iso`
- `\\datetime(fmt=...)`: `short`, `long`, `relative`, `iso`

Defaults when omitted:

- `\date(fmt=...)`: default `short`
- `\time(fmt=...)`: default `long`
- `\datetime(fmt=...)`: default `short`

## 10. Non-normative guidance for tooling

- Formatters should normalize line endings to LF.
- Provide diagnostics for discouraged patterns (leading/trailing whitespace in attribute values, leading zeros, mixed directionality, etc.).
- For typo recovery, treat unknown nodes as inline-list mode (§5.2).

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

