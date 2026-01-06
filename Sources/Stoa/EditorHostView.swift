import AppKit
import StoaKit

final class EditorHostView: NSView, StoaApp {
    static var appType: String { "editor" }

    var onLayout: (() -> Void)?
    var onEvent: ((StoaAppEvent) -> Void)?
    var shouldInterceptKey: ((NSEvent) -> Bool)?

    private let fileURL: URL
    private var session: EditorEmbeddedSession?

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init(frame: .zero)
        do {
            session = try EditorEmbeddedSession(fileURL: fileURL, hostView: self)
        } catch {
            print("Failed to launch editor: \(error)")
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    func destroy() {
        session?.shutdown()
        session = nil
    }

    func focus() {
        session?.focus()
        window?.makeFirstResponder(self)
    }

    func setText(_ text: String) -> Bool {
        session?.setText(text) ?? false
    }

    func save() -> Bool {
        session?.save() ?? false
    }

    func matches(fileURL: URL) -> Bool {
        self.fileURL == fileURL
    }

    override func layout() {
        super.layout()
        onLayout?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onLayout?()
    }
}
