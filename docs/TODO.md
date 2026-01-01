# Specification TODOs

- Assign semantics to node types, paragraph kinds, ...
- Specify "syntax" proper
- Add links to RFCs where possible
- Document `lang` inheritance. No `lang` attribute means that parent language is used.


- Special-style blocks become block containers
  - The “special paragraph” family (e.g. note, info, warning, danger, tip, spoiler, quote, …) are block containers.
  - Their { ... } list body is always Block-list mode (i.e., they contain blocks like p, ul, ol, pre, etc.).
  - They do not accept inline-list bodies directly. Inline markup requires an explicit paragraph:
    note { p { text with \link(...) { inline } nodes } }
- General implicit-paragraph shorthand (removes special cases)
  - You’re removing the element-specific special casing (like the old quote/li/td convenience rules) and replacing it with one general semantic rule:
  - Rule: If a block element’s list body would allow “regular top-level blocks” (e.g. p, pre, ol, ul, …), then that element’s body MAY be written as a string or verbatim literal.
  - Equivalence: A string/verbatim body is equivalent to a block-list body containing a single paragraph with the same content as plain text.
    Concretely:
      X "TEXT" ≡ X { p "TEXT" }
      X: | TEXT ≡ X { p: | TEXT }
  - Notes:
    - This shorthand produces plain text and therefore follows your normal inline text construction rules (including whitespace normalization).
    - This shorthand should apply to “flow containers” like quote, note, and also fixes li / td ergonomics cleanly.
    - It should not be used for structural containers where a string would be misleading (e.g. ul/ol/table/columns/row), because those don’t “allow regular blocks” as direct children in the first place.
