import { EditorState } from "@codemirror/state";
import { EditorView, keymap, lineNumbers, highlightActiveLineGutter } from "@codemirror/view";
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import { bracketMatching, foldGutter, foldKeymap, indentOnInput, syntaxHighlighting, HighlightStyle } from "@codemirror/language";
import { oneDark } from "@codemirror/theme-one-dark";
import { tags } from "@lezer/highlight";

import { javascript } from "@codemirror/lang-javascript";
import { json } from "@codemirror/lang-json";
import { rust } from "@codemirror/lang-rust";
import { python } from "@codemirror/lang-python";
import { go } from "@codemirror/lang-go";
import { markdown } from "@codemirror/lang-markdown";
import { html } from "@codemirror/lang-html";
import { css } from "@codemirror/lang-css";
import { sql } from "@codemirror/lang-sql";
import { java } from "@codemirror/lang-java";

function el(tag, attrs = {}, children = []) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (key === "class") node.className = value;
    else if (key === "text") node.textContent = value;
    else node.setAttribute(key, value);
  }
  for (const child of children) node.append(child);
  return node;
}

function nowTime() {
  const d = new Date();
  return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
}

function extname(p) {
  const i = p.lastIndexOf(".");
  return i >= 0 ? p.slice(i + 1).toLowerCase() : "";
}

function languageForPath(filePath) {
  const ext = extname(filePath);
  switch (ext) {
    case "js":
    case "mjs":
    case "cjs":
      return javascript({ typescript: false, jsx: true });
    case "ts":
    case "tsx":
      return javascript({ typescript: true, jsx: true });
    case "json":
      return json();
    case "rs":
      return rust();
    case "py":
      return python();
    case "go":
      return go();
    case "md":
    case "markdown":
      return markdown();
    case "html":
    case "htm":
      return html();
    case "css":
      return css();
    case "sql":
      return sql();
    case "java":
      return java();
    default:
      return null;
  }
}

async function fetchInitial() {
  const res = await fetch("/api/file");
  if (!res.ok) throw new Error(`Failed to load file: ${res.status}`);
  return await res.json();
}

async function saveText(text) {
  const res = await fetch("/api/save", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ text }),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`Save failed (${res.status}): ${body}`);
  }
}

const stoaDarkish = HighlightStyle.define([
  { tag: tags.keyword, color: "#c792ea" },
  { tag: [tags.name, tags.deleted, tags.character, tags.propertyName, tags.macroName], color: "#82aaff" },
  { tag: [tags.function(tags.variableName), tags.labelName], color: "#82aaff" },
  { tag: [tags.color, tags.constant(tags.name), tags.standard(tags.name)], color: "#f78c6c" },
  { tag: [tags.definition(tags.name), tags.separator], color: "#c3e88d" },
  { tag: [tags.typeName, tags.className], color: "#ffcb6b" },
  { tag: [tags.number, tags.changed, tags.annotation, tags.modifier, tags.self, tags.namespace], color: "#f78c6c" },
  { tag: [tags.operator, tags.operatorKeyword], color: "#89ddff" },
  { tag: [tags.url, tags.escape, tags.regexp, tags.link], color: "#89ddff" },
  { tag: [tags.meta, tags.comment], color: "#6b7280" },
  { tag: tags.string, color: "#c3e88d" },
  { tag: tags.invalid, color: "#ff5370" },
]);

(async function main() {
  const root = document.getElementById("app");
  root.replaceChildren();

  const header = el("div", { class: "header" });
  const title = el("div", { class: "title", text: "CodeMirror Demo" });
  const meta = el("div", { class: "meta", text: "" });
  const status = el("div", { class: "status", text: "Loading…" });
  header.append(title, meta, status);

  const editorHost = el("div", { class: "editorHost" });
  const editorRoot = el("div", { class: "editorRoot" });
  editorHost.append(editorRoot);

  const hint = el("div", {
    class: "hint",
    text: "Cmd+S saves. This demo writes plain text back to the file path you pass to ./cm.",
  });

  root.append(header, editorHost, hint);

  const initial = await fetchInitial();
  meta.textContent = initial.path ? `File: ${initial.path}` : "No file configured";

  const lang = initial.path ? languageForPath(initial.path) : null;
  let savedText = String(initial.text ?? "");
  let saving = false;

  const onSave = async (view) => {
    if (saving) return true;
    saving = true;
    status.textContent = "Saving…";
    const text = view.state.doc.toString();
    try {
      await saveText(text);
      savedText = text;
      status.textContent = `Saved ${nowTime()}`;
    } catch (err) {
      console.error(err);
      status.textContent = `Save failed: ${String(err.message || err)}`;
    } finally {
      saving = false;
    }
    return true;
  };

  const state = EditorState.create({
    doc: savedText,
    extensions: [
      oneDark,
      syntaxHighlighting(stoaDarkish, { fallback: true }),
      lineNumbers(),
      highlightActiveLineGutter(),
      history(),
      foldGutter(),
      indentOnInput(),
      bracketMatching(),
      keymap.of([
        indentWithTab,
        ...defaultKeymap,
        ...historyKeymap,
        ...foldKeymap,
        {
          key: "Mod-s",
          run: onSave,
          preventDefault: true,
        },
      ]),
      EditorView.updateListener.of((update) => {
        if (!update.docChanged) return;
        const current = update.state.doc.toString();
        status.textContent = current === savedText ? `Saved ${nowTime()}` : "Modified";
      }),
      lang ? lang : [],
    ],
  });

  const view = new EditorView({
    state,
    parent: editorRoot,
  });

  status.textContent = `Loaded ${nowTime()}`;
})();

const style = document.createElement("style");
style.textContent = `
  html, body { height: 100%; margin: 0; background: #0b0e14; color: #e6edf3; }
  #app { height: 100%; display: flex; flex-direction: column; }
  .header {
    display: flex; gap: 16px; align-items: baseline;
    padding: 10px 12px; border-bottom: 1px solid rgba(255,255,255,0.08);
    background: rgba(255,255,255,0.02);
  }
  .title { font: 600 13px/1.2 ui-sans-serif, system-ui, -apple-system; }
  .meta { font: 12px/1.2 ui-monospace, SFMono-Regular, Menlo, monospace; opacity: 0.8; }
  .status { margin-left: auto; font: 12px/1.2 ui-sans-serif, system-ui, -apple-system; opacity: 0.85; }
  .editorHost { flex: 1; overflow: auto; padding: 16px; }
  .editorRoot { max-width: 1200px; margin: 0 auto; border: 1px solid rgba(255,255,255,0.08); border-radius: 10px; overflow: hidden; }
  .hint {
    padding: 10px 12px; border-top: 1px solid rgba(255,255,255,0.08);
    font: 12px/1.2 ui-sans-serif, system-ui, -apple-system; opacity: 0.75;
  }
  .cm-editor { height: calc(100vh - 44px - 44px - 32px); } /* header + hint + padding */
  .cm-scroller { font: 13px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; }
`;
document.head.append(style);
