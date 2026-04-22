import AppKit

class ProcessManager {
    static let shared = ProcessManager()
    private init() {}

    private let claudeBundleID = "com.anthropic.claudefordesktop"

    func quitClaude(then completion: @escaping () -> Void) {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == claudeBundleID
        }

        if running.isEmpty {
            killCLI()
            completion()
            return
        }

        for app in running { app.terminate() }

        // Poll until the desktop app is gone (max 4s), then kill CLI and proceed
        var attempts = 0
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            let still = NSWorkspace.shared.runningApplications.filter {
                $0.bundleIdentifier == self.claudeBundleID
            }
            attempts += 1
            if still.isEmpty || attempts >= 8 {
                timer.invalidate()
                for app in still { app.forceTerminate() }
                self.killCLI()
                completion()
            }
        }
    }

    func launchClaude() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: claudeBundleID)
              ?? URL(fileURLWithPath: "/Applications/Claude.app", isDirectory: true) as URL?
        else { return }
        NSWorkspace.shared.openApplication(
            at: url,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    private func killCLI() {
        let task = Process()
        task.launchPath = "/usr/bin/pkill"
        task.arguments  = ["-x", "claude"]
        try? task.run()
    }
}
