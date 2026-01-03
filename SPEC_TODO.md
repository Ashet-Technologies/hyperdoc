# Spec compliance TODOs

- Title/header interplay lacks the required comparison.  
  - Expect: When both `hdoc(title=...)` and `title { ... }` are present, their plaintext forms are compared and a redundancy hint is emitted if they match (§8.1).  
  - Actual: The block title is used and the header title is ignored without any comparison or diagnostics.  
  - Proposed: Compare the plaintext values, warn when redundant, and keep emitting hints when neither title form is present.
