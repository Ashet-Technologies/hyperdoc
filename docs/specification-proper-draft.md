# HyperDoc 2.0

**Status:** Cleaned-up draft.

## 0. Chapter Status

Chapters that are marked FROZEN must not be changed by AI agents.

FROZEN:  No changes allowed.
DONE:    Semantics are correct, language might need improvement.
DRAFT:   Current semantics are not finalized yet.
MISSING: Chapter needs to be added still.

- "1. Introduction": DONE
- "2. Conformance and terminology": FROZEN
- "3. Document encoding (byte- and line-level)": DONE
- "4. Syntactic model": DONE
- "5. Grammar and additional syntax rules"
  - "5.1 Grammar (EBNF)": DRAFT
  - "5.2 Deterministic list-mode disambiguation: DONE
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
  - "7.5 IDs and references": DRAFT
  - "7.6 Built-in element recognition": DONE
- "8. Elements and attributes"
  - "8.1 Built-in elements and list mode"
    - "8.1.1 Inline vs block": DONE
    - "8.1.2 List-body mode per built-in element": TODO
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
  - "8.3 Inline elements"
    - "8.3.1 `\\em`": DRAFT
    - "8.3.2 `\\mono`": DRAFT
    - "8.3.3 `\\strike`, `\\sub`, `\\sup`": DRAFT
    - "8.3.4 `\\link`": DRAFT
    - "8.3.5 `\\date`, `\\time`, `\\datetime`": DRAFT
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
- `:` - verbatim body (one or more `|` lines)
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
- If braces cannot be balanced, they **must** be written as escape-text tokens `\{` and `\}`.
- A backslash in inline content is interpreted as:
  - one of the three escape-text tokens `\\`, `\{`, `\}`, or
  - the start of an inline node otherwise.

### 5.5 String literals (syntax)

> TODO: This chapter requires improved wording. String literals are basically parsed by:
>
> ```pseudo
> assert next() == '"'
> while(not eof()):
>   char = next()
>   if char == '\\':
>     _ = next() # skip character
>   elif char == '"':
>     break # end of string literal
>   elif is_control(char): # includes CR, LF, TAB and all other control characters
>     abort() # invalid character
> ```

String literals are delimiter-based and do **not** validate escape *meaning*.

Syntactically invalid inside `"..."`:

- raw LF or CR
- a backslash in the last position of the string (`\"` never terminates the string literal)
- a control character (Unicode `Cc`) - **note:** this includes TAB.

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

### 7.5 IDs and references

> TODO: References must not contain control characters or whitespace. They can be any sequence of characters that are not spaces or control characters.

- `id` is allowed only on **top-level block elements** (direct children of the document; not inside another node).
- `id` values **MUST** be non-empty and **MUST** be unique (case-sensitive) across the document.

#### Interior references (`ref`)

- A `ref` attribute value **MUST** be a valid Reference value (§9.1).
- `\ref(ref="...")` **MUST** reference an existing top-level `id`.

#### Footnote references (`key` / `ref`)

Footnotes define a separate reference namespace from top-level `id`:

- `\footnote(key="..."){...}` defines a footnote key in the **footnote namespace**.
- Footnote keys **MUST** be unique (case-sensitive) within the footnote namespace.
- `\footnote(ref="...");` **MUST** reference an existing footnote key.


### 7.6 Built-in element recognition

- Built-in element names are defined in §8.
- Unknown elements are syntactically valid (parseable), but semantically invalid.

## 8. Elements and attributes

### 8.1 Built-in elements and list mode

#### 8.1.1 Inline vs block

- Any element name starting with `\` is an **inline element**.
- Any element name not starting with `\` is a **block element**.

#### 8.1.2 List-body mode per built-in element

> TODO: `li` and `td` have an auto-upgrade rule, which performs a conversion of string/verbatim body to `{ p { <content of body> } }`.
>       This means they auto-upgrade their body from literal to "paragraph with literal content"

When a built-in element uses a `{ ... }` list body, it is parsed in the mode below:

- **Inline-list mode:** `title`, `h1`, `h2`, `h3`, `p`, `note`, `warning`, `danger`, `tip`, `quote`, `spoiler`, `img`, `pre`, `group`, and all inline elements (`\em`, `\mono`, `\link`, `\ref`, `\footnote`, `\date`, `\time`, `\datetime`, ...).
- **Block-list mode:** `ul`, `ol`, `li`, `table`, `columns`, `row`, `td`.

- Containers (`ul`, `ol`, `table`, `row`, `columns`) naturally contain nested nodes.
- Text blocks (`title`, `p`, headings, etc.) contain inline text streams.
- `li` and `td` contain either blocks or a single string/verbatim; representing blocks implies block-list mode.

### 8.2 Element catalog (normative)

> TODO: "inline text" bodies are:
>
> - inline list body
> - string body
> - verbatim body
>
> So only an empty body is not "inline text"

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

- **Role:** block heading levels 1-3
- **Body:** inline text (string body or inline-list body)
- **Attributes:** `lang` (optional), `id` (optional; top-level only)

#### 8.2.3 Paragraph blocks: `p`, `note`, `warning`, `danger`, `tip`, `quote`, `spoiler`

- **Role:** paragraph-like block with semantic hint
- **Body:** inline text (string body or inline-list body)
- **Attributes:** `lang` (optional), `id` (optional; top-level only)

#### 8.2.4 Lists: `ul`, `ol`

> TODO: Split into two separate parts "Unordered Lists" and "Ordered Lists"

- **Body:** block-list containing `li` (at least one)
- **Attributes:** `lang` (optional), `id` (optional; top-level only)

`ol` additional attribute:

- `first` (optional Integer ≥ 0; default 1): number of the first list item

#### 8.2.5 List item: `li`

> TODO: Include correct body upgrade rules

- **Body:** either
  - a block-list of block elements, or
  - a single string body, or
  - a verbatim body
- **Attributes:** `lang` (optional)

#### 8.2.6 Figure: `img`

- **Body:** inline text caption/description (may be empty)
- **Attributes:**
  - `path` (required, non-empty)
  - `alt` (optional, non-empty)
  - `lang` (optional)
  - `id` (optional; top-level only)

#### 8.2.7 Preformatted: `pre`

> TODO: Body is always just "inline text", as verbatim bodies are also always inline text.

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

> TODO: `group` is not a "row with implicit title and no cells", but basically
>       `group { <text> }` is equivalent to `columns { td(colspan="<all>") { <text> } }`,
>       so a regular row with a single cell spanning all columns.
>       `group` never implies the existence of the "leading title column"

> TODO: The `row(title="…")` does never affect the effective column count.
>       It implies an additional untitled first column, which is blank in `columns` and `group` rows.
>       The `title` row is designed to form matrices with an empty top-left field.

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

> TODO: Include correct body upgrade rules

- **Body:** either
  - a block-list of block elements, or
  - a single string body, or
  - a verbatim body
- **Attributes:** `colspan` (optional Integer ≥ 1; default 1), `lang` (optional)

#### 8.2.X `title` (document title)

- **Role:** document-level display title
- **Body:** inline text (string body or inline-list body)
- **Attributes:** `lang` (optional)

Semantic constraints:

- `title` **MUST** be a top-level block element.
- `title` **MUST** appear at most once.
- If present, `title` **MUST** be the second node in the document (after `hdoc`).
- `title` **MUST NOT** have an `id` attribute.

#### 8.2.X Footnote dump: `footnotes`

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

#### 8.3.4 `\link`

- **Role:** foreign hyperlink (external or non-validated target)
- **Body:** inline text
- **Attributes:**
  - `uri` (**required**)
  - `lang` (optional)

Notes:

- `\link` is used for hyperlinks that are not validated as interior document references.
- Interior references use `\ref(ref="...")`.


#### 8.3.5 `\\date`, `\\time`, `\\datetime`

- **Role:** localized date/time rendering
- **Body:** must be plain text, a single string, or verbatim (no nested inline elements)
- **Attributes:** `fmt` (optional; per element), `lang` (optional)

#### 8.3.X `\ref`

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

#### 8.3.X `\footnote`

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
