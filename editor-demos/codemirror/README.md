# CodeMirror “`cm <file>`” Demo (Standalone)

Goal: a tiny, standalone CodeMirror 6 app for exploring “coding editor” capabilities. It opens a file, lets you edit, and saves back to the same file on `Cmd+S`.

This demo does **not** interact with Stoa.

## What it is

- A local dev server (Node + Vite) that serves a CodeMirror editor UI.
- A tiny `/api/*` endpoint that loads and saves a single file on disk.
- A CLI wrapper (`./cm <file>`) that starts the server and opens your browser.

## Setup

```bash
cd /Users/justin/code/stoa/editor-demos/codemirror
npm install
```

## Run

```bash
./cm /tmp/demo.rs
```

- Save with `Cmd+S`.
- Quit the server with `Ctrl+C` in the terminal.

## Notes / Next steps

- This is “local file edit”, not a full project/workspace yet.
- LSP is not wired up here yet. Once we like CodeMirror’s ergonomics, we can add:
  - a minimal LSP client (stdio) and bridge completions/diagnostics/hover into CM,
  - or reuse an existing CM6 LSP adapter if we choose one.

