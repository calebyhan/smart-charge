import Foundation

// PowerMetrics Helper - runs as root via SMJobBless
// Provides power metrics data to the main app via XPC

class PowerMetricsHelper: NSObject, NSXPCListenerDelegate, PowerMetricsXPCProtocol {
    private let listener: NSXPCListener

    override init() {
        self.listener = NSXPCListener(machServiceName: kPowerMetricsHelperID)
        super.init()
        self.listener.delegate = self
    }

    func run() {
        listener.resume()
        RunLoop.current.run()
    }

    // MARK: - NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: PowerMetricsXPCProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    // MARK: - PowerMetricsXPCProtocol

    func getPowerMetrics(reply: @escaping (Double, Double, Double, String) -> Void) {
        let metrics = fetchPowerMetrics()
        reply(metrics.cpuPower, metrics.gpuPower, metrics.combinedPower, metrics.thermalPressure)
    }

    // MARK: - Power Metrics Fetching

    private func fetchPowerMetrics() -> (cpuPower: Double, gpuPower: Double, combinedPower: Double, thermalPressure: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
        process.arguments = ["--samplers", "cpu_power,thermal", "-n", "1", "-i", "100"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return (0, 0, 0, "unknown")
            }

            return parseOutput(output)
        } catch {
            return (0, 0, 0, "error")
        }
    }

    private func parseOutput(_ output: String) -> (cpuPower: Double, gpuPower: Double, combinedPower: Double, thermalPressure: String) {
        var cpuPower = 0.0
        var gpuPower = 0.0
        var combinedPower = 0.0
        var thermalPressure = "nominal"

        let lines = output.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.contains("Combined Power") || trimmed.contains("Package Power") {
                if let watts = extractWatts(from: trimmed) {
                    combinedPower = watts
                }
            }

            if trimmed.hasPrefix("CPU Power:") {
                if let watts = extractWatts(from: trimmed) {
                    cpuPower = watts
                }
            }

            if trimmed.hasPrefix("GPU Power:") {
                if let watts = extractWatts(from: trimmed) {
                    gpuPower = watts
                }
            }

            if trimmed.contains("pressure level") {
                let levels = ["Nominal", "Moderate", "Heavy", "Trapping", "Sleeping"]
                for level in levels {
                    if trimmed.localizedCaseInsensitiveContains(level) {
                        thermalPressure = level.lowercased()
                        break
                    }
                }
            }
        }

        if combinedPower == 0 && (cpuPower > 0 || gpuPower > 0) {
            combinedPower = cpuPower + gpuPower
        }

        return (cpuPower, gpuPower, combinedPower, thermalPressure)
    }

    private func extractWatts(from line: String) -> Double? {
        // Match "123.45 W" or "123 mW"
        let patterns = [
            #"([\d.]+)\s*W\b"#,
            #"([\d.]+)\s*mW\b"#
        ]

        for (index, pattern) in patterns.enumerated() {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let range = Range(match.range(at: 1), in: line) {
                if let value = Double(line[range]) {
                    return index == 1 ? value / 1000.0 : value
                }
            }
        }
        return nil
    }
}

// XPC Protocol - must match the one in the main app
@objc(PowerMetricsXPCProtocol)
protocol PowerMetricsXPCProtocol {
    func getPowerMetrics(reply: @escaping (Double, Double, Double, String) -> Void)
}

let kPowerMetricsHelperID = "com.smartcharge.powermetrics-helper"

// Entry point
let helper = PowerMetricsHelper()
helper.run()
