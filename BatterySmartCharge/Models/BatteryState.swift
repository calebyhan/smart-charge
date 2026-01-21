import Foundation

struct BatteryState {
    let percent: Int
    let isCharging: Bool
    let isPluggedIn: Bool
    let powerDraw: Double // in Watts (total system power)
    let cpuPower: Double // in Watts
    let gpuPower: Double // in Watts
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
        temperature: 0.0,
        health: 100,
        cycleCount: 0,
        timeRemaining: nil
    )
}
