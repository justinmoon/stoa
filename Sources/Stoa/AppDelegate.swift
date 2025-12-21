import AppKit
import SwiftUI
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var ghosttyApp: GhosttyApp?
    var windowController: StoaWindowController?
    let mode: DemoMode
    
    init(mode: DemoMode) {
        self.mode = mode
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the main window
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        
        switch mode {
        case .terminal:
            setupTerminalMode()
            window.makeKeyAndOrderFront(nil)
        case .webview(let url):
            setupWebViewMode(url: url)
            window.makeKeyAndOrderFront(nil)
        case .split:
            setupSplitMode()
            window.makeKeyAndOrderFront(nil)
        case .dynamic:
            setupDynamicMode()
        }
    }
    
    private func setupTerminalMode() {
        window.title = "Stoa - Demo 1"
        
        // Create the Ghostty app wrapper
        ghosttyApp = GhosttyApp()
        guard let ghosttyApp = ghosttyApp, ghosttyApp.isReady else {
            print("Failed to initialize Ghostty")
            NSApp.terminate(nil)
            return
        }

        // Create the terminal view
        let terminalView = TerminalSurfaceView(app: ghosttyApp.app!)
        
        // Host SwiftUI content
        let contentView = NSHostingView(rootView: 
            TerminalContainer(terminalView: terminalView)
                .environmentObject(ghosttyApp)
        )
        
        window.contentView = contentView

        // Ensure terminal gets focus
        DispatchQueue.main.async {
            self.window.makeFirstResponder(terminalView)
        }
    }
    
    private func setupWebViewMode(url: URL) {
        window.title = "Stoa - Demo 2"
        
        // Host SwiftUI content with WebView
        let contentView = NSHostingView(rootView: WebViewContainer(url: url))
        window.contentView = contentView
        
        // Find the WKWebView and make it first responder
        DispatchQueue.main.async {
            if let webView = self.findWebView(in: self.window.contentView) {
                self.window.makeFirstResponder(webView)
            }
        }
    }
    
    private func setupSplitMode() {
        window.title = "Stoa - Demo 3"
        
        // Create the Ghostty app wrapper
        ghosttyApp = GhosttyApp()
        guard let ghosttyApp = ghosttyApp, ghosttyApp.isReady else {
            print("Failed to initialize Ghostty")
            NSApp.terminate(nil)
            return
        }
        
        // Create two terminal views
        let leftTerminal = TerminalSurfaceView(app: ghosttyApp.app!)
        let rightTerminal = TerminalSurfaceView(app: ghosttyApp.app!)
        
        // Host SwiftUI content with split terminals
        let contentView = NSHostingView(rootView:
            SplitTerminalContainer(leftTerminal: leftTerminal, rightTerminal: rightTerminal)
                .environmentObject(ghosttyApp)
        )
        
        window.contentView = contentView
        
        // Focus the left terminal initially
        DispatchQueue.main.async {
            self.window.makeFirstResponder(leftTerminal)
        }
    }
    
    private func setupDynamicMode() {
        // Create the Ghostty app wrapper
        ghosttyApp = GhosttyApp()
        guard let ghosttyApp = ghosttyApp, ghosttyApp.isReady else {
            print("Failed to initialize Ghostty")
            NSApp.terminate(nil)
            return
        }
        
        // Create the window controller (it manages its own window)
        windowController = StoaWindowController(ghosttyApp: ghosttyApp)
        windowController?.showWindow(nil)
        
        // Focus the initial terminal
        DispatchQueue.main.async {
            if let pane = self.windowController?.focusedPane,
               let view = pane.view {
                self.windowController?.window?.makeFirstResponder(view)
            }
        }
    }
    
    private func findWebView(in view: NSView?) -> WKWebView? {
        guard let view = view else { return nil }
        if let webView = view as? WKWebView {
            return webView
        }
        for subview in view.subviews {
            if let webView = findWebView(in: subview) {
                return webView
            }
        }
        return nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
