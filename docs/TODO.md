# Specification TODOs

- Assign semantics to node types, paragraph kinds, ...
- Specify "syntax" proper
- Add links to RFCs where possible
- Document `lang` inheritance. No `lang` attribute means that parent language is used.
- Clarify that page layout is static and won't change except for context resize.
- \abbrev and \term might be good ideas.

> Okay, next task: Fix chapter 6 (escapes) by splitting into two chapters (described in 308-315), clarify how control characters are handled (L328)



> §5.5 - String Literal Control Character Inconsistency

§5.5 forbids "any Unicode control characters" in string literals
§6.3 allows \n (LF) and \r (CR) escape sequences
Problem: These decode to control characters (Cc), contradicting §6.2 which says "resolved string-literal values" must not contain control characters except line terminators. Need explicit carve-out.

> Problem: How does this interact with inline \time and \datetime elements? Do they inherit it? §9.2.2 says "If hdoc(tz="...") is present, a time value MAY omit the zone," but doesn't specify how the default is applied during rendering.

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
