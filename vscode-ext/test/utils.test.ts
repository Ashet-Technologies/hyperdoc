import { strict as assert } from "node:assert";
import path from "path";
import {
  ATTRIBUTE_SUGGESTIONS,
  ELEMENT_SUGGESTIONS,
  computeIsInAttributeList,
  mapSuggestionKind,
  resolveWasmPath
} from "../src/utils";

describe("computeIsInAttributeList", () => {
  it("returns false when no opening paren is present", () => {
    assert.equal(computeIsInAttributeList("hdoc "), false);
  });

  it("returns true between parentheses before closing", () => {
    const text = 'node(attr="1"';
    assert.equal(computeIsInAttributeList(text), true);
  });

  it("returns false after the closing parenthesis", () => {
    const text = 'node(attr="1") ';
    assert.equal(computeIsInAttributeList(text), false);
  });

  it("returns false if a block brace appears after the last open paren", () => {
    const text = 'node(attr="1"{';
    assert.equal(computeIsInAttributeList(text), false);
  });
});

describe("completion suggestions", () => {
  it("exposes element suggestions with both block and inline names", () => {
    const labels = ELEMENT_SUGGESTIONS.map((s) => s.label);
    assert(labels.includes("hdoc"));
    assert(labels.includes("\\em"));
  });

  it("exposes attribute suggestions", () => {
    const labels = ATTRIBUTE_SUGGESTIONS.map((s) => s.label);
    assert(labels.includes("id"));
    assert(labels.includes("fmt"));
  });
});

describe("mapSuggestionKind", () => {
  it("maps to completion item kinds", () => {
    assert.equal(mapSuggestionKind("class"), 6);
    assert.equal(mapSuggestionKind("function"), 3);
    assert.equal(mapSuggestionKind("property"), 10);
  });
});

describe("resolveWasmPath", () => {
  const extPath = "/extension";

  it("returns absolute paths unchanged", () => {
    const input = "/tmp/server.wasm";
    assert.equal(
      resolveWasmPath(input, { extensionPath: extPath }),
      input
    );
  });

  it("uses workspace folder when available", () => {
    const output = resolveWasmPath("server.wasm", {
      extensionPath: extPath,
      workspaceFolders: ["/workspace/project"]
    });
    assert.equal(output, path.join("/workspace/project", "server.wasm"));
  });

  it("falls back to the extension path", () => {
    const output = resolveWasmPath("server.wasm", {
      extensionPath: extPath
    });
    assert.equal(output, path.join(extPath, "server.wasm"));
  });
});
