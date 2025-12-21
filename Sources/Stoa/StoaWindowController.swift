import AppKit
import SwiftUI

/// Main controller for Demo 4: manages split tree state, focus, and keybindings.
class StoaWindowController: NSWindowController, NSWindowDelegate, ObservableObject {
    @Published var splitTree: SplitTree
    @Published var focusedPaneId: UUID?
    
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
        window.title = "Stoa - Demo 4"
        window.center()
        
        super.init(window: window)
        window.delegate = self
        
        setupContentView()
        createTerminalView(for: initialPane)
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
    
    // MARK: - Terminal Management
    
    func createTerminalView(for pane: Pane) {
        guard let app = ghosttyApp.app else { return }
        let terminalView = TerminalSurfaceView(app: app)
        terminalView.onKeyDown = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
        pane.view = terminalView
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
        let newPane = Pane()
        
        do {
            splitTree = try splitTree.insert(pane: newPane, at: current, direction: .right)
            createTerminalView(for: newPane)
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
            createTerminalView(for: newPane)
            focusPane(newPane)
        } catch {
            print("Failed to split: \(error)")
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
        // Only handle Cmd+key combinations
        guard event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.shift) else { return false }
        
        let key = event.charactersIgnoringModifiers ?? ""
        let keyCode = event.keyCode
        
        // Debug: print key info
        print("Key: '\(key)' keyCode: \(keyCode) modifiers: \(event.modifierFlags.rawValue)")
        
        // keyCode 42 = backslash, keyCode 27 = minus
        switch keyCode {
        case 42:  // Backslash
            splitHorizontal()
            return true
        case 27:  // Minus
            splitVertical()
            return true
        case 13:  // W
            closePane()
            return true
        case 4:   // H
            focusPane(direction: .left)
            return true
        case 38:  // J
            focusPane(direction: .down)
            return true
        case 40:  // K
            focusPane(direction: .up)
            return true
        case 37:  // L
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
