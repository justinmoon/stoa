import AppKit
import WebKit

/// Custom WKWebView subclass that suppresses beeps for unhandled key events
class StoaWebView: WKWebView {
    private var currentZoomLevel: CGFloat = 1.0
    
    /// Callback for intercepting key events (for Stoa keybindings)
    var onKeyDown: ((NSEvent) -> Bool)?
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Let the menu system handle standard shortcuts like Cmd+Q
        if NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
            return true
        }
        
        // Let Stoa handle its keybindings first
        if let handler = onKeyDown, handler(event) {
            return true
        }
        
        // Handle zoom shortcuts
        if event.modifierFlags.contains(.command) {
            let chars = event.charactersIgnoringModifiers ?? ""
            
            switch chars {
            case "=", "+":
                handleZoomIn()
                return true
            case "-":
                handleZoomOut()
                return true
            case "0":
                handleZoomReset()
                return true
            default:
                break
            }
        }
        
        // Let super handle it, return true for command keys to prevent beep
        _ = super.performKeyEquivalent(with: event)
        return event.modifierFlags.contains(.command)
    }
    
    override func noResponder(for eventSelector: Selector) {
        // Do nothing - prevents the beep
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    // MARK: - Zoom Handling
    
    private func handleZoomIn() {
        currentZoomLevel *= 1.1
        applyZoom()
    }
    
    private func handleZoomOut() {
        currentZoomLevel /= 1.1
        applyZoom()
    }
    
    private func handleZoomReset() {
        currentZoomLevel = 1.0
        applyZoom()
    }
    
    private func applyZoom() {
        let script = "document.body.style.zoom = '\(currentZoomLevel)'"
        evaluateJavaScript(script, completionHandler: nil)
    }
}
