import AppKit

/// Content type for a pane - either terminal or webview
enum PaneContent: Codable, Equatable {
    case terminal
    case webview(url: URL)
}

/// A pane is a single content area in the split tree.
class Pane: Identifiable, Codable {
    let id: UUID
    var content: PaneContent
    
    /// The actual NSView backing this pane (not Codable, recreated on restore)
    weak var view: NSView?
    
    init(id: UUID = UUID(), content: PaneContent = .terminal) {
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
