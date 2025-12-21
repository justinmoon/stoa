import SwiftUI
import AppKit

struct TerminalContainer: View {
    let terminalView: TerminalSurfaceView
    @EnvironmentObject var ghosttyApp: GhosttyApp

    var body: some View {
        GeometryReader { geometry in
            TerminalViewRepresentable(terminalView: terminalView, size: geometry.size)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

struct TerminalViewRepresentable: NSViewRepresentable {
    let terminalView: TerminalSurfaceView
    let size: CGSize

    func makeNSView(context: Context) -> NSView {
        return terminalView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.frame = CGRect(origin: .zero, size: size)
    }
}
