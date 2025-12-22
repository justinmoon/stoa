# Zed `editor::Editor` Standalone (macOS) — “`z <file>`”

Goal: get Zed’s Rust `editor::Editor` widget running as a tiny standalone macOS GUI app that can open/edit/save a single file. No Stoa integration yet.

## Why this approach

Zed’s `editor::Editor` is built on Zed’s `gpui` runtime and expects Zed’s workspace-style dependency graph (`*.workspace = true`). The straightest path is to create a small binary **inside the `~/code/zed` Cargo workspace**, so all workspace dependencies resolve without manually recreating Zed’s dependency graph.

## Prereqs

- Xcode + command line tools (Metal requirements for `gpui`): see `~/code/zed/crates/gpui/README.md`
- Recent stable Rust toolchain compatible with your `~/code/zed` checkout

## Step 1 — Create a new workspace binary crate

```bash
cd ~/code/zed
cargo new crates/z --bin
```

Add `crates/z` to the `members = [...]` array in `~/code/zed/Cargo.toml`.

If you already have a `z` shell command (e.g. zoxide), use a different crate folder and set the binary name to `z` (next step).

## Step 2 — Minimal `Cargo.toml`

Edit `~/code/zed/crates/z/Cargo.toml`:

```toml
[package]
name = "z"
version = "0.1.0"
edition.workspace = true
publish = false

[[bin]]
name = "z"
path = "src/main.rs"

[dependencies]
gpui.workspace = true
editor.workspace = true
language.workspace = true
multi_buffer.workspace = true
settings.workspace = true
theme.workspace = true
```

Notes:
- This intentionally pulls only what’s needed to create an editor over a `language::Buffer`.
- Vim mode and full language registry can be layered on later.

## Step 3 — Minimal `main.rs`

Replace `~/code/zed/crates/z/src/main.rs` with:

```rust
use std::path::{Path, PathBuf};

use gpui::{
    actions, px, size, App, Application, Bounds, Context, Focusable as _, KeyBinding, Window,
    WindowBounds, WindowOptions, div, prelude::*,
};

actions!(z, [SaveFile, CloseWindow]);

struct ZWindow {
    path: PathBuf,
    buffer: gpui::Entity<language::Buffer>,
    editor: gpui::Entity<editor::Editor>,
}

impl Render for ZWindow {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        div()
            .size_full()
            .child(self.editor.clone())
            .on_action({
                let path = self.path.clone();
                let buffer = self.buffer.clone();
                move |_: &SaveFile, _window, cx| {
                    let text = buffer.read(cx).text_snapshot().as_rope().to_string();
                    if let Err(err) = std::fs::write(&path, text) {
                        eprintln!("save failed ({}): {err}", path.display());
                    } else {
                        eprintln!("saved {}", path.display());
                    }
                }
            })
            .on_action(|_: &CloseWindow, window, _| window.remove_window())
    }
}

fn read_file_or_empty(path: &Path) -> String {
    std::fs::read_to_string(path).unwrap_or_default()
}

fn main() {
    let path = std::env::args().nth(1).map(PathBuf::from).unwrap_or_else(|| {
        eprintln!("usage: z <file>");
        std::process::exit(2);
    });

    let initial_text = read_file_or_empty(&path);

    Application::new().run(move |cx: &mut App| {
        settings::init(cx);
        theme::init(theme::LoadThemes::JustBase, cx);

        cx.bind_keys([
            KeyBinding::new("cmd-s", SaveFile, None),
            KeyBinding::new("cmd-w", CloseWindow, None),
        ]);
        cx.on_window_closed(|cx| {
            if cx.windows().is_empty() {
                cx.quit();
            }
        })
        .detach();

        let bounds = Bounds::centered(None, size(px(1200.), px(800.)), cx);
        cx.open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                ..Default::default()
            },
            move |window, cx| {
                let buffer = cx.new(|cx| language::Buffer::local(initial_text, cx));
                let multi_buffer = cx.new(|cx| multi_buffer::MultiBuffer::singleton(buffer.clone(), cx));

                let editor = cx.new(|cx| editor::Editor::new(editor::EditorMode::full(), multi_buffer, None, window, cx));
                window.focus(&editor.focus_handle(cx), cx);

                cx.new(|_| ZWindow { path, buffer, editor })
            },
        )
        .unwrap();

        cx.activate(true);
    });
}
```

What this gives you:
- `z <file>` opens a window with Zed’s editor widget editing that file’s contents.
- `Cmd+S` writes the current buffer text back to the file path.
- `Cmd+W` closes the window; app quits when the last window closes.

## Step 4 — Run it

From `~/code/zed`:

```bash
cargo run -p z -- /tmp/test.rs
```

First build will be heavy; subsequent builds are incremental.

## Step 5 — Make `z` available on your PATH

```bash
cd ~/code/zed
cargo build -p z --release
ln -sf ~/code/zed/target/release/z ~/bin/z
```

## Next experiments (still standalone)

- **Window title:** set `WindowOptions.titlebar` to show the filename.
- **Syntax highlighting:** initialize a language registry and set the buffer language based on file extension.
- **Vim mode:** wire `vim` + keymaps/settings once the basic editor loop is stable.

