import Foundation

class ChargingAlgorithm {

    // Pure function to determine the next action
    static func determineAction(
        battery: BatteryState,
        settings: UserSettings,
        currentDate: Date = Date()
    ) -> ChargingAction {

        // 1. Safety Checks (Prioritize these above all)
        if battery.temperature >= settings.tempSafetyCutoff {
            return .forceStop
        }
        
        if battery.temperature >= settings.tempPauseThreshold {
            return .rest // Pause to cool down
        }
        
        // 2. Hard Boundaries
        // If explicitly below absolute min, charge immediately
        if battery.percent < settings.minThreshold {
            return .chargeActive
        }
        
        // If explicitly above absolute max, stop charging
        if battery.percent >= settings.maxThreshold {
            return .rest
        }
        
        // 3. Time-based Target Range
        let (targetMin, targetMax) = settings.getTargetRange(for: currentDate)
        
        // 4. Algorithm Logic
        
        // Case A: Battery is below the target minimum
        if battery.percent < targetMin {
            // If power draw is heavy, we need active charging to catch up
            if battery.powerDraw >= settings.heavyUsageThreshold {
                return .chargeActive
            }
            // Otherwise, normal charging is fine
            return .chargeNormal
        }
        
        // Case B: Battery is within the target range (targetMin...targetMax)
        if battery.percent >= targetMin && battery.percent < targetMax {
            // Strategy: Maintain level based on usage
            
            // If heavy usage, charge actively to prevent drain
            if battery.powerDraw >= settings.heavyUsageThreshold {
                // Only charge if we aren't dangerously close to top of range
                return battery.percent < (targetMax - 2) ? .chargeActive : .chargeTrickle
            }
            
            // If medium/light usage
            if battery.powerDraw >= settings.lightUsageThreshold {
                // If we are comfortably within range, maintain via trickle
                return .chargeTrickle
            }
            
            // If light usage, we can rest mostly, maybe trickle if near bottom
            return battery.percent < (targetMin + 5) ? .chargeTrickle : .rest
        }
        
        // Case C: Battery is above target max (but below Hard Max from step 2)
        // We should drain down to target
        return .rest
    }
}
