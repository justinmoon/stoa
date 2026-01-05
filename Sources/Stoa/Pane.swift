import AppKit
import Combine

/// Content type for a pane - selector, terminal, or webview
enum PaneContent: Codable, Equatable {
    case unselected
    case terminal
    case webview(url: URL)
}

enum PaneTypeSelection: Int, CaseIterable {
    case browser
    case terminal
    
    var title: String {
        switch self {
        case .browser:
            return "Browser"
        case .terminal:
            return "Terminal"
        }
    }
    
    var hotkey: String {
        switch self {
        case .browser:
            return "b"
        case .terminal:
            return "t"
        }
    }
    
    func next() -> PaneTypeSelection {
        let all = Self.allCases
        let index = (rawValue + 1) % all.count
        return all[index]
    }
    
    func previous() -> PaneTypeSelection {
        let all = Self.allCases
        let index = (rawValue - 1 + all.count) % all.count
        return all[index]
    }
}

/// A pane is a single content area in the split tree.
class Pane: Identifiable, Codable, ObservableObject {
    let id: UUID
    @Published var content: PaneContent
    @Published var pendingSelection: PaneTypeSelection = .terminal
    
    /// The actual NSView backing this pane (not Codable, recreated on restore)
    weak var view: NSView?
    
    init(id: UUID = UUID(), content: PaneContent = .unselected) {
        self.id = id
        self.content = content
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id
        case content
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decodeIfPresent(PaneContent.self, forKey: .content) ?? .terminal
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
    }
}
