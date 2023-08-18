# Ashet HyperDocument Format

This format is used for both the _Hyper Wiki_ as well as the _Gateway_ application to store and display
hyperlinked documents.

The format is a rich-text format that can encode/store/display the following document blocks:

- paragraphs (consisting of a sequence of spans)
  - regular text
  - links
  - bold/emphasised text
  - monospaced text
  - line break
- 3 levels of headings
- ordered and unordered lists
  - each list item is a paragraph or another list
- quotes (paragraph with special styling)
- preformatted text (code blocks, also uses the paragraph formatting)
- images

Regular text is assumed to use a proportional font, while preformatted text is required to be rendered as monospace.

## Storage

HyperDocument is stored as a trivial-to-parse plain text format, not necessarily meant to be edited by humans,
but still human readable.

**Example:**

```lua
hdoc "1.0"
p {
  span "Hello, World!\n"
  link "http://google.com" "Visit Google!"
  span "\n"
  emph "This is fat!"
  span "\n"
  mono "int main()"
  span "\n"
}
enumerate {
  item { p { span "first" } }
  item { p { span "second" } }
  item { p { span "third" } }
}
itemize {
  item { p { span "first" } }
  item { p { span "second" } }
  item { p { span "third" } }
}
quote {
  span "Life is what happens when you're busy making other plans.\n - John Lennon"
}
pre {
  span "const std = @import(\"std\");\n"
  span "\n"
  span "pub fn main() !void {\n"
  span "    std.debug.print(\"Hello, World!\\n\", .{});\n"
  span "}\n"
}
image "dog.png"
```
