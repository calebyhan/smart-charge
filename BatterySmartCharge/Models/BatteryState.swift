import Foundation

struct BatteryState {
    let percent: Int
    let isCharging: Bool
    let isPluggedIn: Bool
    let powerDraw: Double // in Watts (TRUE total system power from battery/adapter, includes CPU, GPU, display, SSD, memory, etc.)
    let cpuPower: Double // in Watts (CPU only)
    let gpuPower: Double // in Watts (GPU only)
    let batteryPower: Double // in Watts (positive = charging, negative = discharging)
    let temperature: Double // in Celsius
    let health: Int
    let cycleCount: Int
    let timeRemaining: Int? // in minutes (nil if not calculable)

    static let empty = BatteryState(
        percent: 0,
        isCharging: false,
        isPluggedIn: false,
        powerDraw: 0.0,
        cpuPower: 0.0,
        gpuPower: 0.0,
        batteryPower: 0.0,
        temperature: -999.0,  // Sentinel value indicating sensor unavailable
        health: 100,
        cycleCount: 0,
        timeRemaining: nil
    )

    /// Whether the temperature reading is valid (not a sensor failure)
    var hasValidTemperature: Bool {
        temperature > -50 && temperature < 100
    }
}
