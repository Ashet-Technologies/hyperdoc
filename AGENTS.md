# AGENTS

## General guidelines

- Keep changes focused and incremental; prefer small, reviewable commits.
- Follow existing code style and formatting conventions.
- Use `zig fmt` on Zig source files after edits.
- Ensure new tests are added or updated when behavior changes.
- Run relevant tests (`zig build test`) when making code changes.
- Run `zig build` to validate the main application still compiles
- Test `./zig-out/bin/hyperdoc` with the `.hdoc` files in `examples/`.
- Avoid editing documentation unless the request explicitly asks for it.
