import SwiftUI
import StoaKit

/// Renders a SplitTree recursively with resizable dividers.
struct SplitTreeView: View {
    @ObservedObject var controller: StoaWindowController
    
    var body: some View {
        ZStack {
            Group {
                if let root = controller.splitTree.root {
                    NodeView(node: root, controller: controller)
                } else {
                    Color.black
                }
            }
            if controller.isShowingHelp {
                HotkeyHelpOverlay(isPresented: Binding(
                    get: { controller.isShowingHelp },
                    set: { controller.isShowingHelp = $0 }
                ))
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

/// Renders a single pane with a selector, terminal, browser, or editor.
struct PaneView: View {
    @ObservedObject var pane: Pane
    @ObservedObject var controller: StoaWindowController
    
    private var isFocused: Bool {
        controller.focusedPaneId == pane.id
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                switch pane.content {
                case .unselected:
                    PaneTypeSelectionView(selection: pane.pendingSelection)
                case .terminal, .webview, .chromium:
                    PaneAppViewRepresentable(pane: pane, size: geo.size, controller: controller)
                case .terminal, .webview, .chromium:
                    PaneAppViewRepresentable(pane: pane, size: geo.size, controller: controller)
                case .editor(let url):
                    PaneEditorViewRepresentable(pane: pane, url: url, controller: controller)
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

struct PaneTypeSelectionView: View {
    let selection: PaneTypeSelection
    
    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                ForEach(PaneTypeSelection.allCases, id: \.rawValue) { option in
                    PaneTypeSelectionOption(
                        title: "\(option.title) [\(option.hotkey)]",
                        isSelected: selection == option
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PaneTypeSelectionOption: View {
    let title: String
    let isSelected: Bool
    
    var body: some View {
        Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(isSelected ? .black : .white)
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.white : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(isSelected ? 0.0 : 0.6), lineWidth: 1)
                    )
            )
    }
}

private struct HotkeyHelpOverlay: View {
    @Binding var isPresented: Bool

    private struct HotkeyItem: Identifiable {
        let id = UUID()
        let keys: String
        let action: String
    }

    private struct HotkeySection: Identifiable {
        let id = UUID()
        let title: String
        let items: [HotkeyItem]
    }

    private let sections: [HotkeySection] = [
        HotkeySection(title: "Layout", items: [
            HotkeyItem(keys: "Cmd+\\", action: "Split horizontally"),
            HotkeyItem(keys: "Cmd+-", action: "Split vertically"),
            HotkeyItem(keys: "Cmd+W", action: "Close pane")
        ]),
        HotkeySection(title: "Focus", items: [
            HotkeyItem(keys: "Cmd+H", action: "Focus left"),
            HotkeyItem(keys: "Cmd+J", action: "Focus down"),
            HotkeyItem(keys: "Cmd+K", action: "Focus up"),
            HotkeyItem(keys: "Cmd+L", action: "Focus right")
        ]),
        HotkeySection(title: "Browser", items: [
            HotkeyItem(keys: "Cmd+Shift+W", action: "Split WebKit"),
            HotkeyItem(keys: "Cmd+Shift+L", action: "Open address bar")
        ]),
        HotkeySection(title: "Pane Selection", items: [
            HotkeyItem(keys: "J/K or Up/Down", action: "Cycle pane type"),
            HotkeyItem(keys: "C / W / T / E", action: "Pick Chromium / WebKit / Terminal / Editor"),
            HotkeyItem(keys: "Enter", action: "Confirm selection")
        ]),
        HotkeySection(title: "Help", items: [
            HotkeyItem(keys: "Cmd+/", action: "Toggle help"),
            HotkeyItem(keys: "Esc", action: "Close help")
        ])
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            VStack(alignment: .leading, spacing: 16) {
                Text("Stoa Hotkeys")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)

                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                        ForEach(section.items) { item in
                            HStack(alignment: .top, spacing: 12) {
                                Text(item.keys)
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .frame(width: 150, alignment: .leading)
                                Text(item.action)
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                    }
                }
            }
            .padding(24)
            .background(Color.black.opacity(0.9))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .padding(32)
        }
    }
}

/// NSViewRepresentable for app panes - stores app reference in pane model
struct PaneAppViewRepresentable: NSViewRepresentable {
    let pane: Pane
    let size: CGSize
    let controller: StoaWindowController
    
    func makeNSView(context: Context) -> PaneAppContainerView {
        let container = PaneAppContainerView()
        container.updateApp(pane: pane, controller: controller, size: size)
        return container
    }
    
    func updateNSView(_ container: PaneAppContainerView, context: Context) {
        container.updateApp(pane: pane, controller: controller, size: size)
    }
}

final class PaneAppContainerView: NSView {
    private weak var currentApp: StoaApp?
    
    func updateApp(pane: Pane, controller: StoaWindowController, size: CGSize) {
        let app = controller.ensureApp(for: pane, size: size)
        if currentApp !== app {
            subviews.forEach { $0.removeFromSuperview() }
            if let appView = app?.view {
                appView.frame = bounds
                appView.autoresizingMask = [.width, .height]
                addSubview(appView)
            }
            currentApp = app
        } else if let appView = app?.view {
            appView.frame = bounds
        }
    }
    
    override func layout() {
        super.layout()
        currentApp?.view.frame = bounds
    }
}

/// NSViewRepresentable for editor panes - stores view reference in pane model
struct PaneEditorViewRepresentable: NSViewRepresentable {
    let pane: Pane
    let url: URL
    let controller: StoaWindowController

    func makeNSView(context: Context) -> EditorHostView {
        if let existingView = pane.view as? EditorHostView {
            controller.attachEditorSession(for: pane, hostView: existingView, url: url)
            return existingView
        }

        let hostView = EditorHostView()
        pane.view = hostView
        controller.attachEditorSession(for: pane, hostView: hostView, url: url)
        return hostView
    }

    func updateNSView(_ hostView: EditorHostView, context: Context) {
        controller.updateEditorSessionFrame(for: pane)
    }
}
