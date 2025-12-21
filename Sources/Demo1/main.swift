// Demo 1: Single Terminal Window
// Proves: libghostty integration works

import AppKit
import SwiftUI

// Initialize Ghostty
if ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != GHOSTTY_SUCCESS {
    print("ghostty_init failed")
    exit(1)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.activate(ignoringOtherApps: true)
app.run()
