import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var ghosttyApp: GhosttyApp?
    var windowController: StoaWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the Ghostty app wrapper
        ghosttyApp = GhosttyApp()
        guard let ghosttyApp = ghosttyApp, ghosttyApp.isReady else {
            print("Failed to initialize Ghostty")
            NSApp.terminate(nil)
            return
        }
        
        // Create and show the main window
        windowController = StoaWindowController(ghosttyApp: ghosttyApp)
        windowController?.showWindow(nil)
        
        // Bring app to foreground and focus the initial terminal
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let pane = self.windowController?.focusedPane,
               let view = pane.app?.view {
                self.windowController?.window?.makeFirstResponder(view)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        ChromiumRuntime.shared.shutdown()
    }
}
