// Stoa - Tiling Window Manager for AI-driven Development

import AppKit

// Initialize libghostty
if ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != GHOSTTY_SUCCESS {
    print("ghostty_init failed")
    exit(1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
