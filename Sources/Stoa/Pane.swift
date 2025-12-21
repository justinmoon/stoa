import AppKit

/// A pane is a single content area in the split tree.
/// For Demo 4, panes only contain terminals.
class Pane: Identifiable, Codable {
    let id: UUID
    
    /// The actual NSView backing this pane (not Codable, recreated on restore)
    weak var view: NSView?
    
    init(id: UUID = UUID()) {
        self.id = id
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
    }
}
