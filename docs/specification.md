# HyperDoc 2.0

This specification describes the document markup language "HyperDoc 2.0", that tries to be a simple to parse, easy to write markup language for hypertext documents.

It sits somewhat between LaTeX and Markdown and tries to be way simpler to parse than Markdown, but keep useful semantics around.

## Syntax Overview

```hdoc
hdoc "2.0"

h1{HyperDoc 2.0}

toc{}

h2{Paragraphs}

p { This is a simple paragraph containing text. }

p(id="foo") {
  This is a paragraph with an attribute "id" with the value "foo".
}

p {
  This paragraph contains \em{inline} formatting. We don't support \strike{bold} or \strike{italic} as it's a stylistic choice.
  Other formatting we have is \mono{monospaced}, superscript (x\sup{2}) and subscript(x\sub{2}).
  We can also \link(ref="foo"){link to other parts of a document} or \link(url="https://ashet.computer"){to websites}.
  With \mono(syntax="c"){int *value = 10;} we can also have language information and potential syntax highlighting attached to monospaced font.
}

h2{Special Paragraphs}

note    { HyperDoc 2.0 also supports different types of paragraphs. }
warning { These should affect rendering, and have well-defined semantics attached to them. }
danger  { You shall not assume any specific formatting of these elements though. }
tip     { They typically have a standardized style though. }
quote   { You shall not pass! }
spoiler { Nobody expects the Spanish Inquisition! }

h2{Literals and Preformatted Text}

p:
| we can also use literal lines.
| these are introduced by a trailing colon (':') at the end of a line.
| each following line that starts with whitespace followed by a pipe character ('|')
| is then part of the contents.
| Literal lines don't perform any parsing, so they don't require any escaping of characters.
| This is really useful for code blocks:

pre(syntax="c"):
| #include <stdio.h>
| int main(int argc, char const * argv[]) {
|   printf("Hello, World!\n");
|   return 0;
| }

h2{String Literals}

p "It's also possible to use a string literal for bodies if desired."

p { \em "Magic" is a simple way to highlight single words or text with escaping in inlines. }

h2{Images & Figures}

p { We can also add images to our documents: }

img(id="fig1", path="./preview.jpeg") { If this is non-empty, it's a figure caption. }

h2{Lists}

p { Also lists are possible: }

h3{Unordered Lists}

ul {
  li { p { Apples } }
  li { p { Bananas } }
  li { p { Cucumbers } }
}

h3{Ordered Lists}

ol {
  li { p { Collect underpants } }
  li { p { ? } }
  li { p { Profit } }
}

h2{Tables}

p { And last, but not least, we can have tables: }

table {
  columns {
    td "Key"
    td "Value"
  }
  row {
    td "Author"
    td { Felix "xq" Queißner }
  }
  row {
    td "Date of Invention"
    td { \date{2025-12-17} }
  }
}
```

## Grammar

This grammar describes the text format

Short notes on grammar notation:

- `{ ... }` is a repetition
- `[ ... ]` is an option
- `a | b | c` is alternatives
- `( ... )` is a group
- `"foo"` is a literal token sequence, no escape sequences (So `"\"` is a single backslash)
- `/.../` is a regex
- Whitespace is assumed to be ignored between tokens unless matched by a literal or regex, so tokens are typically separated by whitespace
- Upper case elements are roughly tokens, while lowercase elements are rules.

```
document       := HEADER { block }

block          := IDENTIFIER [ attribute_list ] body

body           := list | literal | STRING
literal        := ":" "\n" { LITERAL_LINE }

list           := "{" { escape | inline | block | WORD } "}"
escape         := "\\" | "\{" | "\}"
inline         := "\" IDENTIFIER [ attribute_list ] body

attribute_list := "(" [ attribute { "," attribute } ] ")"
attribute      := IDENTIFIER "=" STRING

IDENTIFIER     := /\b\w+\b/
HEADER         := /^hdoc\s+"2.0"\s*$/
STRING         := /"(\\.|[^"\r\n])*"/
LITERAL_LINE   := /^\s*\|(.*)$/
WORD           := /[^\s\{\}\\]+/
```

**NOTE:** `list` also allows `block` for `inline` elements, as this enables us to have support for balanced braces without special care. The `block` elements will be flattened when rendering an inline list body into the document.

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

| Attribute | Function                                                                                                             |
| --------- | -------------------------------------------------------------------------------------------------------------------- |
| `first`   | An integer that is the number of the *first* item of the list. Allows paragraph breaks between a single joined list. |

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

| Attribute | Function                                                                |
| --------- | ----------------------------------------------------------------------- |
| `depth`   | `1`, `2` or `3`. Defines how many levels of headings shall be included. |

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

Allowed Items: `columns`, `row`, `group`

> TODO: Spec out tables proper.
> `columns` is basically a `row` with only column headings
> `row` is just a row with cells
> all rows must contain the same amount of cell span
> `group` is a heading for subsequent rows
> `row.title` attribute is displayed in a column left of the first column, the top-left element is always empty

## Table Elements

### Column Headers: `columns`

**Allowed Items:** `td`

This element contains cells 

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

| Attribute | Function                                           |
| --------- | -------------------------------------------------- |
| `colspan` | Integer defining how many columns this cell spans. |

This element contains the contents of a table cell.

> TODO: Similar to `li`, it can be string or block-sequence.

## Inline Text

These elements are all allowed inside a paragraph-like content and can typically be nested.

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
| `ref`     | Points the link to a top-level block with the `id` of this `ref` attribute. Mutually exclusive to `url`. |
| `url`     | Points the link to the resource inside the `url`. Mutually exclusive to `ref`. |

Adds a hyperlink to the contents. This allows a reader to navigate by typically clicking the link.

### Localized Date/Time: `date`, `time`, `datetime`

**Nesting:** No

Renders a [ISO 8601](https://en.wikipedia.org/wiki/ISO_8601#Combined_date_and_time_representations) date, time or date+time in a localized manner.

> TODO: Add `fmt` attribute:
> `\date` takes an attribute fmt which can be 
> - "year" (2025)
> - "month" (December),
> - "day" (22th)
> - "weekday" (monday)
> - "short" (22.12.2025)
> - "long" (22th of December 2025)
> - "relative" (two days ago, two months ago, ...)
>
> `\time` takes an attribute fmt which can be 
> - "short" (09:41)
> - "long" (09:41:25)
> - "rough" (early morning, morning, noon, afternoon, evening, late in the night, ...)
> - "relative" (two minutes ago, two days ago, ...)
> 
> `\datetime` takes an attribute fmt which can be 
> - *To be done*
> - ...
> 