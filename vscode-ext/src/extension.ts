import * as fs from "fs/promises";
import * as vscode from "vscode";
import {
  ATTRIBUTE_SUGGESTIONS,
  ELEMENT_SUGGESTIONS,
  Suggestion,
  computeIsInAttributeList,
  mapSuggestionKind,
  resolveWasmPath
} from "./utils";

class HyperdocCompletionProvider implements vscode.CompletionItemProvider {
  provideCompletionItems(
    document: vscode.TextDocument,
    position: vscode.Position
  ): vscode.ProviderResult<vscode.CompletionItem[]> {
    const inAttributeList = isInAttributeList(document, position);
    const pool = inAttributeList ? ATTRIBUTE_SUGGESTIONS : ELEMENT_SUGGESTIONS;

    return pool.map((item) => createCompletionItem(item));
  }
}

function createCompletionItem(item: Suggestion): vscode.CompletionItem {
  const completion = new vscode.CompletionItem(
    item.label,
    mapSuggestionKind(item.kind)
  );
  completion.detail = item.detail;
  return completion;
}

export function isInAttributeList(
  document: vscode.TextDocument,
  position: vscode.Position
): boolean {
  const text = document.getText(
    new vscode.Range(new vscode.Position(0, 0), position)
  );
  return computeIsInAttributeList(text);
}

class WasmLanguageServerController {
  private wasmModule: WebAssembly.Module | undefined;
  private readonly output: vscode.OutputChannel;

  constructor(private readonly context: vscode.ExtensionContext) {
    this.output = vscode.window.createOutputChannel("HyperDoc");
  }

  async prepareFromConfiguration(): Promise<void> {
    const configuredPath = vscode.workspace
      .getConfiguration("hyperdoc")
      .get<string>("languageServer.wasmPath")
      ?.trim();

    if (!configuredPath) {
      this.wasmModule = undefined;
      this.output.appendLine(
        "HyperDoc wasm language server is disabled (no path configured)."
      );
      return;
    }

    await this.loadWasmModule(configuredPath);
  }

  dispose(): void {
    this.wasmModule = undefined;
    this.output.dispose();
  }

  private async loadWasmModule(rawPath: string): Promise<void> {
    const resolvedPath = resolveWasmPath(rawPath, {
      extensionPath: this.context.extensionPath,
      workspaceFolders: vscode.workspace.workspaceFolders?.map(
        (folder) => folder.uri.fsPath
      )
    });
    this.output.appendLine(
      `Preparing HyperDoc wasm language server stub from: ${resolvedPath}`
    );

    try {
      const bytes = await fs.readFile(resolvedPath);
      const wasmBytes = Uint8Array.from(bytes);
      this.wasmModule = await WebAssembly.compile(wasmBytes);
      this.output.appendLine(
        "Wasm module compiled. Language client wiring is intentionally disabled until the server shim is available."
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      vscode.window.showWarningMessage(
        `HyperDoc: failed to load wasm language server (${message}).`
      );
    }
  }
}

export async function activate(context: vscode.ExtensionContext): Promise<void> {
  const completionProvider = vscode.languages.registerCompletionItemProvider(
    { language: "hyperdoc" },
    new HyperdocCompletionProvider(),
    "\\",
    "{",
    "("
  );

  const wasmController = new WasmLanguageServerController(context);

  const startWasmCommand = vscode.commands.registerCommand(
    "hyperdoc.startWasmLanguageServer",
    async () => {
      await wasmController.prepareFromConfiguration();
      vscode.window.showInformationMessage(
        "HyperDoc wasm language server stub prepared (when configured)."
      );
    }
  );

  const configChangeListener = vscode.workspace.onDidChangeConfiguration(
    async (event) => {
      if (event.affectsConfiguration("hyperdoc.languageServer.wasmPath")) {
        await wasmController.prepareFromConfiguration();
      }
    }
  );

  context.subscriptions.push(
    completionProvider,
    wasmController,
    startWasmCommand,
    configChangeListener
  );

  await wasmController.prepareFromConfiguration();
}

export function deactivate(): void {
  // No-op
}
