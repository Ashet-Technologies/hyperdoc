# Spec compliance TODOs

- Inline escape tokens remain undecoded in inline text construction.  
  - Expect: `\\`, `\{`, and `\}` tokens produced in inline bodies decode to literal `\`, `{`, and `}` during semantic processing (§6.1).  
  - Actual: Inline text spans keep the backslash sequences verbatim, so escapes render incorrectly.  
  - Proposed: Decode these three escape tokens before span merging while preserving locations.

- String literal control character policy is incomplete.  
  - Expect: Resolved string values must reject control characters except LF and CR when immediately followed by LF (§7.1).  
  - Actual: `\r` escapes decode to lone CR codepoints without diagnostics, so invalid CR characters survive into resolved text.  
  - Proposed: Reject `\r` unless it participates in a CRLF sequence after escape decoding.

- Identifier parsing permits extra characters.  
  - Expect: Node names use identifier characters limited to letters, digits, and `_`, with inline names beginning with `\`; attribute keys are hyphen-separated segments of the same identifier characters (§5.1, §4.3).  
  - Actual: Identifiers allow `-` and `\` in any position, so node and attribute names outside the grammar are accepted.  
  - Proposed: Align identifier character checks with the grammar and treat hyphens only as separators for attribute keys.

- Heading sequencing rules are missing.  
  - Expect: `h2` must follow an `h1`, and `h3` must follow an `h2` without intervening `h1` (§9.2.3).  
  - Actual: Heading indices increment without validating the required ordering.  
  - Proposed: Track the last seen heading levels and emit errors when a heading appears without its required parent level.

- Title/header interplay lacks the required comparison.  
  - Expect: When both `hdoc(title=...)` and `title { ... }` are present, their plaintext forms are compared and a redundancy hint is emitted if they match (§8.1).  
  - Actual: The block title is used and the header title is ignored without any comparison or diagnostics.  
  - Proposed: Compare the plaintext values, warn when redundant, and keep emitting hints when neither title form is present.

- Top-level-only elements are allowed to nest.  
  - Expect: `h1`/`h2`/`h3`, `toc`, and `footnotes` may only appear as top-level blocks (§9.2).  
  - Actual: Nested blocks (e.g., `note { h1 ... }`) accept these nodes, so top-level elements render within other containers.  
  - Proposed: Reject top-level elements when they appear in nested block lists.

- Containers do not restrict children to general text blocks.  
  - Expect: `li`, `td`, and admonition blocks contain general text block elements (with shorthand promotion) and may be empty for admonitions (§9.1.3, §9.3.2, §9.4.5).  
  - Actual: Block lists in these containers accept any block type (including headings and footnotes) and treat empty lists as errors.  
  - Proposed: Limit children to the allowed general text blocks and permit empty admonition bodies.

- `\time` accepts an unsupported `fmt`.  
  - Expect: `\time(fmt=...)` supports only `iso`, `short`, `long`, and `rough` (§10.3.4).  
  - Actual: The `fmt` enum includes `relative`, so `fmt="relative"` is accepted.  
  - Proposed: Remove the unsupported variant and reject unknown `fmt` values.

- `\ref` is permitted inside headings and titles.  
  - Expect: `\ref` must not appear inside `h1`/`h2`/`h3` or `title` bodies (§9.5.6).  
  - Actual: Inline translation allows references in these contexts without diagnostics.  
  - Proposed: Detect and reject `\ref` nodes while processing heading and title bodies.
