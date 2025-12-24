# HyperDoc 2.0

This specification describes the document markup language "HyperDoc 2.0", that tries to be a simple to parse, easy to write markup language for hypertext documents.

It sits somewhat between LaTeX and Markdown and tries to be way simpler to parse than Markdown, but keep useful semantics around.

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

## Grammar

This grammar describes the hypertext format.

Short notes on grammar notation:

- `{ ... }` is a repetition
- `[ ... ]` is an option
- `a | b | c` is alternatives
- `( ... )` is a group
- `"foo"` is a literal token sequence, no escape sequences (So `"\"` is a single backslash)
- `/.../` is a regex
- Whitespace is assumed to be ignored between tokens unless matched by a literal or regex, so tokens are typically separated by whitespace
- Upper case elements are roughly tokens, while lowercase elements are rules.

```ebnf
document       := { block }

block          := WORD [ attribute_list ] body

body           := ";" | list | verbatim | STRING
verbatim       := ":" "\n" { VERBATIM_LINE }

list           := "{" { escape | inline | block | WORD } "}"
escape         := "\\" | "\{" | "\}"
inline         := "\" WORD [ attribute_list ] body

attribute_list := "(" [ attribute { "," attribute } ] ")"
attribute      := WORD "=" STRING

STRING         := /"(\\.|[^"\r\n])*"/
VERBATIM_LINE  := /^\s*\|(.*)$/
WORD           := /[^\s\{\}\\\"(),=:]+/
```

**NOTE:** `list` also allows `block` for `inline` elements, as this enables us to have support for balanced braces without special care. The `block` elements will be flattened when rendering an inline list body into the document.

**NOTE:** All attribute values are strings, so numeric-looking values are still expressed as strings (e.g. `depth="1"`).

## Element Overview

| Element                                                     | Element Type | Allowed Children             | Attributes                                   |
| ----------------------------------------------------------- | ------------ | ---------------------------- | -------------------------------------------- |
| *Document*                                                  | Document     | `hdoc`, Blocks               |                                              |
| `hdoc`                                                      | Header       | -                            | `lang`, `title`, `version`, `author`, `date` |
| `h1`, `h2`, `h3`                                            | Block        | Text Body                    | `lang`, \[`id`\]                             |
| `p`, `note`, `warning`, `danger`, `tip`, `quote`, `spoiler` | Block        | Text Body                    | `lang`, \[`id`\]                             |
| `ul`                                                        | Block        | `li` ≥ 1                     | `lang`, \[`id`\]                             |
| `ol`                                                        | Block        | `li` ≥ 1                     | `lang`, \[`id`\], `first`                    |
| `img`                                                       | Block        | Text Body                    | `lang`, \[`id`\], `alt`, `path`              |
| `pre`                                                       | Block        | Text Body                    | `lang`, \[`id`\], `syntax`                   |
| `toc`                                                       | Block        | -                            | `lang`, \[`id`\], `depth`                    |
| `table`                                                     | Block        | Table Rows                   | `lang`, \[`id`\]                             |
| `columns`                                                   | Table Row    | `td` ≥ 1                     | `lang`                                       |
| `group`                                                     | Table Row    | Text Body                    | `lang`,                                      |
| `row`                                                       | Table Row    | `td` ≥ 1                     | `lang`, `title`                              |
| `td`                                                        | Table Cell   | Blocks, String, Verbatim     | `lang`, `colspan`                            |
| `li`                                                        | List Item    | Blocks, String, Verbatim     | `lang`                                       |
| `\em`                                                       | Text Body    | Text Body                    | `lang`                                       |
| `\mono`                                                     | Text Body    | Text Body                    | `lang`, `syntax`                             |
| `\strike`                                                   | Text Body    | Text Body                    | `lang`                                       |
| `\sub`, `\sup`                                              | Text Body    | Text Body                    | `lang`                                       |
| `\link`                                                     | Text Body    | Text Body                    | `lang`, (`ref` \| `uri`)                     |
| `\date`, `\time`, `\datetime`                               | Text Body    | Plain Text, String, Verbatim | `lang`, `fmt`                                |
| *Plain Text*                                                | Text Body    | -                            |                                              |
| *String*                                                    | Text Body    | -                            |                                              |
| *Verbatim*                                                  | Text Body    | -                            |                                              |

Notes:

- The attribute `id` is only allowed when the element is a top-level element (direct child of the document)
- The attributes `ref` and `uri` on a `\link` are mutually exclusive
- `\date`, `\time` and `\datetime` cannot contain other text body items except for plain text, string or verbatim content.

## Attribute Overview

| Attribute | Required | Allowed Values                                                                                                                                                                            | Description                                                                     |
| --------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `version` | Yes      | `2.0`                                                                                                                                                                                     | Describes the version of this HyperDoc document.                                |
| `lang`    | No       | [BCP 47 Language Tag](https://datatracker.ietf.org/doc/html/rfc5646)                                                                                                                      | Defines the language of the elements contents.                                  |
| `title`   | No       | *Any*                                                                                                                                                                                     | Sets the title of the document or the table row.                                |
| `author`  | No       | *Any*                                                                                                                                                                                     | Sets the author of the document.                                                |
| `date`    | No       | A date-time value using the format specified below (intersection between [RFC3339](https://datatracker.ietf.org/doc/html/rfc3339) and [ISO 8601](https://en.wikipedia.org/wiki/ISO_8601)) | Sets the authoring date of the document.                                        |
| `id`      | No       | Non-empty                                                                                                                                                                                 | Sets a reference which can be linked to with `\link(ref="...")`.                |
| `first`   | No       | Decimal integer numbers ≥ 0                                                                                                                                                               | Sets the number of the first list item.                                         |
| `alt`     | No       | Non-empty                                                                                                                                                                                 | Sets the alternative text shown when an image cannot be loaded.                 |
| `path`    | Yes      | Non-empty file path to an image file                                                                                                                                                      | Defines the file path where the image file can be found.                        |
| `syntax`  | No       | *See element documentation*                                                                                                                                                               | Hints the syntax highlighter how how the elements context shall be highlighted. |
| `depth`   | No       | `1`, `2` or `3`                                                                                                                                                                           | Defines how many levels of headings shall be included.                          |
| `colspan` | No       | Decimal integer numbers ≥ 1                                                                                                                                                               | Sets how many columns the table cell spans.                                     |
| `ref`     | No       | Any value present in an `id` attribute.                                                                                                                                                   | References any `id` inside this document.                                       |
| `uri`     | No       | [Internationalized Resource Identifier (IRI)](https://datatracker.ietf.org/doc/html/rfc3987)                                                                                              | Links to a foreign document with a URI.                                         |
| `fmt`     | No       | *See element documentation*                                                                                                                                                               |                                                                                 |

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
| `date`     | `fmt`     | `year`, `month`, `day`, `weekday`, `short`, `long`, `relative`.                                             |
| `time`     | `fmt`     | `short`, `long`, `rough`, `relative`.                                                                       |
| `datetime` | `fmt`     | `short` (localized date+time), `long` (localized date+time with seconds), `relative`, `iso` (raw ISO 8601). |

Renders a [ISO 8601](https://en.wikipedia.org/wiki/ISO_8601#Combined_date_and_time_representations) date, time or date+time in a localized manner.

