import AppKit

class TerminalSurfaceView: NSView {
    private var surface: ghostty_surface_t?
    private var trackingArea: NSTrackingArea?
    
    /// Callback for handling Cmd+key events (for split management)
    var onKeyDown: ((NSEvent) -> Bool)?

    init(app: ghostty_app_t) {
        super.init(frame: NSMakeRect(0, 0, 800, 600))

        // Configure the view
        self.wantsLayer = true
        self.layerContentsRedrawPolicy = .duringViewResize

        // Create surface configuration
        var config = ghostty_surface_config_new()
        config.userdata = Unmanaged.passUnretained(self).toOpaque()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(self).toOpaque()
        ))
        config.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2.0)
        config.font_size = 0  // Use default

        // Create the surface
        guard let surface = ghostty_surface_new(app, &config) else {
            print("Failed to create surface")
            return
        }
        self.surface = surface

        updateTrackingAreas()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        if let surface = surface {
            ghostty_surface_free(surface)
        }
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
    }

    // MARK: - First Responder

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        guard let surface = surface else { return false }
        ghostty_surface_set_focus(surface, true)
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        guard let surface = surface else { return super.resignFirstResponder() }
        ghostty_surface_set_focus(surface, false)
        return super.resignFirstResponder()
    }

    // MARK: - Tracking Area

    override func updateTrackingAreas() {
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }

        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .inVisibleRect,
            .activeInKeyWindow
        ]

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )

        if let trackingArea = trackingArea {
            addTrackingArea(trackingArea)
        }

        super.updateTrackingAreas()
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        updateSurfaceSize()
    }
    
    /// Notify libghostty of size change - must convert to backing (pixel) coordinates
    func updateSurfaceSize() {
        guard let surface = surface else { return }
        // Convert points to pixels (framebuffer size)
        let scaledSize = convertToBacking(bounds.size)
        let width = UInt32(max(1, scaledSize.width))
        let height = UInt32(max(1, scaledSize.height))
        ghostty_surface_set_size(surface, width, height)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let surface = surface, let window = window else { return }
        let scale = Double(window.backingScaleFactor)
        ghostty_surface_set_content_scale(surface, scale, scale)
    }

    // MARK: - Keyboard Input

    override func keyDown(with event: NSEvent) {
        // Let controller handle Cmd+key for splits
        if event.modifierFlags.contains(.command) {
            if let handler = onKeyDown, handler(event) {
                return
            }
        }
        
        guard let surface = surface else { return }

        let mods = translateMods(event.modifierFlags)
        let text = event.characters ?? ""

        text.withCString { cStr in
            var keyEvent = ghostty_input_key_s()
            keyEvent.action = GHOSTTY_ACTION_PRESS
            keyEvent.mods = mods
            keyEvent.consumed_mods = GHOSTTY_MODS_NONE
            keyEvent.keycode = UInt32(event.keyCode)
            keyEvent.composing = false
            keyEvent.text = cStr
            keyEvent.unshifted_codepoint = 0
            _ = ghostty_surface_key(surface, keyEvent)
        }
    }

    override func keyUp(with event: NSEvent) {
        guard let surface = surface else { return }

        let mods = translateMods(event.modifierFlags)

        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_RELEASE
        keyEvent.mods = mods
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.composing = false
        keyEvent.text = nil
        keyEvent.unshifted_codepoint = 0
        _ = ghostty_surface_key(surface, keyEvent)
    }

    override func flagsChanged(with event: NSEvent) {
        // Modifier-only changes - not needed for basic demo
    }

    // MARK: - Mouse Input

    override func mouseDown(with event: NSEvent) {
        guard let surface = surface else { return }
        window?.makeFirstResponder(self)
        let mods = translateMods(event.modifierFlags)
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface = surface else { return }
        let mods = translateMods(event.modifierFlags)
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func mouseMoved(with event: NSEvent) {
        reportMousePosition(event)
    }

    override func mouseDragged(with event: NSEvent) {
        reportMousePosition(event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface = surface else { return }
        let mods = translateScrollMods(event)
        ghostty_surface_mouse_scroll(surface, event.scrollingDeltaX, event.scrollingDeltaY, mods)
    }

    private func reportMousePosition(_ event: NSEvent) {
        guard let surface = surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        let mods = translateMods(event.modifierFlags)
        ghostty_surface_mouse_pos(surface, point.x, bounds.height - point.y, mods)
    }

    // MARK: - Modifier Translation

    private func translateMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods: UInt32 = 0
        if flags.contains(.shift) { mods |= UInt32(GHOSTTY_MODS_SHIFT.rawValue) }
        if flags.contains(.control) { mods |= UInt32(GHOSTTY_MODS_CTRL.rawValue) }
        if flags.contains(.option) { mods |= UInt32(GHOSTTY_MODS_ALT.rawValue) }
        if flags.contains(.command) { mods |= UInt32(GHOSTTY_MODS_SUPER.rawValue) }
        if flags.contains(.capsLock) { mods |= UInt32(GHOSTTY_MODS_CAPS.rawValue) }
        return ghostty_input_mods_e(rawValue: mods)
    }

    private func translateScrollMods(_ event: NSEvent) -> ghostty_input_scroll_mods_t {
        var mods: Int32 = 0
        // Precision scrolling (trackpad)
        if event.hasPreciseScrollingDeltas {
            mods |= 1 << 0
        }
        return mods
    }
}
