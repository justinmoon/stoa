import AppKit

class GhosttyApp: ObservableObject {
    private(set) var config: ghostty_config_t?
    private(set) var app: ghostty_app_t?
    
    var isReady: Bool { app != nil }

    init() {
        // Create configuration
        guard let cfg = ghostty_config_new() else {
            print("ghostty_config_new failed")
            return
        }
        
        // Load default config files
        ghostty_config_load_default_files(cfg)
        ghostty_config_finalize(cfg)
        self.config = cfg

        // Create runtime configuration
        var runtimeCfg = ghostty_runtime_config_s()
        runtimeCfg.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtimeCfg.supports_selection_clipboard = true
        runtimeCfg.wakeup_cb = { userdata in
            GhosttyApp.wakeup(userdata)
        }
        runtimeCfg.action_cb = { app, target, action in
            return true
        }
        runtimeCfg.read_clipboard_cb = { userdata, location, state in }
        runtimeCfg.confirm_read_clipboard_cb = { userdata, str, state, request in }
        runtimeCfg.write_clipboard_cb = { userdata, location, content, len, confirm in
            GhosttyApp.writeClipboard(userdata, content: content)
        }
        runtimeCfg.close_surface_cb = { userdata, processAlive in }

        // Create the app
        guard let ghosttyApp = ghostty_app_new(&runtimeCfg, cfg) else {
            print("ghostty_app_new failed")
            return
        }
        self.app = ghosttyApp

        // Set initial focus state
        ghostty_app_set_focus(ghosttyApp, NSApp.isActive)
    }

    deinit {
        if let app = app {
            ghostty_app_free(app)
        }
        if let config = config {
            ghostty_config_free(config)
        }
    }

    func tick() {
        guard let app = app else { return }
        ghostty_app_tick(app)
    }
    
    // MARK: - Static Callbacks
    
    static func wakeup(_ userdata: UnsafeMutableRawPointer?) {
        guard let userdata = userdata else { return }
        let app = Unmanaged<GhosttyApp>.fromOpaque(userdata).takeUnretainedValue()
        DispatchQueue.main.async {
            app.tick()
        }
    }
    
    static func writeClipboard(_ userdata: UnsafeMutableRawPointer?, content: UnsafePointer<ghostty_clipboard_content_s>?) {
        guard let content = content else { return }
        guard let data = content.pointee.data else { return }
        let str = String(cString: data)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(str, forType: .string)
    }
}
