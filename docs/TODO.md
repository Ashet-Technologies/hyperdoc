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
