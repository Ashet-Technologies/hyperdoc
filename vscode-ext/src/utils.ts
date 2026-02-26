import * as path from "path";

export type Suggestion = {
  label: string;
  detail: string;
  kind: "class" | "function" | "property";
};

export const ELEMENT_SUGGESTIONS: Suggestion[] = [
  { label: "hdoc", detail: "Document header", kind: "class" },
  { label: "title", detail: "Document title", kind: "class" },
  { label: "h1", detail: "Heading level 1", kind: "class" },
  { label: "h2", detail: "Heading level 2", kind: "class" },
  { label: "h3", detail: "Heading level 3", kind: "class" },
  { label: "toc", detail: "Table of contents", kind: "class" },
  { label: "footnotes", detail: "Footnote dump", kind: "class" },
  { label: "p", detail: "Paragraph", kind: "class" },
  { label: "note", detail: "Admonition block: note", kind: "class" },
  { label: "warning", detail: "Admonition block: warning", kind: "class" },
  { label: "danger", detail: "Admonition block: danger", kind: "class" },
  { label: "tip", detail: "Admonition block: tip", kind: "class" },
  { label: "quote", detail: "Admonition block: quote", kind: "class" },
  { label: "spoiler", detail: "Admonition block: spoiler", kind: "class" },
  { label: "ul", detail: "Unordered list", kind: "class" },
  { label: "ol", detail: "Ordered list", kind: "class" },
  { label: "li", detail: "List item", kind: "class" },
  { label: "img", detail: "Figure/image", kind: "class" },
  { label: "pre", detail: "Preformatted block", kind: "class" },
  { label: "table", detail: "Table", kind: "class" },
  { label: "columns", detail: "Table columns header", kind: "class" },
  { label: "row", detail: "Table row", kind: "class" },
  { label: "group", detail: "Table row group", kind: "class" },
  { label: "td", detail: "Table cell", kind: "class" },
  { label: "\\em", detail: "Inline emphasis", kind: "function" },
  { label: "\\mono", detail: "Inline monospace", kind: "function" },
  { label: "\\strike", detail: "Inline strikethrough", kind: "function" },
  { label: "\\sub", detail: "Inline subscript", kind: "function" },
  { label: "\\sup", detail: "Inline superscript", kind: "function" },
  { label: "\\link", detail: "Inline link", kind: "function" },
  { label: "\\date", detail: "Inline date", kind: "function" },
  { label: "\\time", detail: "Inline time", kind: "function" },
  { label: "\\datetime", detail: "Inline datetime", kind: "function" },
  { label: "\\ref", detail: "Inline reference", kind: "function" },
  { label: "\\footnote", detail: "Inline footnote", kind: "function" }
];

export const ATTRIBUTE_SUGGESTIONS: Suggestion[] = [
  { label: "id", detail: "Block identifier", kind: "property" },
  { label: "title", detail: "Title attribute", kind: "property" },
  { label: "lang", detail: "Language override", kind: "property" },
  { label: "fmt", detail: "Format selection", kind: "property" },
  { label: "ref", detail: "Reference target", kind: "property" },
  { label: "key", detail: "Footnote key", kind: "property" }
];

export function computeIsInAttributeList(text: string): boolean {
  const lastOpen = text.lastIndexOf("(");
  if (lastOpen === -1) {
    return false;
  }

  const lastClose = text.lastIndexOf(")");
  if (lastClose > lastOpen) {
    return false;
  }

  const afterOpen = text.slice(lastOpen + 1);
  return !afterOpen.includes("{") && !afterOpen.includes("}");
}

export function mapSuggestionKind(kind: Suggestion["kind"]): number {
  switch (kind) {
    case "class":
      return 6;
    case "function":
      return 3;
    case "property":
      return 10;
    default:
      return 9;
  }
}

export function resolveWasmPath(
  rawPath: string,
  context: { extensionPath: string; workspaceFolders?: string[] }
): string {
  if (path.isAbsolute(rawPath)) {
    return rawPath;
  }

  const workspaceFolder = context.workspaceFolders?.[0];
  if (workspaceFolder) {
    return path.join(workspaceFolder, rawPath);
  }

  return path.join(context.extensionPath, rawPath);
}
