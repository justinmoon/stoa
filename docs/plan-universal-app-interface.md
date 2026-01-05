# Plan: Universal App Interface + Embedded Editor

## Goal

Create a universal interface for "apps" that can run in stoa panes, then use it to embed Zed's editor as a native pane alongside Ghostty terminals and webviews.

## Key Constraints

1. **Fast iteration** - Must be able to run/test the editor standalone without full stoa rebuild
2. **Maintainable GPUI changes** - Minimize merge conflicts as upstream GPUI evolves
3. **No LSP yet** - Start with basic editor (text, syntax highlighting, vim mode)

## Reference Repos

Coding agents should grep through these for patterns and examples:

- `~/code/zed` - GPUI, Editor, vim mode, all the Rust code
- `~/code/stoa` - The Swift host app, Ghostty integration patterns
- `~/code/monaco-editor` - Monaco architecture (for comparison)
- `~/code/codemirror` - CodeMirror architecture (for comparison)

---

## What IS a "Stoa App"?

A stoa app is a **static library with C ABI**, just like Ghostty today:

```
┌─────────────────────────────────────────────────────────────┐
│ What Ghostty is today:                                       │
│                                                              │
│   libghostty.a    +    ghostty.h    =    Stoa App           │
│   (static lib)         (C header)                            │
│                                                              │
│   Swift calls:  ghostty_app_new()                           │
│                 ghostty_surface_new()                        │
│                 ghostty_surface_key()                        │
│                 ghostty_surface_free()                       │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ What the editor will be:                                     │
│                                                              │
│   libstoa_editor.a  +  stoa_editor.h  =    Stoa App         │
│   (static lib)          (C header)                           │
│                                                              │
│   Swift calls:  stoa_editor_new()                           │
│                 stoa_editor_load_file()                      │
│                 stoa_editor_key()                            │
│                 stoa_editor_free()                           │
└─────────────────────────────────────────────────────────────┘
```

The **StoaApp Swift protocol** is just sugar to make these uniform on the Swift side:

```swift
protocol StoaApp {
    var view: NSView { get }
    func focus()
    func destroy()
    // ...
}

class TerminalApp: StoaApp { /* wraps libghostty.a */ }
class EditorApp: StoaApp   { /* wraps libstoa_editor.a */ }
class WebViewApp: StoaApp  { /* wraps WKWebView, no FFI */ }
```

**WebView is the odd one out** - it's not a static lib, it's just Apple's WKWebView. But it conforms to the same Swift protocol so pane management is uniform.

---

## Fast Iteration Strategy

The key insight: **the editor can be a separate process**, not linked into Stoa.

```
┌─────────────────────────────────────────────────────────────┐
│  Stoa (your dev environment - dogfood it!)                  │
│  ┌─────────────────────┬───────────────────────────────────┐│
│  │ Terminal pane       │ Editor pane (placeholder NSView)  ││
│  │                     │                                   ││
│  │ $ cargo watch -x    │     ┌───────────────────────┐     ││
│  │   'run --example    │     │ GPUI window           │     ││
│  │    standalone'      │     │ (SEPARATE PROCESS)    │     ││
│  │                     │     │                       │     ││
│  │ [rebuilds on save]  │     │ Stoa positions this   │     ││
│  │                     │     │ over the placeholder  │     ││
│  │                     │     └───────────────────────┘     ││
│  └─────────────────────┴───────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### Why Subprocess First?

| Approach | Rebuild cycle | Complexity |
|----------|---------------|------------|
| Static lib in Stoa | ~30-60 sec (Rust + Swift) | High |
| Subprocess | ~5-10 sec (Rust only) | Low |

### Iteration Workflow

```bash
# Terminal 1 (in Stoa): Watch and rebuild
cd ~/code/stoa-gpui
cargo watch -x 'run --example standalone -- /tmp/test.rs'

# Terminal 2 (in Stoa): Edit the editor code
vim src/editor_app.rs
# Save → cargo watch rebuilds → new editor window appears

# EVEN FASTER: Editor edits itself
cargo run --example standalone -- src/editor_app.rs
# Save, Ctrl-C, up-arrow, enter → 5 second loop
```

### Integration Phases

1. **Phase A: Standalone binary** - Just get the editor running in its own window
2. **Phase B: Subprocess mode** - Stoa spawns editor, positions its window
3. **Phase C (optional): Static lib** - Link into Stoa for tighter integration

We may never need Phase C. Subprocess mode might be good enough forever.

---

## The NSApplication Problem (Critical)

GPUI assumes it owns the macOS app:
- Creates `GPUIApplication` subclass
- Sets itself as app delegate
- Calls `NSApplication.run()` (takes over the main loop)

**This conflicts with Stoa**, which already owns NSApp.

### Solution: GPUI Embedded Runtime Mode

Add a GPUI entry path that:
- Does NOT call `NSApplication.run()`
- Does NOT set itself as app delegate
- Does NOT require GPUIApplication principal class
- Still initializes enough runtime to create windows, render, handle input

```rust
// Current GPUI (takes over the app)
gpui::App::new().run(|cx| { ... });

// New embedded mode (attaches to existing app)
gpui::App::new().run_embedded(|cx| { ... });
// Returns immediately, doesn't block on NSApp.run()
```

### What "Embedded" Means in Practice

For the subprocess approach, we don't even need true embedding initially:
1. Editor subprocess creates its own GPUI window (borderless, no titlebar)
2. Stoa tells editor (via IPC) where to position itself
3. Editor moves its window to overlay Stoa's pane area
4. Focus: Stoa tells editor when to activate/deactivate

This gives us a working editor pane with minimal GPUI surgery.

### GPUI Changes Required (Small!)

Files to modify in `~/code/zed/crates/gpui/src/platform/mac/`:

| File | Change |
|------|--------|
| `platform.rs` | Add `run_embedded()` that skips `NSApp.run()` |
| `app.rs` | Make app delegate optional in embedded mode |
| `window.rs` | Allow borderless/undecorated windows |

Everything else (Editor, Buffer, vim, rendering) works unchanged.

---

## Phase 1: Define Universal App Interface

### 1.1 Create the Swift Protocol

**File: `Sources/StoaKit/StoaApp.swift`**

```swift
import AppKit

/// Configuration passed when creating an app
public struct StoaAppConfig {
    public let id: UUID
    public let initialSize: NSSize
    public let scaleFactor: CGFloat
    public let initialData: [String: Any]?

    public init(id: UUID = UUID(),
                initialSize: NSSize = NSSize(width: 800, height: 600),
                scaleFactor: CGFloat = 2.0,
                initialData: [String: Any]? = nil) {
        self.id = id
        self.initialSize = initialSize
        self.scaleFactor = scaleFactor
        self.initialData = initialData
    }
}

/// Events from apps to Stoa
public enum StoaAppEvent {
    case requestClose
    case requestSplit(horizontal: Bool)
    case titleChanged(String)
    case bell
    case custom(name: String, data: Data?)
}

/// A Stoa app is anything that can render into a pane
public protocol StoaApp: AnyObject {
    /// Unique type identifier
    static var appType: String { get }

    /// The NSView to embed in the pane
    var view: NSView { get }

    /// Callback for events the app wants Stoa to handle
    var onEvent: ((StoaAppEvent) -> Void)? { get set }

    /// Callback for key events Stoa might intercept
    /// Return true if Stoa handled it, false to let app handle
    var shouldInterceptKey: ((NSEvent) -> Bool)? { get set }

    /// Focus management
    func focus()
    func blur()

    /// Cleanup
    func destroy()
}
```

### 1.2 Create C FFI Header for Native Apps

**File: `Sources/Stoa/stoa_app.h`**

```c
#ifndef STOA_APP_H
#define STOA_APP_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque app handle
typedef struct stoa_app stoa_app_t;

// Configuration
typedef struct {
    double width;
    double height;
    double scale_factor;
    void* userdata;

    // Callbacks
    void (*on_event)(void* userdata, const char* event_type, const char* event_data);
    void (*on_wakeup)(void* userdata);
    void (*write_clipboard)(void* userdata, const char* text, size_t len);
    void (*read_clipboard)(void* userdata, char* buffer, size_t* len);
} stoa_app_config_t;

// Input types (matching Ghostty's pattern)
typedef enum {
    STOA_KEY_PRESS,
    STOA_KEY_RELEASE,
    STOA_KEY_REPEAT
} stoa_key_action_t;

typedef enum {
    STOA_MOD_SHIFT = 1 << 0,
    STOA_MOD_CTRL  = 1 << 1,
    STOA_MOD_ALT   = 1 << 2,
    STOA_MOD_SUPER = 1 << 3,
    STOA_MOD_CAPS  = 1 << 4,
} stoa_mods_t;

typedef struct {
    stoa_key_action_t action;
    uint32_t mods;
    uint32_t keycode;
    const char* text;  // UTF-8 text input
} stoa_key_event_t;

typedef enum {
    STOA_MOUSE_LEFT,
    STOA_MOUSE_RIGHT,
    STOA_MOUSE_MIDDLE,
} stoa_mouse_button_t;

typedef enum {
    STOA_MOUSE_PRESS,
    STOA_MOUSE_RELEASE,
} stoa_mouse_action_t;

// Lifecycle
stoa_app_t* stoa_app_new(stoa_app_config_t* config);
void stoa_app_free(stoa_app_t* app);

// Get the native view (NSView* on macOS)
void* stoa_app_get_view(stoa_app_t* app);

// Focus
void stoa_app_set_focus(stoa_app_t* app, bool focused);

// Size
void stoa_app_set_size(stoa_app_t* app, uint32_t width, uint32_t height);
void stoa_app_set_scale(stoa_app_t* app, double scale_x, double scale_y);

// Input
bool stoa_app_key(stoa_app_t* app, stoa_key_event_t event);
void stoa_app_mouse_button(stoa_app_t* app, stoa_mouse_action_t action,
                           stoa_mouse_button_t button, uint32_t mods);
void stoa_app_mouse_pos(stoa_app_t* app, double x, double y, uint32_t mods);
void stoa_app_mouse_scroll(stoa_app_t* app, double dx, double dy, uint32_t mods);

// Tick (for apps that need regular updates)
void stoa_app_tick(stoa_app_t* app);

#ifdef __cplusplus
}
#endif

#endif // STOA_APP_H
```

### 1.3 Create Generic Native App Wrapper

**File: `Sources/Stoa/NativeAppView.swift`**

A generic Swift wrapper that works with any C FFI conforming to `stoa_app.h`:

```swift
import AppKit

/// Base class for native apps using C FFI
class NativeAppView: NSView, StoaApp {
    // Subclasses override
    class var appType: String { "native" }

    var onEvent: ((StoaAppEvent) -> Void)?
    var shouldInterceptKey: ((NSEvent) -> Bool)?

    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        if let area = trackingArea { removeTrackingArea(area) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .inVisibleRect, .activeInKeyWindow],
            owner: self
        )
        addTrackingArea(trackingArea!)
        super.updateTrackingAreas()
    }

    // MARK: - StoaApp Protocol

    var view: NSView { self }

    func focus() {
        window?.makeFirstResponder(self)
        didFocus()
    }

    func blur() {
        didBlur()
    }

    func destroy() {
        // Override in subclass
    }

    // MARK: - Subclass Hooks

    func didFocus() {}
    func didBlur() {}
    func didResize(to size: NSSize) {}
    func handleKey(_ event: NSEvent, action: stoa_key_action_t) -> Bool { false }
    func handleMouseButton(_ event: NSEvent, action: stoa_mouse_action_t, button: stoa_mouse_button_t) {}
    func handleMouseMove(_ event: NSEvent) {}
    func handleScroll(_ event: NSEvent) {}

    // MARK: - Event Handling

    override func keyDown(with event: NSEvent) {
        if let intercept = shouldInterceptKey, intercept(event) { return }
        if !handleKey(event, action: STOA_KEY_PRESS) {
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        _ = handleKey(event, action: STOA_KEY_RELEASE)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        handleMouseButton(event, action: STOA_MOUSE_PRESS, button: STOA_MOUSE_LEFT)
    }

    override func mouseUp(with event: NSEvent) {
        handleMouseButton(event, action: STOA_MOUSE_RELEASE, button: STOA_MOUSE_LEFT)
    }

    override func mouseMoved(with event: NSEvent) {
        handleMouseMove(event)
    }

    override func mouseDragged(with event: NSEvent) {
        handleMouseMove(event)
    }

    override func scrollWheel(with event: NSEvent) {
        handleScroll(event)
    }

    override func layout() {
        super.layout()
        didResize(to: bounds.size)
    }
}
```

---

## Phase 2: Migrate Ghostty to Universal Interface

### 2.1 Refactor TerminalSurfaceView

Modify `TerminalSurfaceView` to conform to `StoaApp` protocol. The existing Ghostty integration already follows a similar pattern, so this is mostly renaming/restructuring.

**Changes to `TerminalSurfaceView.swift`:**

1. Make it extend `NativeAppView` or directly conform to `StoaApp`
2. Map Ghostty's callbacks to `StoaAppEvent`
3. Keep existing `ghostty_*` FFI calls

### 2.2 Create Terminal App Factory

```swift
class TerminalApp: NativeAppView {
    static override var appType: String { "terminal" }

    private var surface: ghostty_surface_t?
    private let ghosttyApp: GhosttyApp

    init(ghosttyApp: GhosttyApp, config: StoaAppConfig) {
        self.ghosttyApp = ghosttyApp
        super.init(frame: NSRect(origin: .zero, size: config.initialSize))
        setupSurface(config)
    }

    // ... existing Ghostty integration code ...
}
```

### 2.3 Update Pane to Use Protocol

```swift
enum PaneContent: Codable, Equatable {
    case terminal
    case webview(url: URL)
    case editor(path: String?)  // NEW
}

class Pane {
    var app: StoaApp?  // The actual app instance

    func createApp(ghosttyApp: GhosttyApp?, config: StoaAppConfig) -> StoaApp {
        switch content {
        case .terminal:
            return TerminalApp(ghosttyApp: ghosttyApp!, config: config)
        case .webview(let url):
            return WebViewApp(url: url, config: config)
        case .editor(let path):
            return EditorApp(path: path, config: config)
        }
    }
}
```

---

## Phase 3: GPUI Embedding Layer (Minimal Invasive)

### 3.1 Strategy: Wrapper Crate, Not Fork

Create a new crate that wraps GPUI rather than modifying it. This minimizes merge conflicts.

```
~/code/stoa-gpui/
├── Cargo.toml
├── src/
│   ├── lib.rs           # Main exports
│   ├── embedded.rs      # Embedded app infrastructure
│   ├── surface.rs       # Surface abstraction
│   └── ffi.rs           # C FFI exports
└── examples/
    └── standalone.rs    # For fast iteration testing
```

**Cargo.toml:**

```toml
[package]
name = "stoa-gpui"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["staticlib", "cdylib", "rlib"]

[dependencies]
gpui = { path = "../zed/crates/gpui" }
editor = { path = "../zed/crates/editor" }
language = { path = "../zed/crates/language" }
text = { path = "../zed/crates/text" }
multi_buffer = { path = "../zed/crates/multi_buffer" }
theme = { path = "../zed/crates/theme" }
settings = { path = "../zed/crates/settings" }
vim = { path = "../zed/crates/vim", optional = true }

# Platform
metal = "0.29"
objc = "0.2"
cocoa = "0.26"
core-graphics = "0.24"

[features]
default = ["vim"]
vim = ["dep:vim"]

[build-dependencies]
cbindgen = "0.26"
```

### 3.2 The Key Insight: GPUI Window Proxy

Instead of modifying GPUI's window creation, we create a **proxy window** that:
1. Creates a real GPUI window (hidden or offscreen)
2. Captures its Metal layer
3. Composites that layer into the Stoa-provided NSView

OR (simpler): Use GPUI's panel/popover support which already allows non-main windows.

**Check if GPUI has headless/offscreen support:**

Look at `~/code/zed/crates/gpui/src/platform/mac/` for:
- Panel creation
- Window without decorations
- Offscreen rendering

### 3.3 Embedded Surface Implementation

**File: `stoa-gpui/src/surface.rs`**

```rust
use gpui::*;
use std::sync::Arc;

/// An embedded GPUI surface that can be hosted in an external NSView
pub struct EmbeddedSurface {
    app: App,
    window: Option<AnyWindowHandle>,
    metal_layer: *mut objc::runtime::Object,  // CAMetalLayer
}

impl EmbeddedSurface {
    /// Create a new embedded surface
    ///
    /// The surface creates its own GPUI context and window,
    /// but exposes the Metal layer for external compositing.
    pub fn new(width: u32, height: u32, scale: f64) -> Self {
        // Initialize GPUI
        let app = App::new();

        // Create a borderless, transparent window
        let window = app.run(|cx| {
            let options = WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(Bounds {
                    origin: point(px(0.), px(0.)),
                    size: size(px(width as f32), px(height as f32)),
                })),
                titlebar: None,
                window_background: WindowBackground::Transparent,
                // Key: we want to control this window externally
                ..Default::default()
            };

            cx.open_window(options, |_, cx| {
                cx.new(|_| EmptyView)
            })
        });

        Self {
            app,
            window: Some(window),
            metal_layer: std::ptr::null_mut(), // Get from window
        }
    }

    /// Get the CAMetalLayer for external compositing
    pub fn metal_layer(&self) -> *mut objc::runtime::Object {
        self.metal_layer
    }

    /// Set the root view
    pub fn set_root<V: Render + 'static>(&mut self, view: Entity<V>) {
        // Replace window content with the view
    }
}

struct EmptyView;
impl Render for EmptyView {
    fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
        div()
    }
}
```

### 3.4 Alternative: Child Window Approach

If layer sharing is complex, use a simpler approach:

1. GPUI creates a real NSWindow (borderless, no titlebar)
2. Swift positions this window to exactly overlay the pane area
3. Swift handles focus forwarding

This is how some DAWs embed plugin windows.

```swift
class GPUIWindowProxy: StoaApp {
    private var gpuiWindow: NSWindow?  // The actual GPUI window
    private var parentView: NSView?

    func attachTo(view: NSView) {
        parentView = view
        // Position GPUI window to match view's screen coordinates
        updatePosition()

        // Observe parent view changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(parentMoved),
            name: NSView.frameDidChangeNotification,
            object: view
        )
    }

    @objc func parentMoved() {
        updatePosition()
    }

    private func updatePosition() {
        guard let view = parentView,
              let parentWindow = view.window else { return }

        let frameInWindow = view.convert(view.bounds, to: nil)
        let frameOnScreen = parentWindow.convertToScreen(frameInWindow)
        gpuiWindow?.setFrame(frameOnScreen, display: true)
    }
}
```

---

## Phase 4: Minimal Editor Implementation

### 4.1 Create Editor App

**File: `stoa-gpui/src/editor_app.rs`**

```rust
use gpui::*;
use editor::{Editor, EditorMode};
use language::Buffer;
use multi_buffer::MultiBuffer;

/// A minimal editor app for Stoa
pub struct EditorApp {
    editor: Entity<Editor>,
}

impl EditorApp {
    pub fn new(cx: &mut App) -> Entity<Self> {
        cx.new(|cx| {
            // Create empty buffer
            let buffer = cx.new(|cx| Buffer::local("", cx));
            let multi_buffer = cx.new(|cx| MultiBuffer::singleton(buffer, cx));

            // Create editor (no project = no LSP, which is fine for now)
            let editor = cx.new(|cx| {
                Editor::new(EditorMode::full(), multi_buffer, None, cx)
            });

            Self { editor }
        })
    }

    pub fn load_file(&mut self, path: &str, cx: &mut Context<Self>) {
        let content = std::fs::read_to_string(path).unwrap_or_default();
        self.editor.update(cx, |editor, cx| {
            editor.buffer().update(cx, |buffer, cx| {
                buffer.as_singleton().unwrap().update(cx, |buf, cx| {
                    buf.set_text(&content, cx);
                });
            });
        });
    }
}

impl Render for EditorApp {
    fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
        div()
            .size_full()
            .child(self.editor.clone())
    }
}
```

### 4.2 C FFI Exports

**File: `stoa-gpui/src/ffi.rs`**

```rust
use std::ffi::{c_char, c_void, CStr};
use std::ptr;

use crate::EditorApp;

#[repr(C)]
pub struct stoa_app_config {
    pub width: f64,
    pub height: f64,
    pub scale_factor: f64,
    pub userdata: *mut c_void,

    pub on_event: Option<extern "C" fn(*mut c_void, *const c_char, *const c_char)>,
    pub on_wakeup: Option<extern "C" fn(*mut c_void)>,
}

pub struct StoaEditorApp {
    // GPUI context and editor
    surface: EmbeddedSurface,
    editor: Entity<EditorApp>,
}

#[no_mangle]
pub extern "C" fn stoa_editor_new(config: *mut stoa_app_config) -> *mut StoaEditorApp {
    let config = unsafe { &*config };

    // Create embedded GPUI surface
    let mut surface = EmbeddedSurface::new(
        config.width as u32,
        config.height as u32,
        config.scale_factor,
    );

    // Create editor
    let editor = surface.run(|cx| EditorApp::new(cx));
    surface.set_root(editor.clone());

    Box::into_raw(Box::new(StoaEditorApp { surface, editor }))
}

#[no_mangle]
pub extern "C" fn stoa_editor_free(app: *mut StoaEditorApp) {
    if !app.is_null() {
        unsafe { drop(Box::from_raw(app)) };
    }
}

#[no_mangle]
pub extern "C" fn stoa_editor_get_view(app: *mut StoaEditorApp) -> *mut c_void {
    // Return NSView* or CAMetalLayer*
    unsafe { (*app).surface.metal_layer() as *mut c_void }
}

#[no_mangle]
pub extern "C" fn stoa_editor_set_size(app: *mut StoaEditorApp, width: u32, height: u32) {
    unsafe { (*app).surface.set_size(width, height) };
}

#[no_mangle]
pub extern "C" fn stoa_editor_load_file(app: *mut StoaEditorApp, path: *const c_char) {
    let path = unsafe { CStr::from_ptr(path).to_str().unwrap() };
    unsafe {
        (*app).surface.run(|cx| {
            (*app).editor.update(cx, |editor, cx| {
                editor.load_file(path, cx);
            });
        });
    }
}

// Key input
#[no_mangle]
pub extern "C" fn stoa_editor_key(
    app: *mut StoaEditorApp,
    action: u32,    // 0=press, 1=release
    mods: u32,
    keycode: u32,
    text: *const c_char,
) -> bool {
    // Forward to GPUI input system
    false
}

// ... more FFI functions for mouse, scroll, focus ...
```

### 4.3 Generate C Header

**File: `stoa-gpui/build.rs`**

```rust
use std::env;
use std::path::PathBuf;

fn main() {
    let crate_dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    let out_path = PathBuf::from(&crate_dir).join("include");

    cbindgen::Builder::new()
        .with_crate(&crate_dir)
        .with_language(cbindgen::Language::C)
        .generate()
        .expect("Unable to generate bindings")
        .write_to_file(out_path.join("stoa_editor.h"));
}
```

---

## Phase 5: Fast Iteration Setup

### 5.1 Standalone Test Binary

**File: `stoa-gpui/examples/standalone.rs`**

```rust
//! Standalone editor for fast iteration
//!
//! Run with: cargo run --example standalone -- [file]
//!
//! This creates a minimal window with just the editor,
//! bypassing Swift/Stoa entirely for quick testing.

use gpui::*;
use stoa_gpui::EditorApp;

fn main() {
    let file = std::env::args().nth(1);

    App::new().run(|cx| {
        // Initialize vim mode if available
        #[cfg(feature = "vim")]
        vim::init(cx);

        // Initialize editor settings
        editor::init(cx);

        cx.open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(Bounds {
                    origin: point(px(100.), px(100.)),
                    size: size(px(1200.), px(800.)),
                })),
                ..Default::default()
            },
            |window, cx| {
                let editor = EditorApp::new(cx);

                if let Some(path) = file {
                    editor.update(cx, |e, cx| e.load_file(&path, cx));
                }

                editor
            },
        );
    });
}
```

### 5.2 Development Justfile

**File: `stoa-gpui/justfile`**

```makefile
# Quick iteration commands

# Run standalone editor with a file
edit file="":
    cargo run --example standalone --release -- {{file}}

# Run standalone editor with test file
test-edit:
    echo "fn main() {\n    println!(\"Hello\");\n}" > /tmp/test.rs
    cargo run --example standalone --release -- /tmp/test.rs

# Build the static library for Swift
build-lib:
    cargo build --release
    cp target/release/libstoa_gpui.a ../stoa/Libraries/

# Watch and rebuild
watch:
    cargo watch -x "build --example standalone"

# Check compilation only (fastest)
check:
    cargo check --example standalone

# Run with debug logging
debug file="":
    RUST_LOG=debug cargo run --example standalone -- {{file}}
```

### 5.3 Iteration Workflow

```bash
# Terminal 1: Watch for changes
cd ~/code/stoa-gpui
just watch

# Terminal 2: Quick test
cd ~/code/stoa-gpui
just edit ~/code/stoa/Sources/Stoa/main.swift

# For fastest iteration during development:
just check  # ~2-3 seconds
just edit   # ~5-10 seconds full build+run
```

---

## Phase 6: Integration Testing

### 6.1 Swift Integration Test App

Create a minimal Swift app just for testing the embedded editor:

**File: `stoa-gpui/test-app/`**

A simple Swift app that:
1. Links against `libstoa_gpui.a`
2. Creates a window
3. Embeds the editor
4. Forwards events

This allows testing the Swift<->Rust integration without full Stoa.

### 6.2 Integration Test Script

```bash
#!/bin/bash
# test-integration.sh

cd ~/code/stoa-gpui
cargo build --release

cd test-app
swift build
.build/debug/TestApp
```

---

## Dependency Management

### Zed Crates to Use

From `~/code/zed/crates/`:

| Crate | Purpose | Notes |
|-------|---------|-------|
| `gpui` | UI framework | Core dependency |
| `editor` | Editor component | Main goal |
| `text` | Text rope | Required by editor |
| `multi_buffer` | Buffer abstraction | Required by editor |
| `language` | Syntax highlighting | For tree-sitter |
| `theme` | Theming | For colors |
| `settings` | Configuration | For editor settings |
| `vim` | Vim mode | Optional but wanted |

### NOT Needed (for now)

| Crate | Why Skip |
|-------|----------|
| `project` | LSP, file watchers - skip for v1 |
| `workspace` | Zed's pane/tab management |
| `lsp` | Language servers |
| `copilot` | AI features |
| `collab` | Collaboration |

### Handling GPUI Updates

Strategy: **Git subtree or patch-based approach**

1. Don't fork GPUI
2. Create `stoa-gpui` as a wrapper crate
3. If GPUI changes needed, create minimal patches
4. Periodically rebase patches on new GPUI versions

```bash
# Update to new Zed/GPUI version
cd ~/code/zed
git pull

# Rebuild stoa-gpui (should work if API compatible)
cd ~/code/stoa-gpui
cargo build

# If API broke, check what changed
cd ~/code/zed
git diff OLD_VERSION..NEW_VERSION -- crates/gpui/src/
```

---

## Open Questions

### Q1: Window Embedding Strategy?

Options:
- **A) Layer sharing** - GPUI renders to CAMetalLayer, Swift composites
- **B) Child window** - GPUI creates real window, Swift positions it
- **C) Offscreen render** - GPUI renders to texture, Swift draws texture

Recommendation: Start with **B (child window)** as it's simplest, then optimize to A if needed.

### Q2: Input Handling?

Options:
- **A) Swift intercepts all** - Swift captures events, forwards via FFI
- **B) GPUI handles own** - GPUI window gets events directly (child window approach)
- **C) Hybrid** - GPUI handles most, Swift intercepts for global keybindings

Recommendation: **C (hybrid)** - match how Ghostty works.

### Q3: Vim Mode Integration?

The `vim` crate hooks into editors via `cx.observe_new()`. Need to ensure this works in embedded context.

Test: Does `vim::init(cx)` work when Editor is created in embedded surface?

---

## Implementation Order (Revised)

### Phase 1: stoa-app-protocol (2 days)
- [ ] Define `StoaApp` Swift protocol
- [ ] Define `stoa_app.h` C header
- [ ] Refactor Ghostty wrapper to use protocol
- [ ] Refactor WebView wrapper to use protocol
- [ ] **Success:** Stoa works exactly as before, cleaner code

### Phase 2: stoa-gpui-editor (5-7 days)
- [ ] Create `~/code/stoa-gpui` crate
- [ ] Get basic GPUI window running (standalone)
- [ ] Add Zed's Editor + Buffer dependencies
- [ ] Get text editing working
- [ ] Get syntax highlighting working
- [ ] Get vim mode working
- [ ] Standalone test harness (`just edit file.rs`)
- [ ] **Success:** Can edit files with vim bindings, no Swift needed

### Phase 3: stoa-editor-integration (3-4 days)
- [ ] Add IPC for Stoa ↔ Editor communication (position, focus)
- [ ] Stoa spawns editor subprocess
- [ ] Stoa positions editor window over pane placeholder
- [ ] Focus forwarding works
- [ ] **Success:** Editor pane in Stoa, can switch focus between terminal/editor

### Optional Future: Static Library Mode
- [ ] Add GPUI `run_embedded()` for in-process hosting
- [ ] C FFI layer
- [ ] Link as static lib instead of subprocess
- [ ] **Maybe never needed** - subprocess might be good enough

**Total: ~10-13 days**

---

## Phase Summary

```
┌─────────────────────────────────────────────────────────────┐
│ Phase 1: stoa-app-protocol                                  │
│   Pure Swift refactoring. Proves interface design.          │
│   No new functionality, just cleaner abstractions.          │
│   ~2 days                                                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Phase 2: stoa-gpui-editor                                   │
│   Pure Rust. Standalone editor binary.                      │
│   Fastest iteration: cargo run, no Swift rebuilds.          │
│   This is where most dev time goes.                         │
│   ~5-7 days                                                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Phase 3: stoa-editor-integration                            │
│   Subprocess + window positioning.                          │
│   IPC between Swift and Rust.                               │
│   ~3-4 days                                                  │
└─────────────────────────────────────────────────────────────┘
```

---

## Success Criteria

### Phase 1 Done When:
- [ ] Stoa compiles and runs
- [ ] Ghostty terminals work exactly as before
- [ ] WebViews work exactly as before
- [ ] Code is cleaner (protocol-based)

### Phase 2 Done When:
- [ ] `cargo run --example standalone -- somefile.rs` opens editor
- [ ] Can type, move cursor, delete text
- [ ] Vim bindings work (hjkl, i, esc, :w, etc.)
- [ ] Syntax highlighting works for .rs, .swift, .ts files
- [ ] Can save files
- [ ] ~5 second iteration loop when editing the editor itself

### Phase 3 Done When:
- [ ] `Cmd+Shift+E` (or whatever) opens editor pane in Stoa
- [ ] Editor pane visually aligned with Stoa pane boundaries
- [ ] Can focus terminal, then focus editor, then focus terminal
- [ ] Editor follows pane when Stoa window moves/resizes
- [ ] Can have multiple editor panes (split)

### Non-Goals (for now):
- LSP / go-to-definition
- File tree
- Tabs
- Project-wide search
- Git integration

These come later. First, just get a working editor pane.
