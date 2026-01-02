# Specification TODOs

## Tasks

- Assign semantics to node types, paragraph kinds, ...
- Specify "syntax" proper
- Add links to RFCs where possible

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
