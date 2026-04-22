import AppKit

class ProcessManager {
    static let shared = ProcessManager()
    private init() {}

    private let claudeBundleID = "com.anthropic.claudefordesktop"

    func quitClaude(then completion: @escaping () -> Void) {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == claudeBundleID
        }

        guard !running.isEmpty else {
            killCLI()
            completion()
            return
        }

        for app in running { app.terminate() }

        // Poll until gone (max 4s), then force-kill and proceed
        var attempts = 0
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            let still = NSWorkspace.shared.runningApplications.filter {
                $0.bundleIdentifier == self.claudeBundleID
            }
            attempts += 1
            if still.isEmpty || attempts >= 8 {
                timer.invalidate()
                still.forEach { $0.forceTerminate() }
                self.killCLI()
                completion()
            }
        }
    }

    func launchClaude() {
        // Delay gives pkill time to fully reap CLI processes before the app relaunches
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments  = ["-a", "Claude"]
            try? task.run()
        }
    }

    private func killCLI() {
        let task = Process()
        task.launchPath = "/usr/bin/pkill"
        task.arguments  = ["-x", "claude"]
        try? task.run()
    }
}
