# Ashet HyperDocument Format

## Motivation

> TODO: Write motivation

## Specification

[Read the specification](docs/specification.md).

## Building

Requires [Zig 0.15.2](https://ziglang.org/) installed.

### Build debug application

```sh-session
[user@host] hyperdoc$ zig build
```

### Build release application

```sh-session
[user@host] hyperdoc$ zig build -Drelease
```

### Run test suite

```sh-session
[user@host] hyperdoc$ zig build test
```

> Optional: installing Node.js enables the WASM integration tests that exercise the compiled `hyperdoc_wasm.wasm` via `node test/wasm/validate.js`.
