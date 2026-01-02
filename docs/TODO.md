# Specification TODOs

- Assign semantics to node types, paragraph kinds, ...
- Specify "syntax" proper
- Add links to RFCs where possible
- Document `lang` inheritance. No `lang` attribute means that parent language is used.
- Clarify that page layout is static and won't change except for context resize.
- \abbrev and \term might be good ideas.
- Add more text to the introduction and underlying ideas of the format:
  - Orthogonality: Semantic structure is not dependend on syntax. Verbatim lines are not preformatted, but `pre` blocks are.
  - Strictness for ecosystem health: Prevent HTML uncontrolled growth desaster
  - Allow tooling to work with semanticall yinvalid documents
  - Static layout: No surprises. Layout once, yield consistent rendering
  - Accessiblity: Everything is semantic, nothing is presentation-only.
- h3 after h1 is not legal

> Problem: What if neither columns nor row exists (table with only group)? Spec should require at least one row or columns.

> Problem: What should synthesized text be for valid non-heading targets like table, img, pre? Spec says headings get <index> <name> but doesn't define fallback for figures ("Figure 3"), tables ("Table 2"), etc.

States "A renderer SHALL render a regular footnote marker as \sup{\link{\d+}}"
Problem: This seems like implementation guidance, not semantic requirement. Different renderers (HTML, PDF, terminal) may render markers differently. Should be in §10 (non-normative) or relaxed to "SHOULD".


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
