import Foundation
import Combine
import SwiftUI

class UserSettings: ObservableObject {
    @AppStorage("minThreshold") var minThreshold: Int = 20
    @AppStorage("maxThreshold") var maxThreshold: Int = 80
    @AppStorage("lightUsageThreshold") var lightUsageThreshold: Double = 15.0
    @AppStorage("heavyUsageThreshold") var heavyUsageThreshold: Double = 30.0
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = true
    @AppStorage("useFahrenheit") var useFahrenheit: Bool = true

    @Published var timeRules: [TimeRule] = [] {
        didSet {
            saveTimeRules()
        }
    }

    // Temperature safety limits
    let tempPauseThreshold: Double = 38.0
    let tempResumeThreshold: Double = 35.0
    let tempSafetyCutoff: Double = 42.0

    init() {
        loadTimeRules()
        migrateDefaults()
    }

    /// Migrate existing users from old 0-100% defaults to new 20-80% defaults
    private func migrateDefaults() {
        let hasCustomized = UserDefaults.standard.bool(forKey: "hasCustomizedThresholds")
        if !hasCustomized {
            // Check if user has old defaults (0-100) and migrate them
            if minThreshold == 0 && maxThreshold == 100 {
                minThreshold = 20
                maxThreshold = 80
            }
            UserDefaults.standard.set(true, forKey: "hasCustomizedThresholds")
        }
    }
    
    func getTargetRange(for date: Date) -> (min: Int, max: Int) {
        if let activeRule = timeRules.first(where: { $0.isActive(at: date) }) {
            // Clamp rule ranges to hard boundaries
            let clampedMin = max(activeRule.targetMin, minThreshold)
            let clampedMax = min(activeRule.targetMax, maxThreshold)
            // Ensure min <= max
            return (clampedMin, max(clampedMin, clampedMax))
        }
        return (minThreshold, maxThreshold)
    }

    /// Get the currently active time rule, if any
    func getActiveRule(for date: Date) -> TimeRule? {
        return timeRules.first(where: { $0.isActive(at: date) })
    }

    /// Get all pairs of overlapping rules
    func getOverlappingRules() -> [(TimeRule, TimeRule)] {
        var overlaps: [(TimeRule, TimeRule)] = []
        for i in 0..<timeRules.count {
            for j in (i + 1)..<timeRules.count {
                if timeRules[i].overlaps(with: timeRules[j]) {
                    overlaps.append((timeRules[i], timeRules[j]))
                }
            }
        }
        return overlaps
    }

    private func saveTimeRules() {
        if let encoded = try? JSONEncoder().encode(timeRules) {
            UserDefaults.standard.set(encoded, forKey: "timeRules")
        }
    }
    
    private func loadTimeRules() {
        if let data = UserDefaults.standard.data(forKey: "timeRules"),
           let decoded = try? JSONDecoder().decode([TimeRule].self, from: data) {
            timeRules = decoded
        }
    }
}
