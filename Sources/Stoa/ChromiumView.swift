import AppKit
import ImageIO
import StoaCEF
import StoaKit
import UniformTypeIdentifiers

final class ChromiumView: NSView, StoaApp {
    static var appType: String { "chromium" }

    var onEvent: ((StoaAppEvent) -> Void)?
    var shouldInterceptKey: ((NSEvent) -> Bool)?

    private var browser: OpaquePointer?
    private var image: CGImage?
    private var pixelData: Data?
    private var trackingArea: NSTrackingArea?
    private let runtime = ChromiumRuntime.shared
    private var didDumpFrame = false
    private let frameDumpPath: String?

    private(set) var currentURL: URL?

    init(initialURL: URL, initialSize: CGSize) {
        self.currentURL = initialURL
        self.frameDumpPath = ProcessInfo.processInfo.environment["STOA_CHROMIUM_DUMP_FRAME_PATH"]
        super.init(frame: NSRect(origin: .zero, size: initialSize))
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize

        guard runtime.ensureInitialized() else {
            debugLog("ChromiumView: runtime initialization failed")
            return
        }

        debugLog("ChromiumView: creating browser for \(initialURL.absoluteString)")
        createBrowser(url: initialURL, size: initialSize)
        updateTrackingAreas()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func destroy() {
        if let browser {
            stoa_cef_browser_destroy(browser)
            self.browser = nil
        }
        trackingArea.map(removeTrackingArea)
        trackingArea = nil
    }

    func loadURL(_ url: URL) {
        currentURL = url
        guard let browser else { return }
        stoa_cef_browser_load_url(browser, url.absoluteString)
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        setBrowserFocus(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        setBrowserFocus(false)
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            resizeBrowser()
            setBrowserFocus(true)
            updateDeviceScaleFactor()
        }
    }

    override func layout() {
        super.layout()
        resizeBrowser()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        resizeBrowser()
    }

    override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        resizeBrowser()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDeviceScaleFactor()
        resizeBrowser()
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .inVisibleRect,
            .activeInKeyWindow
        ]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        if let trackingArea {
            addTrackingArea(trackingArea)
        }
        super.updateTrackingAreas()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image, let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        context.draw(image, in: bounds)
    }

    // MARK: - Input

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            if let handler = shouldInterceptKey, handler(event) {
                return
            }
        }
        sendKeyEvent(event, type: .down)
        sendKeyEvent(event, type: .char)
    }

    override func keyUp(with event: NSEvent) {
        sendKeyEvent(event, type: .up)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        setBrowserFocus(true)
        sendMouseClick(event, mouseUp: false)
    }

    override func mouseUp(with event: NSEvent) {
        sendMouseClick(event, mouseUp: true)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        setBrowserFocus(true)
        sendMouseClick(event, mouseUp: false)
    }

    override func rightMouseUp(with event: NSEvent) {
        sendMouseClick(event, mouseUp: true)
    }

    override func otherMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        setBrowserFocus(true)
        sendMouseClick(event, mouseUp: false)
    }

    override func otherMouseUp(with event: NSEvent) {
        sendMouseClick(event, mouseUp: true)
    }

    override func mouseMoved(with event: NSEvent) {
        sendMouseMove(event, mouseLeave: false)
    }

    override func mouseDragged(with event: NSEvent) {
        sendMouseMove(event, mouseLeave: false)
    }

    override func mouseEntered(with event: NSEvent) {
        sendMouseMove(event, mouseLeave: false)
    }

    override func mouseExited(with event: NSEvent) {
        sendMouseMove(event, mouseLeave: true)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let browser else { return }
        let point = convert(event.locationInWindow, from: nil)
        let mods = cefModifiers(from: event, includeMouseButtons: false, includeRepeat: false, includeScrollDelta: true)
        let y = bounds.height - point.y
        stoa_cef_browser_send_mouse_wheel(
            browser,
            Int32(point.x),
            Int32(y),
            mods,
            Int32(event.scrollingDeltaX),
            Int32(event.scrollingDeltaY)
        )
    }

    // MARK: - CEF Integration

    private func createBrowser(url: URL, size: CGSize) {
        let viewSize = viewSizeForCEF(size)
        let viewPointer = Unmanaged.passUnretained(self).toOpaque()
        let scaleFactor = Float(currentDeviceScaleFactor())
        browser = stoa_cef_browser_create(
            url.absoluteString,
            Int32(viewSize.width),
            Int32(viewSize.height),
            viewPointer,
            scaleFactor,
            viewPointer,
            ChromiumView.paintCallback
        )
        if browser == nil {
            debugLog("ChromiumView: stoa_cef_browser_create returned nil")
        }
    }

    private func resizeBrowser() {
        guard let browser else { return }
        let viewSize = viewSizeForCEF(bounds.size)
        stoa_cef_browser_resize(browser, Int32(viewSize.width), Int32(viewSize.height))
    }

    private func handlePaint(width: Int32, height: Int32, buffer: UnsafePointer<UInt8>?, length: Int32) {
        guard let buffer, length > 0 else { return }
        let data = Data(bytes: buffer, count: Int(length))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let alphaInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(alphaInfo)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: Int(width),
                height: Int(height),
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: Int(width) * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return
        }

        pixelData = data
        self.image = image
        needsDisplay = true
        dumpFrameIfNeeded(image)
    }

    private static let paintCallback: stoa_cef_paint_callback = { userData, width, height, buffer, length in
        guard let userData else { return }
        let view = Unmanaged<ChromiumView>.fromOpaque(userData).takeUnretainedValue()
        if Thread.isMainThread {
            view.handlePaint(width: width, height: height, buffer: buffer?.assumingMemoryBound(to: UInt8.self), length: length)
        } else {
            DispatchQueue.main.async {
                view.handlePaint(width: width, height: height, buffer: buffer?.assumingMemoryBound(to: UInt8.self), length: length)
            }
        }
    }

    private enum KeyEventType: Int32 {
        case rawDown = 0
        case down = 1
        case up = 2
        case char = 3
    }

    private func sendKeyEvent(_ event: NSEvent, type: KeyEventType) {
        guard let browser else { return }
        let mods = cefModifiers(from: event, includeMouseButtons: true, includeRepeat: event.isARepeat)
        var character: UInt32 = 0
        var unmodified: UInt32 = 0
        if type == .char {
            character = event.characters?.utf16.first.map { UInt32($0) } ?? 0
            unmodified = event.charactersIgnoringModifiers?.utf16.first.map { UInt32($0) } ?? 0
        }
        stoa_cef_browser_send_key_event(
            browser,
            type.rawValue,
            mods,
            character,
            unmodified,
            UInt32(event.keyCode)
        )
    }

    private func sendMouseMove(_ event: NSEvent, mouseLeave: Bool) {
        guard let browser else { return }
        let point = convert(event.locationInWindow, from: nil)
        let y = bounds.height - point.y
        let mods = cefModifiers(from: event, includeMouseButtons: true)
        stoa_cef_browser_send_mouse_move(
            browser,
            Int32(point.x),
            Int32(y),
            mods,
            mouseLeave
        )
    }

    private func sendMouseClick(_ event: NSEvent, mouseUp: Bool) {
        guard let browser else { return }
        let point = convert(event.locationInWindow, from: nil)
        let y = bounds.height - point.y
        let mods = cefModifiers(from: event, includeMouseButtons: true)
        let button = cefMouseButton(from: event)
        stoa_cef_browser_send_mouse_click(
            browser,
            Int32(point.x),
            Int32(y),
            mods,
            button,
            mouseUp,
            Int32(event.clickCount)
        )
    }

    private func viewSizeForCEF(_ size: CGSize) -> CGSize {
        CGSize(width: max(1, size.width), height: max(1, size.height))
    }

    private func currentDeviceScaleFactor() -> CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
    }

    private func updateDeviceScaleFactor() {
        guard let browser else { return }
        stoa_cef_browser_set_device_scale(browser, Float(currentDeviceScaleFactor()))
    }

    private func cefModifiers(
        from event: NSEvent,
        includeMouseButtons: Bool,
        includeRepeat: Bool = false,
        includeScrollDelta: Bool = false
    ) -> Int32 {
        var mods: Int32 = 0
        if event.modifierFlags.contains(.capsLock) { mods |= 1 << 0 }
        if event.modifierFlags.contains(.shift) { mods |= 1 << 1 }
        if event.modifierFlags.contains(.control) { mods |= 1 << 2 }
        if event.modifierFlags.contains(.option) { mods |= 1 << 3 }
        if event.modifierFlags.contains(.command) { mods |= 1 << 7 }
        if event.modifierFlags.contains(.numericPad) { mods |= 1 << 9 }
        if includeRepeat && event.isARepeat { mods |= 1 << 13 }
        if includeScrollDelta && event.hasPreciseScrollingDeltas { mods |= 1 << 14 }
        if includeMouseButtons {
            let buttons = NSEvent.pressedMouseButtons
            if buttons & 1 != 0 { mods |= 1 << 4 }
            if buttons & 2 != 0 { mods |= 1 << 6 }
            if buttons & 4 != 0 { mods |= 1 << 5 }
        }
        return mods
    }

    private func cefMouseButton(from event: NSEvent) -> Int32 {
        switch event.type {
        case .rightMouseDown, .rightMouseUp:
            return Int32(STOA_CEF_MOUSE_RIGHT.rawValue)
        case .otherMouseDown, .otherMouseUp:
            return Int32(STOA_CEF_MOUSE_MIDDLE.rawValue)
        default:
            return Int32(STOA_CEF_MOUSE_LEFT.rawValue)
        }
    }

    private func dumpFrameIfNeeded(_ image: CGImage) {
        guard !didDumpFrame, let frameDumpPath else { return }
        let url = URL(fileURLWithPath: frameDumpPath)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        if CGImageDestinationFinalize(destination) {
            didDumpFrame = true
            debugLog("ChromiumView wrote frame dump to \(frameDumpPath)")
        }
    }

    private func debugLog(_ message: String) {
        if ProcessInfo.processInfo.environment["STOA_CHROMIUM_DEBUG"] == "1" {
            NSLog("%@", message)
        }
    }

    private func setBrowserFocus(_ focus: Bool) {
        guard let browser else { return }
        stoa_cef_browser_set_focus(browser, focus)
    }
}
