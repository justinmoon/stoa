import AppKit

public struct StoaAppConfig {
    public let id: UUID
    public let initialSize: NSSize
    public let scaleFactor: CGFloat
    public let initialData: [String: Any]?

    public init(
        id: UUID = UUID(),
        initialSize: NSSize = NSSize(width: 800, height: 600),
        scaleFactor: CGFloat = 2.0,
        initialData: [String: Any]? = nil
    ) {
        self.id = id
        self.initialSize = initialSize
        self.scaleFactor = scaleFactor
        self.initialData = initialData
    }
}

public enum StoaAppEvent {
    case requestClose
    case requestSplit(horizontal: Bool)
    case titleChanged(String)
    case bell
    case custom(name: String, data: Data?)
}

public protocol StoaApp: AnyObject {
    static var appType: String { get }
    var view: NSView { get }
    var onEvent: ((StoaAppEvent) -> Void)? { get set }
    var shouldInterceptKey: ((NSEvent) -> Bool)? { get set }
    func focus()
    func blur()
    func destroy()
}

public extension StoaApp where Self: NSView {
    var view: NSView { self }

    func focus() {
        window?.makeFirstResponder(self)
    }

    func blur() {
        if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
    }
}
