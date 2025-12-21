import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var ghosttyApp: GhosttyApp!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the Ghostty app wrapper
        ghosttyApp = GhosttyApp()
        guard ghosttyApp.isReady else {
            print("Failed to initialize Ghostty")
            NSApp.terminate(nil)
            return
        }

        // Create the main window
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Stoa - Demo 1"
        window.center()

        // Create the terminal view
        let terminalView = TerminalSurfaceView(app: ghosttyApp.app!)
        
        // Host SwiftUI content
        let contentView = NSHostingView(rootView: 
            TerminalContainer(terminalView: terminalView)
                .environmentObject(ghosttyApp)
        )
        
        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)

        // Ensure terminal gets focus
        DispatchQueue.main.async {
            self.window.makeFirstResponder(terminalView)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
