import Foundation

class PowerMetricsReader {
    static let shared = PowerMetricsReader()

    private var cachedData: PowerMetricsData?
    private var lastUpdate: Date?
    private let cacheInterval: TimeInterval = 0.5  // Reduced to 0.5s for faster updates

    private var useXPC = true  // Try XPC first, fall back to direct if running as root

    struct PowerMetricsData {
        var cpuPower: Double = 0
        var gpuPower: Double = 0
        var combinedPower: Double = 0
        var thermalPressure: String = "nominal"
    }

    init() {
        log("PowerMetrics: Initialized")
    }

    func readSystemPower() -> Double? {
        guard let data = getMetrics() else { return nil }
        return data.combinedPower > 0 ? data.combinedPower : nil
    }

    func readTemperature() -> Double? {
        // Temperature now comes from IORegistry in BatteryMonitor
        return nil
    }

    func readCPUPower() -> Double? {
        guard let data = getMetrics() else { return nil }
        return data.cpuPower > 0 ? data.cpuPower : nil
    }

    func readGPUPower() -> Double? {
        guard let data = getMetrics() else { return nil }
        return data.gpuPower > 0 ? data.gpuPower : nil
    }

    func readThermalPressure() -> String? {
        guard let data = getMetrics() else { return nil }
        return data.thermalPressure
    }

    private func getMetrics() -> PowerMetricsData? {
        // Return cached data if still valid
        if let cached = cachedData,
           let lastUpdate = lastUpdate,
           Date().timeIntervalSince(lastUpdate) < cacheInterval {
            return cached
        }

        // Fetch new data
        let data = fetchPowerMetrics()
        if let data = data {
            cachedData = data
            lastUpdate = Date()
        }
        return data
    }

    private func fetchPowerMetrics() -> PowerMetricsData? {
        // Try XPC connection to privileged helper first
        if useXPC {
            var result: PowerMetricsData?
            let semaphore = DispatchSemaphore(value: 0)

            log("PowerMetrics: Requesting data via XPC...")
            PrivilegedHelperManager.shared.getPowerMetrics { cpu, gpu, combined, thermal in
                if combined > 0 || cpu > 0 || gpu > 0 {
                    var data = PowerMetricsData()
                    data.cpuPower = cpu
                    data.gpuPower = gpu
                    data.combinedPower = combined
                    data.thermalPressure = thermal
                    result = data
                }
                semaphore.signal()
            }

            // Wait up to 1 second for XPC response (reduced for faster toggling)
            let timeout = semaphore.wait(timeout: .now() + 1.0)
            if timeout == .success {
                if let data = result {
                    log("PowerMetrics: Got valid data via XPC - \(data.combinedPower)W")
                    return data
                } else {
                    log("PowerMetrics: XPC returned but no valid data")
                }
            } else {
                log("PowerMetrics: XPC timeout - falling back to direct")
            }
        }

        // Fall back to direct execution (works if running as root)
        log("PowerMetrics: Trying direct powermetrics execution")
        return fetchDirectPowerMetrics()
    }

    private func fetchDirectPowerMetrics() -> PowerMetricsData? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
        process.arguments = [
            "--samplers", "cpu_power,thermal",
            "-n", "1",
            "-i", "100"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return nil
            }

            return parseOutput(output)
        } catch {
            // Silent fail - expected without sudo
            return nil
        }
    }

    private func parseOutput(_ output: String) -> PowerMetricsData {
        var data = PowerMetricsData()

        let lines = output.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.contains("Combined Power") || trimmed.contains("Package Power") {
                if let watts = extractWatts(from: trimmed) {
                    data.combinedPower = watts
                }
            }

            if trimmed.hasPrefix("CPU Power:") {
                if let watts = extractWatts(from: trimmed) {
                    data.cpuPower = watts
                }
            }

            if trimmed.hasPrefix("GPU Power:") {
                if let watts = extractWatts(from: trimmed) {
                    data.gpuPower = watts
                }
            }

            if trimmed.contains("pressure level") {
                if let pressure = extractThermalPressure(from: trimmed) {
                    data.thermalPressure = pressure
                }
            }
        }

        if data.combinedPower == 0 && (data.cpuPower > 0 || data.gpuPower > 0) {
            data.combinedPower = data.cpuPower + data.gpuPower
        }

        if data.combinedPower > 0 {
            log("PowerMetrics: power=\(data.combinedPower)W")
        }

        return data
    }

    private func extractWatts(from line: String) -> Double? {
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

    private func extractThermalPressure(from line: String) -> String? {
        let pressureLevels = ["Nominal", "Moderate", "Heavy", "Trapping", "Sleeping"]
        for level in pressureLevels {
            if line.localizedCaseInsensitiveContains(level) {
                return level.lowercased()
            }
        }
        return nil
    }

    private func log(_ msg: String) {
        // Silent - no logging
    }
}
