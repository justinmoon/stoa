// Stoa - Tiling Window Manager for AI-driven Development
// Demo 1: Single Terminal Window - Proves: libghostty integration works
// Demo 2: Single WebView Window - Proves: WebView bridge works
// Demo 3: Static Split (Two Terminals) - Proves: Multiple libghostty surfaces work
// Demo 4: Dynamic Splits (Terminals Only) - Proves: Split tree logic works

import AppKit
import Foundation
import SwiftUI

enum DemoMode {
    case terminal
    case webview(URL)
    case split
    case dynamic
}

// Parse command-line arguments
func parseArgs() -> DemoMode {
    let args = CommandLine.arguments
    
    // Check for --dynamic flag (Demo 4)
    if args.contains("--dynamic") {
        return .dynamic
    }
    
    // Check for --split flag (Demo 3)
    if args.contains("--split") {
        return .split
    }
    
    // Check for --url flag
    if let urlIndex = args.firstIndex(of: "--url"), urlIndex + 1 < args.count {
        let urlString = args[urlIndex + 1]
        if let url = URL(string: urlString) {
            return .webview(url)
        } else {
            print("Invalid URL: \(urlString)")
            exit(1)
        }
    }
    
    // Check for --webview flag (uses default URL)
    if args.contains("--webview") {
        return .webview(URL(string: "https://github.com")!)
    }
    
    // Default to terminal mode
    return .terminal
}

let demoMode = parseArgs()

// Initialize Ghostty for terminal modes
switch demoMode {
case .terminal, .split, .dynamic:
    if ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != GHOSTTY_SUCCESS {
        print("ghostty_init failed")
        exit(1)
    }
case .webview:
    break
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate(mode: demoMode)
app.delegate = delegate
app.activate(ignoringOtherApps: true)
app.run()
