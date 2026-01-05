import AppKit

enum EditorEmbeddedError: Error, CustomStringConvertible {
    case initFailed
    case createFailed

    var description: String {
        switch self {
        case .initFailed:
            return "failed to initialize embedded editor"
        case .createFailed:
            return "failed to create embedded editor"
        }
    }
}

final class EditorEmbeddedSession {
    private let paneId: UUID
    private let fileURL: URL
    private weak var hostView: EditorHostView?
    private var handle: OpaquePointer?

    var isReady: Bool { handle != nil }

    init(paneId: UUID, fileURL: URL, hostView: EditorHostView) throws {
        self.paneId = paneId
        self.fileURL = fileURL
        try attach(hostView: hostView)
    }

    func attach(hostView: EditorHostView) throws {
        self.hostView = hostView
        hostView.onLayout = { [weak self] in
            self?.updateFrame()
            try? self?.ensureEditor()
        }

        try ensureEditor()
    }

    func focus() {
        guard let handle else { return }
        _ = zed_editor_focus(handle)
    }

    func setText(_ text: String) -> Bool {
        guard let handle else { return false }
        return text.withCString { zed_editor_set_text(handle, $0) }
    }

    func save() -> Bool {
        guard let handle else { return false }
        return zed_editor_save(handle)
    }

    func shutdown() {
        guard let handle else { return }
        zed_editor_destroy(handle)
        self.handle = nil
    }

    func updateFrame() {
        // Embedded editor view is autoresized by AppKit; no explicit resize needed yet.
    }

    private func ensureEditor() throws {
        guard handle == nil else { return }
        guard let hostView, hostView.window != nil else { return }

        guard zed_embed_init() else {
            throw EditorEmbeddedError.initFailed
        }

        let viewPtr = Unmanaged.passUnretained(hostView).toOpaque()
        let editorHandle = fileURL.path.withCString { pathCString in
            zed_editor_create(viewPtr, pathCString)
        }

        guard let editorHandle else {
            throw EditorEmbeddedError.createFailed
        }

        handle = editorHandle
    }
}
