import Foundation
import Combine

import Foundation
import Combine
import SwiftUI

class UserSettings: ObservableObject {
    @AppStorage("minThreshold") var minThreshold: Int = 0
    @AppStorage("maxThreshold") var maxThreshold: Int = 100
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
    }
    
    func getTargetRange(for date: Date) -> (min: Int, max: Int) {
        if let activeRule = timeRules.first(where: { $0.isActive(at: date) }) {
            return (activeRule.targetMin, activeRule.targetMax)
        }
        return (minThreshold, maxThreshold)
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
