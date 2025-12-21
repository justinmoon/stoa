import SwiftUI

/// Renders a SplitTree recursively with resizable dividers.
struct SplitTreeView: View {
    @ObservedObject var controller: StoaWindowController
    @EnvironmentObject var ghosttyApp: GhosttyApp
    
    var body: some View {
        Group {
            if let root = controller.splitTree.root {
                NodeView(node: root, controller: controller)
            } else {
                Color.black
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

/// Renders a single node in the split tree.
struct NodeView: View {
    let node: SplitTree.Node
    @ObservedObject var controller: StoaWindowController
    
    var body: some View {
        switch node {
        case .leaf(let pane):
            PaneView(pane: pane, controller: controller)
        case .split(let split):
            SplitNodeView(split: split, controller: controller)
        }
    }
}

/// Renders a split node with two children and a resizable divider.
struct SplitNodeView: View {
    let split: SplitTree.Node.Split
    @ObservedObject var controller: StoaWindowController
    @State private var ratio: CGFloat
    
    private let dividerSize: CGFloat = 1
    private let hitAreaSize: CGFloat = 8
    
    init(split: SplitTree.Node.Split, controller: StoaWindowController) {
        self.split = split
        self.controller = controller
        self._ratio = State(initialValue: CGFloat(split.ratio))
    }
    
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let leftRect = leftRect(for: size)
            let rightRect = rightRect(for: size, leftRect: leftRect)
            
            ZStack(alignment: .topLeading) {
                // Left/top child
                NodeView(node: split.left, controller: controller)
                    .frame(width: leftRect.width, height: leftRect.height)
                    .offset(x: leftRect.origin.x, y: leftRect.origin.y)
                
                // Right/bottom child
                NodeView(node: split.right, controller: controller)
                    .frame(width: rightRect.width, height: rightRect.height)
                    .offset(x: rightRect.origin.x, y: rightRect.origin.y)
                
                // Divider
                divider(for: size, leftRect: leftRect)
            }
        }
    }
    
    @ViewBuilder
    private func divider(for size: CGSize, leftRect: CGRect) -> some View {
        let isHorizontal = split.direction == .horizontal
        
        ZStack {
            // Invisible hit area
            Rectangle()
                .fill(Color.clear)
                .frame(
                    width: isHorizontal ? hitAreaSize : size.width,
                    height: isHorizontal ? size.height : hitAreaSize
                )
                .contentShape(Rectangle())
            
            // Visible divider
            Rectangle()
                .fill(Color.gray.opacity(0.5))
                .frame(
                    width: isHorizontal ? dividerSize : size.width,
                    height: isHorizontal ? size.height : dividerSize
                )
        }
        .offset(
            x: isHorizontal ? leftRect.width - hitAreaSize / 2 : 0,
            y: isHorizontal ? 0 : leftRect.height - hitAreaSize / 2
        )
        .gesture(dragGesture(size: size))
        .onHover { hovering in
            if hovering {
                if isHorizontal {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.resizeUpDown.push()
                }
            } else {
                NSCursor.pop()
            }
        }
    }
    
    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { gesture in
                let minRatio: CGFloat = 0.1
                let maxRatio: CGFloat = 0.9
                
                switch split.direction {
                case .horizontal:
                    let newRatio = gesture.location.x / size.width
                    ratio = min(max(minRatio, newRatio), maxRatio)
                case .vertical:
                    let newRatio = gesture.location.y / size.height
                    ratio = min(max(minRatio, newRatio), maxRatio)
                }
            }
    }
    
    private func leftRect(for size: CGSize) -> CGRect {
        switch split.direction {
        case .horizontal:
            let width = (size.width - dividerSize) * ratio
            return CGRect(x: 0, y: 0, width: width, height: size.height)
        case .vertical:
            let height = (size.height - dividerSize) * ratio
            return CGRect(x: 0, y: 0, width: size.width, height: height)
        }
    }
    
    private func rightRect(for size: CGSize, leftRect: CGRect) -> CGRect {
        switch split.direction {
        case .horizontal:
            let x = leftRect.width + dividerSize
            return CGRect(x: x, y: 0, width: size.width - x, height: size.height)
        case .vertical:
            let y = leftRect.height + dividerSize
            return CGRect(x: 0, y: y, width: size.width, height: size.height - y)
        }
    }
}

/// Renders a single pane with its terminal view.
struct PaneView: View {
    let pane: Pane
    @ObservedObject var controller: StoaWindowController
    @EnvironmentObject var ghosttyApp: GhosttyApp
    
    private var isFocused: Bool {
        controller.focusedPaneId == pane.id
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let terminalView = pane.view as? TerminalSurfaceView {
                    TerminalViewRepresentable(terminalView: terminalView, size: geo.size)
                } else {
                    Color.black
                }
                
                // Focus border
                if isFocused {
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(Color.blue, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
        }
        .background(Color.black)
        .contentShape(Rectangle())
        .onTapGesture {
            controller.focusPane(pane)
        }
    }
}
