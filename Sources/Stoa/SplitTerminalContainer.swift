import SwiftUI

struct SplitTerminalContainer: View {
    let leftTerminal: TerminalSurfaceView
    let rightTerminal: TerminalSurfaceView
    @EnvironmentObject var ghosttyApp: GhosttyApp
    
    var body: some View {
        SplitView(.horizontal) {
            TerminalContainer(terminalView: leftTerminal)
        } right: {
            TerminalContainer(terminalView: rightTerminal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
