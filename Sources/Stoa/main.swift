// Stoa - Tiling Window Manager for AI-driven Development

import AppKit
import StoaCEF

let cefExitCode = stoa_cef_execute_process(Int32(CommandLine.argc), CommandLine.unsafeArgv)
if cefExitCode >= 0 {
    exit(cefExitCode)
}

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
