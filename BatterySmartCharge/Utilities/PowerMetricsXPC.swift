import Foundation

// XPC Protocol for communication between app and privileged helper
@objc(PowerMetricsXPCProtocol)
protocol PowerMetricsXPCProtocol {
    func getPowerMetrics(reply: @escaping (Double, Double, Double, String) -> Void)
    // Returns: (cpuPower, gpuPower, combinedPower, thermalPressure)
}

// Helper identifier - must match the helper's bundle ID and launchd label
let kPowerMetricsHelperID = "com.smartcharge.powermetrics-helper"
