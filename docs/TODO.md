# Specification TODOs

- Assign semantics to node types, paragraph kinds, ...
- Specify "syntax" proper
- Add links to RFCs where possible
- \abbrev and \term might be good ideas.
- Add more text to the introduction and underlying ideas of the format:
  - Orthogonality: Semantic structure is not dependend on syntax. Verbatim lines are not preformatted, but `pre` blocks are.
  - Strictness for ecosystem health: Prevent HTML uncontrolled growth desaster
  - Allow tooling to work with semanticall yinvalid documents
  - Static layout: No surprises. Layout once, yield consistent rendering
  - Accessiblity: Everything is semantic, nothing is presentation-only.
- h3 after h1 is not legal
- Support "appendix{}" in addition to h1,h2,h3 which is a h1-level chapter that renders as "A. B. C." instead of "1. 2. 3."

> Recommendation 3: Add Formal Whitespace Processing Algorithm


Recommendation 5: Add Appendix with Formal Schema
Rationale: Current spec requires reading entire document to understand element relationships. Machine-readable schema would enable automatic validation and tooling.
Provide RelaxNG Compact syntax schema defining:


Rationale: Technical documentation needs to emphasize specific code lines (tutorials, diffs, explanations).
pre(syntax="python", highlight="2,4-6"):
| def factorial(n):
|     if n == 0:  # Base case
|         return 1
|     else:
|         return n * factorial(n-1)  # Recursive case
also: enable line numbers
