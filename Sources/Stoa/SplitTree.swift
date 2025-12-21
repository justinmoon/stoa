import AppKit

/// SplitTree represents a tree of panes that can be divided.
/// Adapted from Ghostty's SplitTree for Stoa.
struct SplitTree {
    let root: Node?
    
    indirect enum Node: Codable {
        case leaf(pane: Pane)
        case split(Split)
        
        struct Split: Equatable, Codable {
            let direction: Direction
            var ratio: Double
            let left: Node
            let right: Node
            
            static func == (lhs: Split, rhs: Split) -> Bool {
                lhs.direction == rhs.direction &&
                lhs.ratio == rhs.ratio &&
                lhs.left == rhs.left &&
                lhs.right == rhs.right
            }
        }
    }
    
    enum Direction: Codable {
        case horizontal // left | right
        case vertical   // top / bottom
    }
    
    enum SplitError: Error {
        case paneNotFound
    }
    
    enum NewDirection {
        case left, right, up, down
    }
    
    enum FocusDirection {
        case left, right, up, down
    }
}

// MARK: - SplitTree Core

extension SplitTree {
    var isEmpty: Bool { root == nil }
    
    init() {
        self.root = nil
    }
    
    init(pane: Pane) {
        self.root = .leaf(pane: pane)
    }
    
    /// Insert a new pane at the given pane by creating a split in the given direction.
    func insert(pane: Pane, at target: Pane, direction: NewDirection) throws -> Self {
        guard let root else { throw SplitError.paneNotFound }
        return SplitTree(root: try root.insert(pane: pane, at: target, direction: direction))
    }
    
    /// Remove a pane from the tree.
    func remove(_ target: Pane) -> Self {
        guard let root else { return self }
        let targetNode = Node.leaf(pane: target)
        if root == targetNode {
            return SplitTree(root: nil)
        }
        return SplitTree(root: root.remove(targetNode))
    }
    
    /// Find the pane to focus when navigating in a direction from the current pane.
    func focusTarget(from current: Pane, direction: FocusDirection) -> Pane? {
        guard let root else { return nil }
        let currentNode = Node.leaf(pane: current)
        guard root.contains(currentNode) else { return nil }
        
        let spatial = root.spatial()
        let spatialDir: Spatial.Direction = switch direction {
            case .left: .left
            case .right: .right
            case .up: .up
            case .down: .down
        }
        
        let slots = spatial.slots(in: spatialDir, from: currentNode)
        guard let firstSlot = slots.first else { return nil }
        
        // Find the leaf closest in the direction
        switch firstSlot.node {
        case .leaf(let pane):
            return pane
        case .split:
            // Get the appropriate leaf from the split
            return switch direction {
            case .left, .up: firstSlot.node.rightmostLeaf()
            case .right, .down: firstSlot.node.leftmostLeaf()
            }
        }
    }
    
    /// Update the ratio of a split containing the given pane.
    func updateRatio(for pane: Pane, ratio: Double) -> Self {
        guard let root else { return self }
        let node = Node.leaf(pane: pane)
        guard let newRoot = root.updateParentRatio(for: node, ratio: ratio) else {
            return self
        }
        return SplitTree(root: newRoot)
    }
    
    /// Get all panes in the tree.
    var panes: [Pane] {
        root?.leaves() ?? []
    }
    
    /// Find a pane by ID.
    func find(id: UUID) -> Pane? {
        panes.first { $0.id == id }
    }
}

// MARK: - SplitTree.Node

extension SplitTree.Node {
    typealias Node = SplitTree.Node
    typealias Direction = SplitTree.Direction
    typealias NewDirection = SplitTree.NewDirection
    typealias SplitError = SplitTree.SplitError
    
    func contains(_ target: Node) -> Bool {
        if self == target { return true }
        switch self {
        case .leaf: return false
        case .split(let split):
            return split.left.contains(target) || split.right.contains(target)
        }
    }
    
    func insert(pane: Pane, at target: Pane, direction: NewDirection) throws -> Self {
        guard contains(.leaf(pane: target)) else {
            throw SplitError.paneNotFound
        }
        
        let splitDirection: Direction
        let newPaneOnLeft: Bool
        switch direction {
        case .left:
            splitDirection = .horizontal
            newPaneOnLeft = true
        case .right:
            splitDirection = .horizontal
            newPaneOnLeft = false
        case .up:
            splitDirection = .vertical
            newPaneOnLeft = true
        case .down:
            splitDirection = .vertical
            newPaneOnLeft = false
        }
        
        return replacePane(target, with: .split(.init(
            direction: splitDirection,
            ratio: 0.5,
            left: newPaneOnLeft ? .leaf(pane: pane) : .leaf(pane: target),
            right: newPaneOnLeft ? .leaf(pane: target) : .leaf(pane: pane)
        )))
    }
    
    private func replacePane(_ target: Pane, with newNode: Node) -> Node {
        switch self {
        case .leaf(let pane):
            if pane.id == target.id {
                return newNode
            }
            return self
        case .split(let split):
            return .split(.init(
                direction: split.direction,
                ratio: split.ratio,
                left: split.left.replacePane(target, with: newNode),
                right: split.right.replacePane(target, with: newNode)
            ))
        }
    }
    
    func remove(_ target: Node) -> Node? {
        if self == target { return nil }
        
        switch self {
        case .leaf: return self
        case .split(let split):
            let newLeft = split.left.remove(target)
            let newRight = split.right.remove(target)
            
            if newLeft == nil && newRight == nil { return nil }
            if newLeft == nil { return newRight }
            if newRight == nil { return newLeft }
            
            return .split(.init(
                direction: split.direction,
                ratio: split.ratio,
                left: newLeft!,
                right: newRight!
            ))
        }
    }
    
    func leaves() -> [Pane] {
        switch self {
        case .leaf(let pane): return [pane]
        case .split(let split):
            return split.left.leaves() + split.right.leaves()
        }
    }
    
    func leftmostLeaf() -> Pane {
        switch self {
        case .leaf(let pane): return pane
        case .split(let split): return split.left.leftmostLeaf()
        }
    }
    
    func rightmostLeaf() -> Pane {
        switch self {
        case .leaf(let pane): return pane
        case .split(let split): return split.right.rightmostLeaf()
        }
    }
    
    func updateParentRatio(for target: Node, ratio: Double) -> Node? {
        switch self {
        case .leaf: return nil
        case .split(let split):
            // Check if target is a direct child
            if split.left == target || split.right == target {
                return .split(.init(
                    direction: split.direction,
                    ratio: ratio,
                    left: split.left,
                    right: split.right
                ))
            }
            // Recurse
            if let newLeft = split.left.updateParentRatio(for: target, ratio: ratio) {
                return .split(.init(
                    direction: split.direction,
                    ratio: split.ratio,
                    left: newLeft,
                    right: split.right
                ))
            }
            if let newRight = split.right.updateParentRatio(for: target, ratio: ratio) {
                return .split(.init(
                    direction: split.direction,
                    ratio: split.ratio,
                    left: split.left,
                    right: newRight
                ))
            }
            return nil
        }
    }
}

// MARK: - Node Equatable

extension SplitTree.Node: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.leaf(p1), .leaf(p2)):
            return p1.id == p2.id
        case let (.split(s1), .split(s2)):
            return s1 == s2
        default:
            return false
        }
    }
}

// MARK: - Spatial Navigation

extension SplitTree {
    struct Spatial {
        let slots: [Slot]
        
        struct Slot {
            let node: Node
            let bounds: CGRect
        }
        
        enum Direction {
            case left, right, up, down
        }
    }
}

extension SplitTree.Node {
    func spatial(within bounds: CGSize? = nil) -> SplitTree.Spatial {
        let width: Double
        let height: Double
        if let bounds {
            width = bounds.width
            height = bounds.height
        } else {
            let (w, h) = dimensions()
            width = Double(w)
            height = Double(h)
        }
        
        let slots = spatialSlots(in: CGRect(x: 0, y: 0, width: width, height: height))
        return SplitTree.Spatial(slots: slots)
    }
    
    private func dimensions() -> (width: UInt, height: UInt) {
        switch self {
        case .leaf: return (1, 1)
        case .split(let split):
            let leftDim = split.left.dimensions()
            let rightDim = split.right.dimensions()
            
            switch split.direction {
            case .horizontal:
                return (leftDim.width + rightDim.width, max(leftDim.height, rightDim.height))
            case .vertical:
                return (max(leftDim.width, rightDim.width), leftDim.height + rightDim.height)
            }
        }
    }
    
    private func spatialSlots(in bounds: CGRect) -> [SplitTree.Spatial.Slot] {
        switch self {
        case .leaf:
            return [.init(node: self, bounds: bounds)]
        case .split(let split):
            let leftBounds: CGRect
            let rightBounds: CGRect
            
            switch split.direction {
            case .horizontal:
                let splitX = bounds.minX + bounds.width * split.ratio
                leftBounds = CGRect(x: bounds.minX, y: bounds.minY,
                                   width: bounds.width * split.ratio, height: bounds.height)
                rightBounds = CGRect(x: splitX, y: bounds.minY,
                                    width: bounds.width * (1 - split.ratio), height: bounds.height)
            case .vertical:
                let splitY = bounds.minY + bounds.height * split.ratio
                leftBounds = CGRect(x: bounds.minX, y: bounds.minY,
                                   width: bounds.width, height: bounds.height * split.ratio)
                rightBounds = CGRect(x: bounds.minX, y: splitY,
                                    width: bounds.width, height: bounds.height * (1 - split.ratio))
            }
            
            var slots: [SplitTree.Spatial.Slot] = [.init(node: self, bounds: bounds)]
            slots += split.left.spatialSlots(in: leftBounds)
            slots += split.right.spatialSlots(in: rightBounds)
            return slots
        }
    }
}

extension SplitTree.Spatial {
    func slots(in direction: Direction, from referenceNode: SplitTree.Node) -> [Slot] {
        guard let refSlot = slots.first(where: { $0.node == referenceNode }) else { return [] }
        
        func distance(from rect1: CGRect, to rect2: CGRect) -> Double {
            let dx = rect2.minX - rect1.minX
            let dy = rect2.minY - rect1.minY
            return sqrt(dx * dx + dy * dy)
        }
        
        return switch direction {
        case .left:
            slots.filter { $0.node != referenceNode && $0.bounds.maxX <= refSlot.bounds.minX }
                .sorted { distance(from: refSlot.bounds, to: $0.bounds) < distance(from: refSlot.bounds, to: $1.bounds) }
        case .right:
            slots.filter { $0.node != referenceNode && $0.bounds.minX >= refSlot.bounds.maxX }
                .sorted { distance(from: refSlot.bounds, to: $0.bounds) < distance(from: refSlot.bounds, to: $1.bounds) }
        case .up:
            slots.filter { $0.node != referenceNode && $0.bounds.maxY <= refSlot.bounds.minY }
                .sorted { distance(from: refSlot.bounds, to: $0.bounds) < distance(from: refSlot.bounds, to: $1.bounds) }
        case .down:
            slots.filter { $0.node != referenceNode && $0.bounds.minY >= refSlot.bounds.maxY }
                .sorted { distance(from: refSlot.bounds, to: $0.bounds) < distance(from: refSlot.bounds, to: $1.bounds) }
        }
    }
}

// MARK: - Codable

extension SplitTree: Codable {
    enum CodingKeys: String, CodingKey {
        case root
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        root = try container.decodeIfPresent(Node.self, forKey: .root)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(root, forKey: .root)
    }
}

extension SplitTree.Node {
    enum CodingKeys: String, CodingKey {
        case pane, split
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.pane) {
            let pane = try container.decode(Pane.self, forKey: .pane)
            self = .leaf(pane: pane)
        } else if container.contains(.split) {
            let split = try container.decode(Split.self, forKey: .split)
            self = .split(split)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid node"))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .leaf(let pane):
            try container.encode(pane, forKey: .pane)
        case .split(let split):
            try container.encode(split, forKey: .split)
        }
    }
}
