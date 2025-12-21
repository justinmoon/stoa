import AppKit
import SwiftUI

/// Main controller for Demo 4: manages split tree state, focus, and keybindings.
class StoaWindowController: NSWindowController, NSWindowDelegate, ObservableObject {
    @Published var splitTree: SplitTree
    @Published var focusedPaneId: UUID?
    @Published var isShowingURLPrompt = false
    
    let ghosttyApp: GhosttyApp
    private var eventMonitor: Any?
    
    var focusedPane: Pane? {
        guard let id = focusedPaneId else { return nil }
        return splitTree.find(id: id)
    }
    
    init(ghosttyApp: GhosttyApp) {
        self.ghosttyApp = ghosttyApp
        
        // Create initial pane
        let initialPane = Pane()
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
                .environmentObject(ghosttyApp)
                .environmentObject(self)
        )
        window?.contentView = contentView
    }
    
    // MARK: - Focus Management
    
    func focusPane(_ pane: Pane) {
        focusedPaneId = pane.id
        if let view = pane.view {
            window?.makeFirstResponder(view)
        }
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
        let newPane = Pane(content: .terminal)
        
        do {
            splitTree = try splitTree.insert(pane: newPane, at: current, direction: .right)
            focusPane(newPane)
        } catch {
            print("Failed to split: \(error)")
        }
    }
    
    func splitVertical() {
        guard let current = focusedPane else { return }
        let newPane = Pane(content: .terminal)
        
        do {
            splitTree = try splitTree.insert(pane: newPane, at: current, direction: .down)
            focusPane(newPane)
        } catch {
            print("Failed to split: \(error)")
        }
    }
    
    // MARK: - WebView Split
    
    func splitWebView(direction: SplitTree.NewDirection = .right) {
        // Try to get URL from clipboard first
        if let clipboardURL = getURLFromClipboard() {
            createWebViewSplit(url: clipboardURL, direction: direction)
        } else {
            showURLPrompt(direction: direction)
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
    
    private func showURLPrompt(direction: SplitTree.NewDirection) {
        let alert = NSAlert()
        alert.messageText = "Open Web Page"
        alert.informativeText = "Enter a URL to open in a new pane:"
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.placeholderString = "https://example.com"
        textField.stringValue = "https://"
        alert.accessoryView = textField
        
        alert.beginSheetModal(for: window!) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            var urlString = textField.stringValue.trimmingCharacters(in: .whitespaces)
            
            // Add https:// if no scheme
            if !urlString.contains("://") {
                urlString = "https://" + urlString
            }
            
            if let url = URL(string: urlString) {
                self?.createWebViewSplit(url: url, direction: direction)
            }
        }
        
        // Focus the text field
        alert.window.makeFirstResponder(textField)
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
        guard event.modifierFlags.contains(.command) else { return false }
        
        let hasShift = event.modifierFlags.contains(.shift)
        let keyCode = event.keyCode
        
        // Debug: print key info
        print("Key: keyCode: \(keyCode) shift: \(hasShift) modifiers: \(event.modifierFlags.rawValue)")
        
        // Cmd+Shift combinations
        if hasShift {
            switch keyCode {
            case 13:  // Cmd+Shift+W - Open webview split
                splitWebView()
                return true
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
    
    // MARK: - NSWindowDelegate
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return true
    }
}
