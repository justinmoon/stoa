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
               let view = pane.view ?? pane.app?.view {
                self.windowController?.window?.makeFirstResponder(view)
            }
        }

        if ProcessInfo.processInfo.environment["STOA_EDITOR_EMBED_TEST"] == "1" {
            runEditorEmbedTest()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        ChromiumRuntime.shared.shutdown()
    }

    private func runEditorEmbedTest() {
        guard let windowController = windowController else { return }
        guard let path = ProcessInfo.processInfo.environment["STOA_EDITOR_FILE"] else {
            fatalError("STOA_EDITOR_FILE must be set for embed test.")
        }

        let url = URL(fileURLWithPath: path)
        windowController.openEditorForTest(url: url)

        let maxAttempts = 40
        var attempts = 0
        let testText = "stoa-embedded-e2e"
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            attempts += 1
            guard let pane = windowController.focusedPane else { return }

            if windowController.setEditorText(for: pane, text: testText) {
                _ = windowController.saveEditor(for: pane)
                if let contents = try? String(contentsOf: url), contents == testText {
                    timer.invalidate()
                    exit(0)
                }
            }

            if attempts >= maxAttempts {
                timer.invalidate()
                fatalError("Editor embedding test failed: editor did not save the expected text.")
            }
        }
    }
}
