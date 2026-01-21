import Foundation

class SMCController {
    static let shared = SMCController()
    
    private let batteryCLIPath = "/usr/local/bin/battery"
    
    enum SMCError: Error {
        case cliNotFound
        case executionFailed(String)
        case outputParsingFailed
    }
    
    // Check if the battery CLI is installed and accessible
    var isCLIAvailable: Bool {
        return FileManager.default.fileExists(atPath: batteryCLIPath)
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
    
    private func runBatteryCommand(_ args: [String]) async throws {
        try runBatteryCommandSync(args)
    }

    private func runBatteryCommandSync(_ args: [String]) throws {
        guard isCLIAvailable else {
            throw SMCError.cliNotFound
        }

        let task = Process()
        task.launchPath = batteryCLIPath
        task.arguments = args

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if task.terminationStatus != 0 {
                throw SMCError.executionFailed(output)
            }
        } catch {
            throw SMCError.executionFailed(error.localizedDescription)
        }
    }
}
