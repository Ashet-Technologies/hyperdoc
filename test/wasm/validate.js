#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

const repoRoot = path.join(__dirname, '..', '..');
const wasmPath = path.join(repoRoot, 'zig-out', 'bin', 'hyperdoc_wasm.wasm');

const htmlSnapshotTests = [
  {
    name: 'document_header',
    source: path.join(repoRoot, 'test', 'snapshot', 'document_header.hdoc'),
    expected: path.join(repoRoot, 'test', 'snapshot', 'document_header.html'),
  },
  {
    name: 'paragraph_styles',
    source: path.join(repoRoot, 'test', 'snapshot', 'paragraph_styles.hdoc'),
    expected: path.join(repoRoot, 'test', 'snapshot', 'paragraph_styles.html'),
  },
  {
    name: 'tables',
    source: path.join(repoRoot, 'test', 'snapshot', 'tables.hdoc'),
    expected: path.join(repoRoot, 'test', 'snapshot', 'tables.html'),
  },
];

const diagnosticsInput = {
  accepted: path.join(__dirname, 'diagnostic_accepted.hdoc'),
  rejected: path.join(__dirname, 'diagnostic_rejected.hdoc'),
  expected: path.join(__dirname, 'diagnostics_expected.json'),
};

function assertFileExists(filePath) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing required file: ${filePath}`);
  }
}

function readUtf8(filePath) {
  return fs.readFileSync(filePath, 'utf8');
}

function createLogImports(memoryRef) {
  const state = { buffer: '' };
  return {
    reset_log() {
      state.buffer = '';
    },
    append_log(ptr, len) {
      if (len === 0 || ptr === 0) return;
      const memory = memoryRef.current;
      if (!memory) return;
      const view = new Uint8Array(memory.buffer, ptr, len);
      state.buffer += textDecoder.decode(view);
    },
    flush_log(level) {
      if (state.buffer.length === 0) return;
      const method = ['error', 'warn', 'info', 'debug'][level] || 'log';
      console[method](`[wasm ${method}] ${state.buffer}`);
      state.buffer = '';
    },
  };
}

function getMemory(wasm, memoryRef) {
  const memory = wasm.memory || memoryRef.current;
  memoryRef.current = memory;
  if (!memory) {
    throw new Error('WASM memory is unavailable');
  }
  return memory;
}

async function instantiateWasm() {
  assertFileExists(wasmPath);
  const bytes = await fs.promises.readFile(wasmPath);
  const memoryRef = { current: null };
  const env = createLogImports(memoryRef);
  const { instance } = await WebAssembly.instantiate(bytes, { env });
  memoryRef.current = instance.exports.memory;
  return { wasm: instance.exports, memoryRef };
}

function readString(memory, ptr, len) {
  if (!ptr || len === 0) return '';
  const view = new Uint8Array(memory.buffer, ptr, len);
  return textDecoder.decode(view);
}

function processDocument(ctx, sourceText) {
  const { wasm, memoryRef } = ctx;
  const bytes = textEncoder.encode(sourceText);

  if (!wasm.hdoc_set_document_len(bytes.length)) {
    throw new Error('Failed to allocate WASM document buffer');
  }

  const memoryForInput = getMemory(wasm, memoryRef);
  const docPtr = wasm.hdoc_document_ptr();
  if (bytes.length > 0) {
    new Uint8Array(memoryForInput.buffer, docPtr, bytes.length).set(bytes);
  }

  const ok = wasm.hdoc_process() !== 0;
  const memory = getMemory(wasm, memoryRef);

  const htmlPtr = wasm.hdoc_html_ptr();
  const htmlLen = wasm.hdoc_html_len();
  const html = readString(memory, htmlPtr ?? 0, htmlLen);

  const diagnostics = [];
  const diagCount = wasm.hdoc_diagnostic_count();
  for (let i = 0; i < diagCount; i += 1) {
    const msgPtr = wasm.hdoc_diagnostic_message_ptr(i) ?? 0;
    const msgLen = wasm.hdoc_diagnostic_message_len(i);
    diagnostics.push({
      line: wasm.hdoc_diagnostic_line(i),
      column: wasm.hdoc_diagnostic_column(i),
      message: readString(memory, msgPtr, msgLen),
    });
  }

  return { ok, html, diagnostics };
}

function compareDiagnostics(actual, expected, label) {
  assert.deepStrictEqual(
    actual,
    expected,
    `${label} diagnostics differ.\nExpected: ${JSON.stringify(expected, null, 2)}\nActual: ${JSON.stringify(actual, null, 2)}`,
  );
}

async function runHtmlTests(ctx) {
  for (const test of htmlSnapshotTests) {
    assertFileExists(test.source);
    assertFileExists(test.expected);
    const { ok, html, diagnostics } = processDocument(ctx, readUtf8(test.source));
    assert.equal(ok, true, `WASM processing failed for ${test.name}`);
    assert.deepStrictEqual(diagnostics, [], `Expected no diagnostics for ${test.name}`);
    const expectedHtml = readUtf8(test.expected);
    assert.equal(html, expectedHtml, `Rendered HTML mismatch for ${test.name}`);
  }
}

async function runDiagnosticTests(ctx) {
  assertFileExists(diagnosticsInput.accepted);
  assertFileExists(diagnosticsInput.rejected);
  assertFileExists(diagnosticsInput.expected);

  const expectations = JSON.parse(readUtf8(diagnosticsInput.expected));

  const acceptedResult = processDocument(ctx, readUtf8(diagnosticsInput.accepted));
  assert.equal(acceptedResult.ok, true, 'Accepted diagnostic test should render successfully');
  compareDiagnostics(acceptedResult.diagnostics, expectations.accepted, 'Accepted');

  const rejectedResult = processDocument(ctx, readUtf8(diagnosticsInput.rejected));
  assert.equal(rejectedResult.ok, false, 'Rejected diagnostic test should fail');
  compareDiagnostics(rejectedResult.diagnostics, expectations.rejected, 'Rejected');
}

async function main() {
  const ctx = await instantiateWasm();
  await runHtmlTests(ctx);
  await runDiagnosticTests(ctx);
  console.log('WASM integration tests passed.');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
