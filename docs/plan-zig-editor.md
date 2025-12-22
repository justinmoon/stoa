# Plan: Zig Editor (Mach + Flow)

## Goal

Build a minimal, fast, GPU-accelerated code editor in Zig by combining:
- **Mach Engine** - Windowing, input, WebGPU rendering
- **Flow's Buffer** - Rope data structure, cursor/selection, undo/redo

This gives us Flow's battle-tested text editing with Mach's modern GPU rendering.

## Why This Approach?

| What | Flow Provides | Mach Provides |
|------|---------------|---------------|
| Text buffer | Hybrid rope/piece-table | - |
| Cursor/selection | Full implementation | - |
| Undo/redo | Infinite, branching | - |
| Syntax highlighting | Tree-sitter integration | - |
| Keybindings | Vim/Emacs/Helix modes | - |
| Windowing | - | Cross-platform native |
| Input | - | Keyboard/mouse events |
| Rendering | TUI only | WebGPU (Metal/Vulkan/DX12) |
| Text rendering | - | FreeType/HarfBuzz |

**Key insight**: Flow's `src/buffer/` is cleanly separated from TUI rendering. We swap the renderer, keep the editing logic.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        stoa-editor                               │
│                      (our new crate)                             │
├─────────────────────────────────────────────────────────────────┤
│  EditorModule (Mach module)                                      │
│  ├── EditorState                                                 │
│  │   ├── buffer: flow.Buffer.Root      (from Flow)              │
│  │   ├── cursor: flow.Cursor           (from Flow)              │
│  │   ├── selection: flow.Selection     (from Flow)              │
│  │   ├── view: flow.View               (from Flow)              │
│  │   └── undo_stack: flow.UndoNode     (from Flow)              │
│  ├── render_state: TextRenderer                                  │
│  │   ├── font_atlas: GlyphAtlas                                 │
│  │   ├── text_pipeline: gpu.RenderPipeline                      │
│  │   └── vertex_buffer: gpu.Buffer                              │
│  └── syntax: flow.Syntax               (from Flow)              │
├─────────────────────────────────────────────────────────────────┤
│  mach.core        │  mach-freetype     │  flow-syntax           │
│  (window/input)   │  (font rendering)  │  (tree-sitter)         │
├─────────────────────────────────────────────────────────────────┤
│  mach.sysgpu (WebGPU)                                           │
│  ├── Metal (macOS)                                              │
│  ├── Vulkan (Linux)                                             │
│  └── DirectX 12 (Windows)                                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## What We Take From Flow

### Direct Imports (Copy or Git Submodule)

```
flow/src/buffer/
├── Buffer.zig        # 1,726 lines - Rope implementation
├── Cursor.zig        # ~150 lines - Cursor movement
├── Selection.zig     # ~150 lines - Selection handling
├── View.zig          # ~100 lines - Viewport scrolling
├── Manager.zig       # ~150 lines - Multi-buffer management
└── unicode.zig       # UTF-8 utilities

flow/src/
├── text_manip.zig    # Text manipulation utilities
└── keybind/          # Keybinding system (optional)
    ├── keybind.zig
    ├── parse_vim.zig
    └── builtin/*.json
```

**Total: ~2,500 lines of proven, reusable code**

### Adapting Flow's Metrics System

Flow's buffer uses a `Metrics` interface for width calculation. This is perfect for GUI:

```zig
// Flow's interface
pub const Metrics = struct {
    ctx: *const anyopaque,
    egc_length: *const fn(metrics, egcs, *col_count, abs_col) usize,
    egc_chunk_width: *const fn(metrics, chunk, abs_col) usize,
    tab_width: usize,
};

// Our GUI implementation
pub fn createGuiMetrics(font_atlas: *FontAtlas) Metrics {
    return .{
        .ctx = font_atlas,
        .egc_length = guiEgcLength,      // Use font metrics
        .egc_chunk_width = guiChunkWidth, // Pixel-based width
        .tab_width = 4,
    };
}
```

---

## What We Build on Mach

### 1. Text Rendering Pipeline

```zig
// src/text_renderer.zig
const TextRenderer = struct {
    device: *gpu.Device,
    pipeline: gpu.RenderPipeline,
    glyph_atlas: GlyphAtlas,
    vertex_buffer: gpu.Buffer,
    index_buffer: gpu.Buffer,
    uniform_buffer: gpu.Buffer,

    pub fn init(device: *gpu.Device, allocator: Allocator) !TextRenderer {
        // Load font via mach-freetype
        const font = try freetype.Face.init(font_data);

        // Generate glyph atlas (SDF or bitmap)
        const atlas = try GlyphAtlas.generate(font, allocator);

        // Create GPU pipeline for text rendering
        const shader = try device.createShaderModuleWGSL(@embedFile("text.wgsl"));
        const pipeline = try device.createRenderPipeline(.{
            .vertex = .{ .module = shader, .entry_point = "vs_main" },
            .fragment = .{ .module = shader, .entry_point = "fs_main" },
            // ...
        });

        return .{ .device = device, .pipeline = pipeline, .glyph_atlas = atlas };
    }

    pub fn renderText(
        self: *TextRenderer,
        pass: *gpu.RenderPass,
        buffer: Buffer.Root,
        view: View,
        cursor: Cursor,
        selection: ?Selection,
        syntax_highlights: []const Highlight,
    ) void {
        // 1. Calculate visible lines from view
        // 2. Shape text with HarfBuzz
        // 3. Generate vertex data for visible glyphs
        // 4. Render selection background
        // 5. Render text
        // 6. Render cursor
    }
};
```

### 2. Glyph Atlas

```zig
// src/glyph_atlas.zig
const GlyphAtlas = struct {
    texture: gpu.Texture,
    texture_view: gpu.TextureView,
    glyphs: std.AutoHashMap(u32, GlyphInfo),

    const GlyphInfo = struct {
        uv: [4]f32,      // Texture coordinates
        size: [2]f32,    // Glyph size in pixels
        bearing: [2]f32, // Offset from baseline
        advance: f32,    // Horizontal advance
    };

    pub fn generate(face: freetype.Face, allocator: Allocator) !GlyphAtlas {
        // Rasterize ASCII + common Unicode to texture atlas
        // Use SDF for resolution-independent rendering (optional)
    }

    pub fn getGlyph(self: *GlyphAtlas, codepoint: u32) ?GlyphInfo {
        return self.glyphs.get(codepoint);
    }
};
```

### 3. Text Shaping (HarfBuzz)

```zig
// src/text_shaper.zig
const TextShaper = struct {
    hb_font: *harfbuzz.Font,
    hb_buffer: *harfbuzz.Buffer,

    pub fn shape(self: *TextShaper, text: []const u8) []const ShapedGlyph {
        harfbuzz.buffer_add_utf8(self.hb_buffer, text);
        harfbuzz.shape(self.hb_font, self.hb_buffer, null, 0);

        const info = harfbuzz.buffer_get_glyph_infos(self.hb_buffer);
        const pos = harfbuzz.buffer_get_glyph_positions(self.hb_buffer);

        // Convert to our ShapedGlyph format
    }
};
```

### 4. Editor Module (Mach Integration)

```zig
// src/EditorModule.zig
pub const EditorModule = struct {
    pub const mach_module = .editor;

    // State
    buffer_manager: flow.BufferManager,
    active_buffer: *flow.Buffer,
    cursor: flow.Cursor,
    selection: ?flow.Selection,
    view: flow.View,
    mode: KeybindMode,

    // Rendering
    text_renderer: TextRenderer,

    // Mach systems
    pub const mach_systems = .{
        .init,
        .tick,
        .render,
        .deinit,
    };

    pub fn init(self: *@This(), core: *mach.Core) !void {
        self.text_renderer = try TextRenderer.init(core.device, allocator);
        self.buffer_manager = flow.BufferManager.init(allocator);
        self.active_buffer = try self.buffer_manager.open_scratch("untitled", "");
        self.cursor = .{};
        self.view = .{ .rows = 40, .cols = 120 };
    }

    pub fn tick(self: *@This(), core: *mach.Core) !void {
        // Process input events
        for (core.events()) |event| {
            switch (event) {
                .key_press => |e| try self.handleKeyPress(e),
                .char_input => |e| try self.handleCharInput(e),
                .mouse_button => |e| try self.handleMouse(e),
                .scroll => |e| try self.handleScroll(e),
                else => {},
            }
        }
    }

    pub fn render(self: *@This(), core: *mach.Core) !void {
        const pass = core.beginRenderPass();

        self.text_renderer.renderText(
            pass,
            self.active_buffer.root,
            self.view,
            self.cursor,
            self.selection,
            self.getSyntaxHighlights(),
        );

        pass.end();
        core.present();
    }

    fn handleKeyPress(self: *@This(), event: KeyEvent) !void {
        // Map key to command via keybind system
        if (self.mode.lookup(event)) |command| {
            try self.executeCommand(command);
        }
    }

    fn handleCharInput(self: *@This(), char: u21) !void {
        // Insert character at cursor
        const result = try self.active_buffer.insert_chars(
            self.cursor.row,
            self.cursor.col,
            &[_]u8{char},
            allocator,
            self.metrics,
        );
        self.cursor.row = result.row;
        self.cursor.col = result.col;
        self.active_buffer.root = result.root;
    }

    fn executeCommand(self: *@This(), cmd: Command) !void {
        switch (cmd) {
            .move_left => self.cursor.move_left(self.active_buffer.root, self.metrics),
            .move_right => self.cursor.move_right(self.active_buffer.root, self.metrics),
            .move_up => self.cursor.move_up(self.active_buffer.root, self.metrics),
            .move_down => self.cursor.move_down(self.active_buffer.root, self.metrics),
            .delete_char => {
                self.active_buffer.store_undo("delete");
                self.active_buffer.root = try self.active_buffer.delete_bytes(...);
            },
            .undo => _ = try self.active_buffer.undo(),
            .redo => _ = try self.active_buffer.redo(),
            .save => try self.active_buffer.store_to_file_and_clean(self.path),
            // ...
        }
    }
};
```

---

## Project Structure

```
stoa-editor/
├── build.zig
├── build.zig.zon
├── src/
│   ├── main.zig              # Entry point
│   ├── EditorModule.zig      # Main editor logic
│   ├── TextRenderer.zig      # GPU text rendering
│   ├── GlyphAtlas.zig        # Font atlas generation
│   ├── TextShaper.zig        # HarfBuzz text shaping
│   ├── Theme.zig             # Color schemes
│   └── shaders/
│       └── text.wgsl         # Text rendering shader
├── deps/
│   └── flow-buffer/          # Extracted from Flow (git subtree)
│       ├── Buffer.zig
│       ├── Cursor.zig
│       ├── Selection.zig
│       ├── View.zig
│       └── unicode.zig
└── assets/
    └── fonts/
        └── JetBrainsMono.ttf
```

### build.zig.zon

```zig
.{
    .name = "stoa-editor",
    .version = "0.1.0",
    .dependencies = .{
        .mach = .{
            .url = "https://github.com/hexops/mach/archive/...",
            .hash = "...",
        },
        .@"mach-freetype" = .{
            .url = "https://github.com/hexops/mach-freetype/archive/...",
            .hash = "...",
        },
        .@"flow-syntax" = .{
            .url = "https://github.com/neurocyte/flow-syntax/archive/...",
            .hash = "...",
        },
    },
}
```

---

## Implementation Phases

### Phase 1: Window + Basic Rendering (3-4 days)

**Goal**: Mach window displaying static text

- [ ] Set up Mach project with `mach.core`
- [ ] Integrate `mach-freetype` for font loading
- [ ] Build glyph atlas from font
- [ ] Write WGSL shader for textured quads
- [ ] Render "Hello, World!" to screen

**Success**: Window shows monospace text, can resize

### Phase 2: Flow Buffer Integration (3-4 days)

**Goal**: Edit text using Flow's buffer

- [ ] Extract Flow's buffer code (git subtree or copy)
- [ ] Adapt Metrics interface for pixel widths
- [ ] Wire keyboard input → buffer operations
- [ ] Implement cursor movement (hjkl)
- [ ] Implement insert/delete

**Success**: Can type, move cursor, delete - like a basic textarea

### Phase 3: Viewport + Scrolling (2-3 days)

**Goal**: Handle files larger than screen

- [ ] Implement View for viewport tracking
- [ ] Scroll on cursor movement past edges
- [ ] Mouse scroll wheel support
- [ ] Line numbers gutter

**Success**: Can open and scroll through a 1000-line file

### Phase 4: Syntax Highlighting (2-3 days)

**Goal**: Colored code

- [ ] Integrate `flow-syntax` (tree-sitter)
- [ ] Map tree-sitter tokens to colors
- [ ] Incremental re-highlighting on edit
- [ ] Theme support (at least one dark theme)

**Success**: Rust/Zig/JS files display with syntax colors

### Phase 5: Selection + Clipboard (2-3 days)

**Goal**: Select and copy/paste

- [ ] Implement visual selection (Shift+arrows, mouse drag)
- [ ] Selection rendering (highlight background)
- [ ] OS clipboard integration (Cmd+C, Cmd+V)
- [ ] Cut, copy, paste operations

**Success**: Can select text, copy to system clipboard, paste

### Phase 6: Undo/Redo (1-2 days)

**Goal**: Full undo support

- [ ] Wire Flow's undo system
- [ ] Cmd+Z / Cmd+Shift+Z bindings
- [ ] Undo grouping (word-level, not char-level)

**Success**: Can undo/redo any operation

### Phase 7: File Operations (1-2 days)

**Goal**: Open/save files

- [ ] File open dialog (native or simple path input)
- [ ] Save (Cmd+S)
- [ ] Dirty indicator
- [ ] Warn on close if unsaved

**Success**: Can edit and save real files

### Phase 8: Keybinding Modes (2-3 days)

**Goal**: Vim mode

- [ ] Port Flow's keybind parser
- [ ] Implement normal/insert/visual modes
- [ ] Basic vim motions (w, b, e, 0, $, gg, G)
- [ ] Basic vim commands (:w, :q)

**Success**: Vim users feel at home

---

## Timeline Estimate

| Phase | Days | Cumulative |
|-------|------|------------|
| 1. Window + Rendering | 3-4 | 4 |
| 2. Buffer Integration | 3-4 | 8 |
| 3. Viewport + Scrolling | 2-3 | 11 |
| 4. Syntax Highlighting | 2-3 | 14 |
| 5. Selection + Clipboard | 2-3 | 17 |
| 6. Undo/Redo | 1-2 | 19 |
| 7. File Operations | 1-2 | 21 |
| 8. Vim Mode | 2-3 | 24 |

**Total: ~3-4 weeks to usable editor**

---

## Stoa Integration Strategy

Once the editor works standalone, integration with Stoa follows the same pattern as the GPUI plan:

### Option A: Subprocess (Recommended for dev)

```
Stoa spawns: stoa-editor --position=100,100 --size=800,600 /path/to/file.rs
Editor creates borderless Mach window at specified position
Stoa tracks pane bounds, sends position updates via IPC
```

### Option B: Static Library + C FFI

```zig
// Export C API
export fn stoa_editor_new(config: *const Config) *Editor { ... }
export fn stoa_editor_set_size(e: *Editor, w: u32, h: u32) void { ... }
export fn stoa_editor_key_event(e: *Editor, event: *const KeyEvent) bool { ... }
export fn stoa_editor_render(e: *Editor) void { ... }
export fn stoa_editor_get_metal_layer(e: *Editor) *anyopaque { ... }
```

Swift side receives CAMetalLayer, composites into Stoa's window.

---

## Comparison: Zig vs Rust Approach

| Aspect | Zig (Mach + Flow) | Rust (GPUI + Zed) |
|--------|-------------------|-------------------|
| Build time | ~5-10 sec | ~30-60 sec |
| Binary size | ~5 MB | ~20 MB |
| Text editing code | Flow's 2,500 lines | Zed's 10,000+ lines |
| UI framework | Mach (simpler) | GPUI (more features) |
| Tree-sitter | Same | Same |
| Vim mode | Flow's (complete) | Zed's (complete) |
| Platform support | All equal | macOS best |
| Learning curve | Gentler | Steeper |

**Verdict**: Zig path is leaner and potentially faster to iterate on. Rust path has more ecosystem but more complexity.

---

## Open Questions

### Q1: Font Rendering Approach?

Options:
- **A) Bitmap atlas** - Simple, fast, slightly blurry at non-native sizes
- **B) SDF (Signed Distance Field)** - Resolution-independent, more complex shader
- **C) Direct rasterization** - Sharpest, but slower

**Recommendation**: Start with A, upgrade to B if needed.

### Q2: How to Handle Flow's Syntax Module?

Options:
- **A) Full dependency** - Use flow-syntax as-is (includes all 70+ languages)
- **B) Minimal subset** - Fork with only languages we need
- **C) Build our own** - Direct tree-sitter, simpler highlighting

**Recommendation**: A for now, optimize later if bundle size matters.

### Q3: Keybinding System Complexity?

Options:
- **A) Flow's full system** - Vim/Emacs/Helix modes, JSON configs
- **B) Simplified** - Just vim normal/insert, hardcoded
- **C) VSCode-style** - No modes, just shortcuts

**Recommendation**: B for MVP, upgrade to A when stable.

---

## Success Criteria

### MVP Done When:

- [ ] Opens a file from command line
- [ ] Displays with syntax highlighting
- [ ] Cursor movement (arrows, hjkl in normal mode)
- [ ] Insert mode (i) and back to normal (Esc)
- [ ] Basic editing (insert, delete, backspace)
- [ ] Save file (Cmd+S or :w)
- [ ] Undo/redo works
- [ ] Scrolling works for large files
- [ ] Selection + copy/paste works
- [ ] ~60 FPS on 10,000 line file

### Non-Goals (for MVP):

- LSP integration
- Multiple tabs/splits
- File tree
- Search/replace UI
- Git integration
- Settings UI

---

## References

- [Mach Engine](https://machengine.org/)
- [Flow Editor](https://github.com/neurocyte/flow)
- [mach-freetype](https://github.com/hexops/mach-freetype)
- [flow-syntax](https://github.com/neurocyte/flow-syntax)
- [WebGPU Spec](https://www.w3.org/TR/webgpu/)
- [WGSL Spec](https://www.w3.org/TR/WGSL/)
