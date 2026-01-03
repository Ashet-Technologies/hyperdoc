# AGENTS

## General guidelines

- Keep changes focused and incremental; prefer small, reviewable commits.
- Follow existing code style and formatting conventions.
- Use `zig fmt` on Zig source files after edits.
- Ensure new tests are added or updated when behavior changes.
- Run relevant tests (`zig build test`) when making code changes.
- Run `zig build` to validate the main application still compiles
- Test `./zig-out/bin/hyperdoc` with the `.hdoc` files in `examples/` and `test/`.
- Avoid editing documentation unless the request explicitly asks for it.
- `src/hyperdoc.zig` must not contain locale- or rendering-specific parts.
- Treat `docs/specification.md` as the authoritative source of behavior; examples may be outdated or incorrect.
- If the spec is unclear or conflicts with code/tests, ask before changing behavior.
- Do not implement "just make it work" fallbacks that alter semantics to satisfy examples.

## Zig Programming Style

- Do not use "inline functions" like `const func = struct { fn func(…) {} }.func;`
- Zig has no methods. Functions used by "method like" functions can still be placed next to them, no need to put them into global scope nor into local scope.

## Snapshot Files

- If you add a `hdoc` file to `test/snapshot`, also:
  - Generate the corresponding html and yaml file
  - Add the file inside build.zig to the snapshot_files global
- If you change behaviour, the snapshot tests will fail. Validate the failure against your expectations and see if you broke something unexpected.