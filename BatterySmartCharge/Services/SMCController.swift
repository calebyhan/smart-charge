import Foundation

class SMCController {
    static let shared = SMCController()

    private let batteryCLIPath = "/usr/local/bin/battery"

    // Semaphore to prevent concurrent CLI calls (battery CLI has internal daemon conflicts)
    private let commandSemaphore = DispatchSemaphore(value: 1)
    private var lastCommandTime: Date = .distantPast
    private let minCommandInterval: TimeInterval = 1.0 // Minimum 1 second between CLI calls

    enum SMCError: Error {
        case cliNotFound
        case executionFailed(String)
        case outputParsingFailed
        case timeout
    }

    // Check if the battery CLI is installed and accessible
    var isCLIAvailable: Bool {
        return FileManager.default.fileExists(atPath: batteryCLIPath)
    }

    /// Permanently removes the battery CLI's background daemon to prevent conflicts with SmartCharge.
    /// The battery CLI runs its own LaunchAgent that fights with our charging commands, causing oscillation.
    func disableBatteryDaemon() {
        let plistPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/battery.plist")

        guard FileManager.default.fileExists(atPath: plistPath.path) else {
            print("✅ No battery daemon plist found - no conflict expected")
            return
        }

        print("⚠️ Found battery CLI daemon at \(plistPath.path) - removing permanently")

        // Unload the daemon first
        let unloadTask = Process()
        unloadTask.launchPath = "/bin/launchctl"
        unloadTask.arguments = ["unload", plistPath.path]

        do {
            try unloadTask.run()
            unloadTask.waitUntilExit()
        } catch {
            print("⚠️ Failed to unload battery daemon: \(error)")
        }

        // Delete the plist to prevent it from being loaded again
        do {
            try FileManager.default.removeItem(at: plistPath)
            print("✅ Battery daemon plist removed permanently")
        } catch {
            print("⚠️ Failed to remove battery daemon plist: \(error)")
        }

        // Run 'battery maintain stop' to ensure any running maintain process is stopped
        if isCLIAvailable {
            let stopTask = Process()
            stopTask.launchPath = "/usr/bin/sudo"
            stopTask.arguments = [batteryCLIPath, "maintain", "stop"]

            let pipe = Pipe()
            stopTask.standardOutput = pipe
            stopTask.standardError = pipe

            do {
                try stopTask.run()

                // Wait with timeout
                var waited = 0.0
                while stopTask.isRunning && waited < 5.0 {
                    Thread.sleep(forTimeInterval: 0.1)
                    waited += 0.1
                }

                if stopTask.isRunning {
                    stopTask.terminate()
                }

                print("✅ Battery maintain stopped")
            } catch {
                print("⚠️ Failed to stop battery maintain: \(error)")
            }
        }

        // Remove the maintain.percentage file which can cause oscillation if set to invalid values
        let maintainFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".battery/maintain.percentage")
        if FileManager.default.fileExists(atPath: maintainFile.path) {
            do {
                try FileManager.default.removeItem(at: maintainFile)
                print("✅ Removed battery maintain.percentage file")
            } catch {
                print("⚠️ Failed to remove maintain.percentage: \(error)")
            }
        }
    }
    
    func enableCharging() async throws {
        try await runBatteryCommand(["charging", "on"])
    }

    // Synchronous version for use during app termination
    func enableChargingSync() throws {
        try runBatteryCommandSync(["charging", "on"])
    }

    func disableCharging() async throws {
        try await runBatteryCommand(["charging", "off"])
    }

    func maintain(percentage: Int) async throws {
        // Validating percentage range
        let target = max(0, min(100, percentage))
        try await runBatteryCommand(["maintain", String(target)])
    }

    // Verify charging state via CLI status check
    // Note: This may fail if battery CLI requires sudo and app doesn't have privileges
    func verifyChargingState() async -> (enabled: Bool, status: String)? {
        guard isCLIAvailable else { return nil }

        let task = Process()
        task.launchPath = "/usr/bin/sudo"
        task.arguments = [batteryCLIPath, "status"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()

            var timeWaited = 0.0
            while task.isRunning && timeWaited < 3.0 {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                timeWaited += 0.1
            }

            if task.isRunning {
                task.terminate()
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Check if sudo failed
            if output.contains("sudo: a terminal is required") || output.contains("password") {
                // Gracefully skip verification - rely on IOKit monitoring instead
                return nil
            }

            // Parse output: "Battery at 80% (charge; remaining), 12.234V, smc charging enabled"
            let smcEnabled = output.contains("smc charging enabled")
            return (enabled: smcEnabled, status: output)
        } catch {
            return nil
        }
    }
    
    private func runBatteryCommand(_ args: [String]) async throws {
        try runBatteryCommandSync(args)
    }

    private func runBatteryCommandSync(_ args: [String]) throws {
        guard isCLIAvailable else {
            throw SMCError.cliNotFound
        }

        // Acquire semaphore to prevent concurrent CLI calls (max 5 second wait)
        let timeout = DispatchTime.now() + .seconds(5)
        guard commandSemaphore.wait(timeout: timeout) == .success else {
            print("❌ SMC command timeout: another command is running")
            throw SMCError.timeout
        }

        defer {
            commandSemaphore.signal()
        }

        // Enforce minimum interval between commands to avoid CLI daemon conflicts
        let now = Date()
        let timeSinceLastCommand = now.timeIntervalSince(lastCommandTime)
        if timeSinceLastCommand < minCommandInterval {
            let sleepTime = minCommandInterval - timeSinceLastCommand
            print("⏱️  Waiting \(Int(sleepTime * 1000))ms before next SMC command (avoiding CLI daemon conflict)")
            Thread.sleep(forTimeInterval: sleepTime)
        }

        lastCommandTime = Date()

        // Execute battery CLI command with timeout (using sudo for passwordless execution)
        let task = Process()
        task.launchPath = "/usr/bin/sudo"
        task.arguments = [batteryCLIPath] + args

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        // Add timeout to prevent hanging
        let commandString = args.joined(separator: " ")
        print("🔧 Executing: sudo battery \(commandString)")

        do {
            try task.run()

            // Wait with timeout (10 seconds max)
            var timeWaited = 0.0
            let pollInterval = 0.1
            let maxWait = 10.0

            while task.isRunning && timeWaited < maxWait {
                Thread.sleep(forTimeInterval: pollInterval)
                timeWaited += pollInterval
            }

            if task.isRunning {
                task.terminate()
                throw SMCError.executionFailed("Command timed out after \(Int(maxWait))s")
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if task.terminationStatus != 0 {
                print("❌ Battery CLI failed (exit \(task.terminationStatus)): \(output.prefix(200))")
                throw SMCError.executionFailed(output)
            }

            print("✅ Battery CLI succeeded")
        } catch {
            print("❌ Battery CLI error: \(error.localizedDescription)")
            throw SMCError.executionFailed(error.localizedDescription)
        }
    }
}
