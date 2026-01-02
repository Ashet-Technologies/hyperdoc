# Specification TODOs

## Tasks

- Assign semantics to node types, paragraph kinds, ...
- Specify "syntax" proper
- Add links to RFCs where possible

- Verbatim-body to text conversion is under-specified. You define verbatim syntax (: with | lines) and later say verbatim bodies become inline text spans (§8.2), but you don’t precisely define how piped lines join (LF vs preserving original CRLF, whether there is a trailing newline, whether a final EOF line_terminator contributes a newline, etc.). Different implementations may diverge. 
- Inline “groups” exist syntactically but are not given explicit semantics. The grammar includes inline_group ::= "{" , inline_content , "}" and §5.4 makes brace balancing a core rule, but §8.2 doesn’t explicitly state that groups are semantically transparent (flattened) versus affecting whitespace normalization boundaries or span merging. 
- Span attribute semantics are referenced but not fully defined. §8.2 introduces spans with an “attribute set (e.g. emphasis/monospace/link…)” but the spec never fully defines the canonical attribute keys, nesting behavior (e.g., \em inside \mono), or how lang overrides interact at span level. That’s a major interoperability risk because renderers may differ even if parsers agree. 
- 

## Potential Future Features

### `appendix` element

- Support "appendix{}" in addition to h1,h2,h3 which is a h1-level chapter that renders as "A. B. C." instead of "1. 2. 3."

### Abbreviations

- \abbrev(title="Antiblockiersystem"){ABS} defines a new abbreviation
- \abbrev{ABS} references an existing abbreviation
- \abbrev(title) can only be set once.
- glossary; emits a glossary/definition list of all abbreviations

### Definition Lists

- deflist {structural} is a definition list
- term {inline} defines a new term, must be followed by a 
- def { blocks } definition for the term

### Glossary

- \indexed{Word} adds a new entry to the index.
- index; emits an index with refs to all `\index`ed words.

### Formal Whitespace Processing Algorithm

Write a formal definition of the whitespace processing algorithm so it can be easily replicated.

### Formal Language Schema

Recommendation 5: Add Appendix with Formal Schema
Rationale: Current spec requires reading entire document to understand element relationships. Machine-readable schema would enable automatic validation and tooling.
Provide RelaxNG Compact syntax schema defining:

### Highlighted Lines and Line Numbering

Rationale: Technical documentation needs to emphasize specific code lines (tutorials, diffs, explanations).
pre(syntax="python", highlight="2,4-6"):
| def factorial(n):
|     if n == 0:  # Base case
|         return 1
|     else:
|         return n * factorial(n-1)  # Recursive case
also: enable line numbers

## Rejected Features

- `\kbd{…}` is just `\mono(syntax="kbd"){…}`
- `include(path="...")` is rejected for unbounded document content growth
