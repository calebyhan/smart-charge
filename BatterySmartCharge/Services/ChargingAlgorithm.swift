import Foundation

class ChargingAlgorithm {

    /// Determines the next charging action based on battery state, settings, and previous action.
    /// Uses a 2-tier model (charge/rest) that matches actual hardware capabilities.
    ///
    /// - Parameters:
    ///   - battery: Current battery state from IOKit
    ///   - settings: User settings including thresholds and time rules
    ///   - lastAction: Previous action for hysteresis (prevents oscillation)
    ///   - currentDate: Current date for time-based rules
    /// - Returns: The charging action to execute
    static func determineAction(
        battery: BatteryState,
        settings: UserSettings,
        lastAction: ChargingAction?,
        currentDate: Date = Date()
    ) -> ChargingAction {

        // 1. Sensor Validation - fail safe if temperature reading is invalid
        if !battery.hasValidTemperature {
            return .rest
        }

        // 2. Safety Checks (highest priority)
        if battery.temperature >= settings.tempSafetyCutoff {
            return .forceStop
        }

        // Temperature check with hysteresis: if we were resting due to heat,
        // require cooldown to tempResumeThreshold before resuming
        let wasThrottled = (lastAction == .rest || lastAction == .forceStop)
        let resumeTemp = wasThrottled ? settings.tempResumeThreshold : settings.tempPauseThreshold

        if battery.temperature >= resumeTemp {
            return .rest
        }

        // 3. Unplugged Guard - no point trying to charge without power
        if !battery.isPluggedIn {
            return .rest
        }

        // 4. Hard Boundaries (absolute limits)
        if battery.percent < settings.minThreshold {
            return .chargeActive
        }

        if battery.percent >= settings.maxThreshold {
            return .rest
        }

        // 5. Target Range Logic with Hysteresis
        var (targetMin, targetMax) = settings.getTargetRange(for: currentDate)

        // 5a. Health-aware adjustment: narrow range for degraded batteries
        let healthAdjustment: Int
        if battery.health < 80 {
            healthAdjustment = 5  // Severely degraded: narrow by 5% each side
        } else if battery.health < 90 {
            healthAdjustment = 2  // Moderately degraded: narrow by 2%
        } else {
            healthAdjustment = 0
        }
        targetMin = min(targetMin + healthAdjustment, targetMax - 5)
        targetMax = max(targetMax - healthAdjustment, targetMin + 5)

        // 5b. Direction-aware hysteresis: adjust thresholds based on battery flow
        let isRising = battery.batteryPower > 0.5   // Charging at >0.5W
        let isFalling = battery.batteryPower < -0.5  // Discharging at >0.5W

        // If rising (charging), be more aggressive about stopping early
        // If falling (draining), be more conservative about starting charge
        let chargeThreshold = isRising ? targetMin + 2 : targetMin + 4
        let stopThreshold = isFalling ? targetMax - 1 : targetMax - 3

        // 5c. High cycle count: prefer rest at boundary (widen hysteresis band)
        let cycleBonus = battery.cycleCount > 500 ? 1 : 0

        // Below charge threshold: always charge
        if battery.percent < (chargeThreshold - cycleBonus) {
            return .chargeActive
        }

        // Above stop threshold: always rest
        if battery.percent >= (stopThreshold - cycleBonus) {
            return .rest
        }

        // Within hysteresis band: maintain current state to prevent oscillation
        // If we were charging, keep charging until we hit stopThreshold
        // If we were resting, keep resting until we hit chargeThreshold
        if lastAction == .chargeActive {
            return .chargeActive
        }

        return .rest
    }

    /// Returns a human-readable reason for the action decision
    static func actionReason(
        battery: BatteryState,
        settings: UserSettings,
        lastAction: ChargingAction?,
        currentDate: Date = Date()
    ) -> String {
        if !battery.hasValidTemperature {
            return "Temperature sensor unavailable"
        }

        if battery.temperature >= settings.tempSafetyCutoff {
            return "Safety: Temperature \(String(format: "%.1f", battery.temperature))°C exceeds cutoff"
        }

        let wasThrottled = (lastAction == .rest || lastAction == .forceStop)
        let resumeTemp = wasThrottled ? settings.tempResumeThreshold : settings.tempPauseThreshold

        if battery.temperature >= resumeTemp {
            return "Temperature \(String(format: "%.1f", battery.temperature))°C (cooling)"
        }

        if !battery.isPluggedIn {
            return "Not plugged in"
        }

        if battery.percent < settings.minThreshold {
            return "Below minimum (\(settings.minThreshold)%)"
        }

        if battery.percent >= settings.maxThreshold {
            return "Reached maximum (\(settings.maxThreshold)%)"
        }

        let (targetMin, targetMax) = settings.getTargetRange(for: currentDate)
        let chargeThreshold = targetMin + 3
        let stopThreshold = targetMax - 2

        if battery.percent < chargeThreshold {
            return "Below target threshold (\(chargeThreshold)%)"
        }

        if battery.percent >= stopThreshold {
            return "Reached target (\(stopThreshold)%)"
        }

        if lastAction == .chargeActive {
            return "Continuing to charge (hysteresis)"
        }

        return "Within target range (resting)"
    }
}
