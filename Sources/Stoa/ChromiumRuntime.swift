import Foundation
import StoaCEF

final class ChromiumRuntime {
    static let shared = ChromiumRuntime()

    private var isInitialized = false
    private var messageLoopTimer: Timer?

    private init() {}

    func ensureInitialized() -> Bool {
        if isInitialized {
            return true
        }

        guard let paths = resolveCEFPaths() else {
            debugLog("ChromiumRuntime: failed to resolve CEF paths")
            return false
        }

        let ok = stoa_cef_initialize(
            Int32(CommandLine.argc),
            CommandLine.unsafeArgv,
            paths.frameworkPath,
            paths.resourcesPath,
            paths.localesPath,
            paths.cachePath,
            Int32(paths.remoteDebugPort)
        )
        if ok {
            isInitialized = true
            startMessageLoop()
            debugLog("ChromiumRuntime: CEF initialized")
        }
        return ok
    }

    func shutdown() {
        guard isInitialized else { return }
        messageLoopTimer?.invalidate()
        messageLoopTimer = nil
        stoa_cef_shutdown()
        isInitialized = false
    }

    private func startMessageLoop() {
        messageLoopTimer?.invalidate()
        messageLoopTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            stoa_cef_do_message_loop_work()
        }
    }

    private struct CEFPaths {
        let frameworkPath: String
        let resourcesPath: String
        let localesPath: String
        let cachePath: String
        let remoteDebugPort: Int
    }

    private func resolveCEFPaths() -> CEFPaths? {
        let fileManager = FileManager.default
        let env = ProcessInfo.processInfo.environment

        let basePath: String
        if let override = env["STOA_CEF_DIR"] {
            basePath = override
        } else {
            basePath = fileManager.currentDirectoryPath + "/Libraries/CEF"
        }

        let bundleFrameworkPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Frameworks/Chromium Embedded Framework.framework")
            .path

        let frameworkCandidates = [
            bundleFrameworkPath,
            basePath + "/Chromium Embedded Framework.framework",
            basePath + "/Release/Chromium Embedded Framework.framework"
        ]

        guard let frameworkPath = frameworkCandidates.first(where: { fileManager.fileExists(atPath: $0) }) else {
            debugLog("ChromiumRuntime: framework path not found in \(frameworkCandidates)")
            return nil
        }

        let resourcesCandidates = [
            frameworkPath + "/Resources",
            basePath + "/Resources",
            basePath + "/Release/Resources"
        ]

        guard let resourcesPath = resourcesCandidates.first(where: { fileManager.fileExists(atPath: $0) }) else {
            debugLog("ChromiumRuntime: resources path not found in \(resourcesCandidates)")
            return nil
        }

        let localesCandidates = [
            resourcesPath + "/locales",
            resourcesPath,
            frameworkPath + "/Resources/locales",
            basePath + "/locales"
        ]

        guard let localesPath = localesCandidates.first(where: { fileManager.fileExists(atPath: $0) }) else {
            debugLog("ChromiumRuntime: locales path not found in \(localesCandidates)")
            return nil
        }

        let cacheURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/stoa/cef", isDirectory: true)
        try? fileManager.createDirectory(at: cacheURL, withIntermediateDirectories: true)

        let port = Int(env["STOA_CEF_REMOTE_DEBUG_PORT"] ?? "9222") ?? 9222

        return CEFPaths(
            frameworkPath: frameworkPath,
            resourcesPath: resourcesPath,
            localesPath: localesPath,
            cachePath: cacheURL.path,
            remoteDebugPort: port
        )
    }

    private func debugLog(_ message: String) {
        if ProcessInfo.processInfo.environment["STOA_CHROMIUM_DEBUG"] == "1" {
            NSLog("%@", message)
        }
    }
}
