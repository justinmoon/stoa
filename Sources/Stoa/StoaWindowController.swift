import AppKit
import SwiftUI
import WebKit
import StoaKit

/// Main window controller: manages split tree state, focus, and keybindings.
class StoaWindowController: NSWindowController, NSWindowDelegate, ObservableObject {
    @Published var splitTree: SplitTree
    @Published var focusedPaneId: UUID?
    @Published var isShowingURLPrompt = false
    @Published var isShowingHelp = false
    
    let ghosttyApp: GhosttyApp
    private var eventMonitor: Any?
    
    var focusedPane: Pane? {
        guard let id = focusedPaneId else { return nil }
        return splitTree.find(id: id)
    }
    
    init(ghosttyApp: GhosttyApp) {
        self.ghosttyApp = ghosttyApp
        if ProcessInfo.processInfo.environment["STOA_CHROMIUM_DEBUG"] == "1" {
            let autostart = ProcessInfo.processInfo.environment["STOA_CHROMIUM_AUTOSTART_URL"] ?? "nil"
            NSLog("StoaWindowController init, autostart=%@", autostart)
        }
        
        // Create initial pane
        let initialPane = Pane()
        if let urlString = ProcessInfo.processInfo.environment["STOA_CHROMIUM_AUTOSTART_URL"],
           let url = URL(string: urlString) {
            if ProcessInfo.processInfo.environment["STOA_CHROMIUM_DEBUG"] == "1" {
                NSLog("Autostart Chromium URL: %@", url.absoluteString)
            }
            initialPane.content = .chromium(url: url)
            initialPane.pendingSelection = .chromium
        }
        self.splitTree = SplitTree(pane: initialPane)
        self.focusedPaneId = initialPane.id
        
        // Create window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Stoa"
        window.center()
        
        super.init(window: window)
        window.delegate = self
        
        setupContentView()
        setupKeyboardMonitor()
    }
    
    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    private func setupKeyboardMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if self.handleKeyDown(event) {
                return nil  // Consume the event
            }
            return event  // Pass it through
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }
    
    private func setupContentView() {
        let contentView = NSHostingView(rootView:
            SplitTreeView(controller: self)
                .environmentObject(self)
        )
        window?.contentView = contentView
    }
    
    // MARK: - Focus Management
    
    func focusPane(_ pane: Pane) {
        focusedPaneId = pane.id
        pane.app?.focus()
    }
    
    func focusPane(direction: SplitTree.FocusDirection) {
        guard let current = focusedPane else { return }
        if let target = splitTree.focusTarget(from: current, direction: direction) {
            focusPane(target)
        }
    }
    
    // MARK: - Split Operations
    
    func splitHorizontal() {
        guard let current = focusedPane else { return }
        let newPane = Pane()
        
        do {
            splitTree = try splitTree.insert(pane: newPane, at: current, direction: .right)
            focusPane(newPane)
        } catch {
            print("Failed to split: \(error)")
        }
    }
    
    func splitVertical() {
        guard let current = focusedPane else { return }
        let newPane = Pane()
        
        do {
            splitTree = try splitTree.insert(pane: newPane, at: current, direction: .down)
            focusPane(newPane)
        } catch {
            print("Failed to split: \(error)")
        }
    }
    
    // MARK: - WebKit Split
    
    func splitWebView(direction: SplitTree.NewDirection = .right) {
        // Try to get URL from clipboard first
        if let clipboardURL = getURLFromClipboard() {
            createWebViewSplit(url: clipboardURL, direction: direction)
        } else {
            promptForBrowserURL { [weak self] url in
                self?.createWebViewSplit(url: url, direction: direction)
            }
        }
    }
    
    private func getURLFromClipboard() -> URL? {
        let pasteboard = NSPasteboard.general
        if let urlString = pasteboard.string(forType: .string),
           let url = URL(string: urlString),
           url.scheme == "http" || url.scheme == "https" {
            return url
        }
        return nil
    }
    
    private func openWebKit(in pane: Pane) {
        openBrowser(in: pane) { url in .webview(url: url) }
    }
    
    private func openChromium(in pane: Pane) {
        openBrowser(in: pane) { url in .chromium(url: url) }
    }
    
    private func openBrowser(in pane: Pane, makeContent: @escaping (URL) -> PaneContent) {
        if let clipboardURL = getURLFromClipboard() {
            pane.content = makeContent(clipboardURL)
            pane.app?.destroy()
            pane.app = nil
            DispatchQueue.main.async { [weak self] in
                self?.focusPane(pane)
            }
        } else {
            promptForBrowserURL { [weak self, weak pane] url in
                guard let pane else { return }
                pane.content = makeContent(url)
                pane.app?.destroy()
                pane.app = nil
                DispatchQueue.main.async { [weak self] in
                    self?.focusPane(pane)
                }
            }
        }
    }

    private func openEditor(in pane: Pane) {
        if let envPath = ProcessInfo.processInfo.environment["STOA_EDITOR_FILE"] {
            let url = URL(fileURLWithPath: envPath)
            createEditorPane(in: pane, url: url)
            return
        }

        if let clipboardURL = getFileURLFromClipboard() {
            createEditorPane(in: pane, url: clipboardURL)
            return
        }

        createEditorPane(in: pane, url: defaultEditorFileURL())
    }

    private func getFileURLFromClipboard() -> URL? {
        let pasteboard = NSPasteboard.general
        if let urlString = pasteboard.string(forType: .string) {
            let expanded = (urlString as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private func defaultEditorFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "stoa-editor-\(UUID().uuidString).txt"
        let url = tempDir.appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }

    private func createEditorPane(in pane: Pane, url: URL) {
        pane.content = .editor(url: url)
        DispatchQueue.main.async { [weak self] in
            self?.focusPane(pane)
        }
    }

    func openEditorForTest(url: URL) {
        guard let pane = focusedPane else { return }
        createEditorPane(in: pane, url: url)
    }
    
    private func promptForBrowserURL(defaultValue: String? = nil, completion: @escaping (URL) -> Void) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Open Web Page"
        alert.informativeText = "Enter a URL to open:"
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.placeholderString = "https://example.com"
        textField.stringValue = defaultValue?.isEmpty == false ? defaultValue! : "https://"
        alert.accessoryView = textField
        
        isShowingURLPrompt = true
        alert.beginSheetModal(for: window) { [weak self] response in
            defer { self?.isShowingURLPrompt = false }
            guard response == .alertFirstButtonReturn else { return }
            var urlString = textField.stringValue.trimmingCharacters(in: .whitespaces)
            
            // Add https:// if no scheme
            if !urlString.contains("://") {
                urlString = "https://" + urlString
            }
            
            if let url = URL(string: urlString) {
                completion(url)
            }
        }
        
        // Focus the text field
        alert.window.makeFirstResponder(textField)
    }

    private func showAddressPrompt() -> Bool {
        if isShowingURLPrompt {
            return true
        }
        guard let pane = focusedPane else { return false }
        switch pane.content {
        case .webview(let url):
            promptForBrowserURL(defaultValue: url.absoluteString) { [weak self, weak pane] newURL in
                guard let pane else { return }
                pane.content = .webview(url: newURL)
                if let app = pane.app as? StoaWebView {
                    app.load(URLRequest(url: newURL))
                } else {
                    pane.app?.destroy()
                    pane.app = nil
                }
                DispatchQueue.main.async { [weak self] in
                    self?.focusPane(pane)
                }
            }
            return true
        case .chromium(let url):
            promptForBrowserURL(defaultValue: url.absoluteString) { [weak self, weak pane] newURL in
                guard let pane else { return }
                pane.content = .chromium(url: newURL)
                if let app = pane.app as? ChromiumView {
                    app.loadURL(newURL)
                } else {
                    pane.app?.destroy()
                    pane.app = nil
                }
                DispatchQueue.main.async { [weak self] in
                    self?.focusPane(pane)
                }
            }
            return true
        case .terminal, .unselected, .editor:
            return false
        }
    }

    private func isHelpToggleEvent(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        guard let chars = event.charactersIgnoringModifiers else { return false }
        return chars == "/"
    }
    
    private func createWebViewSplit(url: URL, direction: SplitTree.NewDirection) {
        guard let current = focusedPane else { return }
        let newPane = Pane(content: .webview(url: url))
        
        do {
            splitTree = try splitTree.insert(pane: newPane, at: current, direction: direction)
            // Note: webview is created by PaneWebViewRepresentable in SwiftUI
            focusPane(newPane)
        } catch {
            print("Failed to split webview: \(error)")
        }
    }
    
    func closePane() {
        guard let current = focusedPane else { return }
        current.app?.destroy()
        current.app = nil
        
        // Find next pane to focus before removing
        let nextFocus = splitTree.focusTarget(from: current, direction: .right)
            ?? splitTree.focusTarget(from: current, direction: .left)
            ?? splitTree.focusTarget(from: current, direction: .down)
            ?? splitTree.focusTarget(from: current, direction: .up)
        
        splitTree = splitTree.remove(current)
        
        if splitTree.isEmpty {
            // Last pane closed, quit app
            NSApp.terminate(nil)
        } else if let next = nextFocus {
            focusPane(next)
        } else if let first = splitTree.panes.first {
            focusPane(first)
        }
    }
    
    // MARK: - Keyboard Handling
    
    func handleKeyDown(_ event: NSEvent) -> Bool {
        if isShowingHelp {
            if isHelpToggleEvent(event) || event.keyCode == 53 {
                isShowingHelp = false
            }
            return true
        }

        if let pane = focusedPane,
           case .unselected = pane.content,
           handlePaneTypeSelectionKeyDown(event, pane: pane) {
            return true
        }
        
        guard event.modifierFlags.contains(.command) else { return false }

        if isHelpToggleEvent(event) {
            isShowingHelp = true
            return true
        }
        
        let hasShift = event.modifierFlags.contains(.shift)
        let keyCode = event.keyCode
        
        // Debug: print key info
        print("Key: keyCode: \(keyCode) shift: \(hasShift) modifiers: \(event.modifierFlags.rawValue)")
        
        // Cmd+Shift combinations
        if hasShift {
            switch keyCode {
            case 13:  // Cmd+Shift+W - Open WebKit split
                splitWebView()
                return true
            case 37:  // Cmd+Shift+L - Address bar
                return showAddressPrompt()
            default:
                return false
            }
        }
        
        // Cmd only combinations (keyCode 42 = backslash, keyCode 27 = minus)
        switch keyCode {
        case 42:  // Backslash - Split horizontal
            splitHorizontal()
            return true
        case 27:  // Minus - Split vertical
            splitVertical()
            return true
        case 13:  // W - Close pane
            closePane()
            return true
        case 4:   // H - Focus left
            focusPane(direction: .left)
            return true
        case 38:  // J - Focus down
            focusPane(direction: .down)
            return true
        case 40:  // K - Focus up
            focusPane(direction: .up)
            return true
        case 37:  // L - Focus right
            focusPane(direction: .right)
            return true
        default:
            return false
        }
    }

    private func handlePaneTypeSelectionKeyDown(_ event: NSEvent, pane: Pane) -> Bool {
        if isShowingURLPrompt {
            return false
        }
        
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty == false {
            return false
        }
        
        switch event.keyCode {
        case 126: // Up arrow
            pane.pendingSelection = pane.pendingSelection.previous()
            return true
        case 125: // Down arrow
            pane.pendingSelection = pane.pendingSelection.next()
            return true
        case 36, 76: // Return or Enter
            applyPaneSelection(pane.pendingSelection, to: pane)
            return true
        default:
            break
        }
        
        guard let input = event.charactersIgnoringModifiers?.lowercased() else { return false }
        switch input {
        case "k":
            pane.pendingSelection = pane.pendingSelection.previous()
            return true
        case "j":
            pane.pendingSelection = pane.pendingSelection.next()
            return true
        case "c":
            applyPaneSelection(.chromium, to: pane)
            return true
        case "w":
            applyPaneSelection(.webkit, to: pane)
            return true
        case "t":
            applyPaneSelection(.terminal, to: pane)
            return true
        case "e":
            applyPaneSelection(.editor, to: pane)
            return true
        default:
            return false
        }
    }
    
    private func applyPaneSelection(_ selection: PaneTypeSelection, to pane: Pane) {
        switch selection {
        case .chromium:
            pane.pendingSelection = .chromium
            openChromium(in: pane)
        case .webkit:
            pane.pendingSelection = .webkit
            openWebKit(in: pane)
        case .terminal:
            pane.pendingSelection = .terminal
            pane.content = .terminal
            pane.app?.destroy()
            pane.app = nil
            DispatchQueue.main.async { [weak self] in
                self?.focusPane(pane)
            }
        case .editor:
            pane.pendingSelection = .editor
            openEditor(in: pane)
        }
    }

    // MARK: - App Creation

    func ensureApp(for pane: Pane, size: CGSize) -> StoaApp? {
        switch pane.content {
        case .unselected:
            pane.app?.destroy()
            pane.app = nil
            return nil
        case .terminal:
            if let app = pane.app as? TerminalSurfaceView {
                return app
            }
            pane.app?.destroy()
            pane.app = makeTerminalApp()
            return pane.app
        case .webview(let url):
            if let app = pane.app as? StoaWebView {
                if app.url != url {
                    app.load(URLRequest(url: url))
                }
                return app
            }
            pane.app?.destroy()
            pane.app = makeWebKitApp(url: url)
            return pane.app
        case .chromium(let url):
            if let app = pane.app as? ChromiumView {
                if app.currentURL != url {
                    app.loadURL(url)
                }
                return app
            }
            pane.app?.destroy()
            pane.app = makeChromiumApp(url: url, size: size)
            return pane.app
        case .editor(let url):
            if let app = pane.app as? EditorHostView, app.matches(fileURL: url) {
                return app
            }
            pane.app?.destroy()
            pane.app = makeEditorApp(url: url)
            return pane.app
        }
    }

    private func makeTerminalApp() -> StoaApp? {
        guard let app = ghosttyApp.app else {
            return nil
        }
        let terminalView = TerminalSurfaceView(app: app)
        terminalView.shouldInterceptKey = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
        return terminalView
    }

    private func makeWebKitApp(url: URL) -> StoaApp {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let webView = StoaWebView(frame: .zero, configuration: config)
        webView.allowsMagnification = true
        webView.shouldInterceptKey = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
        webView.load(URLRequest(url: url))
        return webView
    }

    private func makeChromiumApp(url: URL, size: CGSize) -> StoaApp {
        let chromiumView = ChromiumView(initialURL: url, initialSize: size)
        chromiumView.shouldInterceptKey = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
        return chromiumView
    }

    private func makeEditorApp(url: URL) -> StoaApp {
        let editorView = EditorHostView(fileURL: url)
        return editorView
    }

    // MARK: - Editor Actions

    func setEditorText(for pane: Pane, text: String) -> Bool {
        editorApp(for: pane)?.setText(text) ?? false
    }

    func saveEditor(for pane: Pane) -> Bool {
        editorApp(for: pane)?.save() ?? false
    }

    private func editorApp(for pane: Pane) -> EditorHostView? {
        if let app = pane.app as? EditorHostView {
            return app
        }
        guard case .editor = pane.content else { return nil }
        let fallbackSize = CGSize(width: 800, height: 600)
        let size = window?.contentView?.bounds.size ?? fallbackSize
        _ = ensureApp(for: pane, size: size)
        return pane.app as? EditorHostView
    }
    
    // MARK: - NSWindowDelegate
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return true
    }
}
