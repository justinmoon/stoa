# Stoa MVP Spec

A tiling window manager for AI-driven software development on macOS.

## Vision

A full-screen desktop app that provides an i3-like tiling experience for coding, without requiring Linux or being limited to terminal-only workflows. Panes can be terminals or webviews, enabling workflows like: terminal + GitHub PR review + browser dev tools, all tiled.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    StoaWindowController                      │
│                   (NSWindowController)                       │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  @Published var paneTree: SplitTree<Pane>             │  │
│  │  var focusedPane: Pane?                               │  │
│  │  func focusPane(_:) → makeFirstResponder              │  │
│  └───────────────────────────────────────────────────────┘  │
│                            │                                 │
│                   NSHostingView(ContentView)                 │
│                            │                                 │
│            ┌───────────────┴───────────────┐                │
│            ▼                               ▼                │
│     ┌─────────────┐                 ┌─────────────┐         │
│     │ Terminal    │                 │ WebView     │         │
│     │ (NSView)    │                 │ (NSView)    │         │
│     │ libghostty  │                 │ WKWebView   │         │
│     └─────────────┘                 └─────────────┘         │
└─────────────────────────────────────────────────────────────┘
```

### Key Decisions

1. **NSWindowController + SwiftUI** - Following Ghostty's approach: an `NSWindowController` owns the window and manages focus/first responder routing, while SwiftUI handles layout and rendering via `NSHostingView`. This makes programmatic focus control between NSViews (terminal vs webview) straightforward.

2. **Split tree holds models, not views** - `SplitTree<Pane>` where `Pane` is a reference type (class) holding the actual NSView. SwiftUI views are rendered *from* this data, not stored in it.

3. **libghostty for terminals** - Build Ghostty's Zig library as a static library, link it into the Xcode project, and write a Swift wrapper. Don't reinvent VT parsing or GPU text rendering.

4. **Native WKWebView for web panes** - Write our own minimal Obj-C bridge (inspired by Turf's `cocoa_bridge.m`) rather than depending on Turf directly. Gives us control and keeps dependencies minimal.

5. **macOS only for MVP** - Focus on nailing one platform. Architecture should allow future Linux/Windows ports but we won't design for them yet.

## Demo Progression

Build in usable increments to maintain momentum.

**Note:** Demos are iterative milestones on a single evolving codebase, not separate standalone apps. Each demo builds on the previous one. The `just demo-N` commands simply run the current state of stoa - they're markers of progress, not different executables.

### Demo 1: Single Terminal Window
- SwiftUI app with one full-screen window
- Embeds a single libghostty terminal surface
- Proves: libghostty integration works

### Demo 2: Single WebView Window
- SwiftUI app with one full-screen window
- Embeds a single WKWebView
- Load a URL from command line or hardcoded
- Proves: WebView bridge works

### Demo 3: Static Split (Two Terminals)
- Hardcoded horizontal split
- Two terminal panes side by side
- Proves: Multiple libghostty surfaces work

### Demo 4: Dynamic Splits (Terminals Only)
- Keybinds to create/close splits (Cmd+\ for horizontal, Cmd+- for vertical, Cmd+W to close)
- Keybinds to navigate between panes (Cmd+hjkl)
- Resizable dividers
- Proves: Split tree logic works

### Demo 5: Mixed Panes (MVP Target)
- Panes can be terminal OR webview
- Keybind to open new webview pane (prompts for URL or uses clipboard)
- Tab-like keybinds to switch pane types
- Proves: Full pane abstraction works

## Technical Components

### 1. Pane Model

Reference type that holds the actual NSView:
```swift
class Pane: Identifiable, Codable {
    let id: UUID
    var content: PaneContent

    // The actual NSView (not Codable, recreated on restore)
    weak var view: NSView?
}

enum PaneContent: Codable {
    case terminal  // view will be Ghostty.SurfaceView
    case webview(url: URL)  // view will be WKWebView
}
```

The tree holds `Pane` objects (models), and SwiftUI renders views from them using `NSViewRepresentable`.

### 2. SplitTree (from Ghostty)

Adapt Ghostty's `SplitTree.swift` with minimal modifications:
- Generic over `Pane` instead of `Ghostty.SurfaceView`
- Keep: tree structure, ratios, spatial navigation, insert/remove/resize
- Keep: `SplitView.swift` for rendering splits with dividers

### 3. StoaWindowController

Main state management and focus routing:
```swift
class StoaWindowController: NSWindowController, NSWindowDelegate, ObservableObject {
    @Published var paneTree: SplitTree<Pane>
    @Published var focusedPaneId: UUID?

    let ghosttyApp: Ghostty.App  // shared libghostty instance

    var focusedPane: Pane? {
        paneTree.first { $0.id == focusedPaneId }
    }

    // Focus management - routes to correct NSView
    func focusPane(_ pane: Pane) {
        focusedPaneId = pane.id
        guard let view = pane.view else { return }
        window?.makeFirstResponder(view)
    }

    func newTerminalSplit(direction: SplitDirection) { ... }
    func newWebViewSplit(direction: SplitDirection, url: URL) { ... }
    func closePane(_ id: UUID) { ... }
    func focusPane(direction: FocusDirection) { ... }
    func resizePane(direction: ResizeDirection, amount: CGFloat) { ... }
}
```

### 4. Terminal Integration

libghostty integration approach:
1. Build libghostty as a static library (`.a`) using Zig's build system
2. Generate C headers via Ghostty's build process
3. Create a Swift modulemap to import the C API
4. Write Swift wrapper types mirroring Ghostty's `SurfaceView`

Reference: Ghostty's `macos/Sources/Ghostty/` for the Swift wrapper patterns.

```swift
// Wrapper that bridges libghostty surface to NSView
class TerminalSurfaceView: NSView {
    let surface: ghostty_surface_t
    // ... Metal rendering, input handling
}

// SwiftUI bridge
struct TerminalViewRepresentable: NSViewRepresentable {
    let pane: Pane

    func makeNSView(context: Context) -> TerminalSurfaceView {
        let surface = TerminalSurfaceView(...)
        pane.view = surface  // Store reference in model
        return surface
    }
}
```

### 5. WebView Integration

Our own minimal wrapper around WKWebView:
```swift
struct WebViewRepresentable: NSViewRepresentable {
    let pane: Pane
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: makeConfig())
        pane.view = webView  // Store reference in model
        webView.load(URLRequest(url: url))
        return webView
    }
}
```

Bridge layer (Obj-C, ~200 lines):
- WKWebView configuration with dev tools enabled
- JS message handler for bidirectional communication
- Zoom handling (Cmd+/-)
- Basic navigation (back/forward/reload)

Reference: `~/code/turf/src/platforms/macos/cocoa_bridge.m`

### 6. PaneView (SwiftUI)

Renders the correct view type based on pane content:
```swift
struct PaneView: View {
    let pane: Pane
    let isFocused: Bool

    var body: some View {
        Group {
            switch pane.content {
            case .terminal:
                TerminalViewRepresentable(pane: pane)
            case .webview(let url):
                WebViewRepresentable(pane: pane, url: url)
            }
        }
        .overlay(focusBorder)
    }

    @ViewBuilder
    var focusBorder: some View {
        if isFocused {
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.accentColor, lineWidth: 2)
        }
    }
}
```

## Keybinds (MVP)

| Keybind | Action |
|---------|--------|
| `Cmd+\` | Split horizontal (left/right) |
| `Cmd+-` | Split vertical (top/bottom) |
| `Cmd+Shift+W` | Open webview split (prompts for URL) |
| `Cmd+W` | Close focused pane |
| `Cmd+H/J/K/L` | Focus pane left/down/up/right |
| `Cmd+Shift+H/J/K/L` | Resize pane |
| `Cmd+=` | Equalize all splits |
| `Cmd+Z` | Toggle zoom (maximize focused pane) |

## File Structure

```
stoa/
├── Stoa.xcodeproj
├── Sources/
│   ├── App/
│   │   ├── StoaApp.swift              # @main, app lifecycle
│   │   ├── AppDelegate.swift          # NSApplicationDelegate
│   │   └── StoaWindowController.swift # window + state management
│   ├── Views/
│   │   ├── ContentView.swift          # root SwiftUI view
│   │   ├── PaneView.swift             # pane rendering
│   │   ├── TerminalViewRepresentable.swift
│   │   └── WebViewRepresentable.swift
│   ├── Models/
│   │   ├── Pane.swift                 # pane model
│   │   ├── SplitTree.swift            # adapted from Ghostty
│   │   └── SplitView.swift            # adapted from Ghostty
│   ├── Terminal/
│   │   ├── TerminalSurfaceView.swift  # NSView for libghostty
│   │   └── GhosttyWrapper.swift       # Swift API for libghostty
│   └── WebView/
│       └── WebViewBridge.m            # Obj-C WKWebView config
├── Libraries/
│   └── libghostty/
│       ├── libghostty.a               # static library
│       ├── ghostty.h                  # C headers
│       └── module.modulemap           # Swift import
└── docs/
    └── mvp.md
```

## Dependencies

- **libghostty**: Terminal rendering (Zig, built as static library and linked)
- **WebKit**: WKWebView (system framework)
- **SwiftUI / AppKit**: UI framework (system)

No external Swift package dependencies for MVP.

## Out of Scope for MVP

- Multiple windows
- Tabs / workspaces
- Session persistence / restore
- Custom themes / configuration file
- Linux / Windows support
- Lua scripting / hackability layer
- Command palette

## Success Criteria

MVP is complete when:
1. App launches full-screen on macOS
2. Can create terminal panes that work like a normal terminal
3. Can create webview panes that load arbitrary URLs
4. Can split in any direction, resize, close panes
5. Can navigate between panes with keyboard
6. Feels fast and responsive (60fps, instant input response)
