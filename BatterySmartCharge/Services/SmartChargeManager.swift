import Foundation
import Combine
import SwiftUI
import AppKit

class SmartChargeManager: ObservableObject {
    static let shared = SmartChargeManager()
    
    @Published var monitor = BatteryMonitor()
    @Published var settings = UserSettings()
    @Published var currentAction: ChargingAction = .rest
    
    @Published var historyPoints: [Double] = []
    @Published var historyEntries: [BatteryHistoryEntry] = []

    private let smc = SMCController.shared
    private let notifications = NotificationManager.shared
    private var cancellables = Set<AnyCancellable>()

    private var lastAction: ChargingAction?
    private var overrideAction: ChargingAction?

    // History tracking with timestamps
    private struct HistoryEntry {
        let timestamp: Date
        let percentage: Double
    }

    // Public struct for UI consumption
    struct BatteryHistoryEntry {
        let timestamp: Date
        let percentage: Double
    }

    private var historyWithTime: [HistoryEntry] = []
    private var lastHistorySave: Date = Date()

    // Limits - 288 points = 1 point every 5 mins for 24h
    private let maxHistoryPoints = 288
    private let historyInterval: TimeInterval = 5 * 60 // 5 minutes
    
    private init() {
        loadHistoryFromDefaults()
        setupSubscriptions()
        setupWakeNotification()

        // Force initial evaluation after subscriptions are set up
        // This ensures we apply the charging algorithm immediately on app launch
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.evaluateState(battery: self.monitor.state)
        }
    }
    
    private func setupSubscriptions() {
        // React to battery state changes or settings changes
        Publishers.CombineLatest(monitor.$state, settings.$timeRules)
            .sink { [weak self] state, _ in
                self?.evaluateState(battery: state)
                self?.updateHistory(battery: state)
            }
            .store(in: &cancellables)

        // Also react to simple threshold changes
        settings.objectWillChange
            .debounce(for: 0.5, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.evaluateState(battery: self.monitor.state)
            }
            .store(in: &cancellables)
    }

    private func setupWakeNotification() {
        // Listen for system wake from sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Immediately record battery level when system wakes up
            self?.recordBatteryOnWake()
        }
    }

    private func recordBatteryOnWake() {
        let battery = monitor.state
        let now = Date()

        // Force record a data point on wake, bypassing the interval check
        let entry = HistoryEntry(timestamp: now, percentage: Double(battery.percent))
        historyWithTime.append(entry)

        // Reset the last save time so normal recording can continue
        lastHistorySave = now

        // Remove entries older than 24 hours
        let cutoffTime = now.addingTimeInterval(-24 * 60 * 60)
        historyWithTime.removeAll { $0.timestamp < cutoffTime }

        // Enforce max count
        if historyWithTime.count > maxHistoryPoints {
            historyWithTime.removeFirst(historyWithTime.count - maxHistoryPoints)
        }

        // Update UI
        DispatchQueue.main.async {
            self.historyPoints = self.historyWithTime.map { $0.percentage }
            self.historyEntries = self.historyWithTime.map {
                BatteryHistoryEntry(timestamp: $0.timestamp, percentage: $0.percentage)
            }
        }

        // Persist
        saveHistoryToDefaults()
    }
    
    func startOverride(action: ChargingAction) {
        self.overrideAction = action
        evaluateState(battery: monitor.state)
        
        // Auto-clear override after 1 hour or when full (logic can be refined)
        // For now, simpler: user manually toggles or we just let it run.
        if action == .chargeActive {
            // If charging to full, maybe we want to clear it when it hits 100?
        }
    }
    
    func stopOverride() {
        self.overrideAction = nil
        evaluateState(battery: monitor.state)
    }
    
    private func updateHistory(battery: BatteryState) {
        let now = Date()

        // Only record if enough time has passed since last save
        guard now.timeIntervalSince(lastHistorySave) >= historyInterval else {
            return
        }

        lastHistorySave = now

        // Add new entry with timestamp
        let entry = HistoryEntry(timestamp: now, percentage: Double(battery.percent))
        historyWithTime.append(entry)

        // Remove entries older than 24 hours (sliding window)
        let cutoffTime = now.addingTimeInterval(-24 * 60 * 60)
        historyWithTime.removeAll { $0.timestamp < cutoffTime }

        // Also enforce max count (should be ~288 for 24h at 5min intervals)
        if historyWithTime.count > maxHistoryPoints {
            historyWithTime.removeFirst(historyWithTime.count - maxHistoryPoints)
        }

        // Update published array for UI
        DispatchQueue.main.async {
            self.historyPoints = self.historyWithTime.map { $0.percentage }
            self.historyEntries = self.historyWithTime.map {
                BatteryHistoryEntry(timestamp: $0.timestamp, percentage: $0.percentage)
            }
        }

        // Persist to UserDefaults
        saveHistoryToDefaults()
    }

    private func loadHistoryFromDefaults() {
        guard let data = UserDefaults.standard.data(forKey: "batteryHistory"),
              let decoded = try? JSONDecoder().decode([CodableHistoryEntry].self, from: data) else {
            return
        }

        let now = Date()
        let cutoffTime = now.addingTimeInterval(-24 * 60 * 60)

        // Convert and filter old entries
        historyWithTime = decoded
            .map { HistoryEntry(timestamp: $0.timestamp, percentage: $0.percentage) }
            .filter { $0.timestamp >= cutoffTime }

        // Update UI
        historyPoints = historyWithTime.map { $0.percentage }
        historyEntries = historyWithTime.map {
            BatteryHistoryEntry(timestamp: $0.timestamp, percentage: $0.percentage)
        }
    }

    private func saveHistoryToDefaults() {
        let codableEntries = historyWithTime.map {
            CodableHistoryEntry(timestamp: $0.timestamp, percentage: $0.percentage)
        }

        if let encoded = try? JSONEncoder().encode(codableEntries) {
            UserDefaults.standard.set(encoded, forKey: "batteryHistory")
        }
    }

    // Codable wrapper for persistence
    private struct CodableHistoryEntry: Codable {
        let timestamp: Date
        let percentage: Double
    }
    
    private func evaluateState(battery: BatteryState) {
        var action: ChargingAction

        if let override = overrideAction {
            action = override
            // Auto-disable override if we reached full charge
            if override == .chargeActive && battery.percent >= 100 {
                Task { @MainActor in
                    self.overrideAction = nil
                    // notifications.sendNotification(title: "Charge Complete", body: "Reached 100%")
                }
            }
        } else {
            action = ChargingAlgorithm.determineAction(
                battery: battery,
                settings: settings
            )
        }

        // Optimistic UI update - update immediately for instant feedback
        DispatchQueue.main.async {
            self.currentAction = action
            // Notify AppDelegate to update menu bar icon
            NotificationCenter.default.post(name: NSNotification.Name("BatteryStateDidChange"), object: nil)
        }

        // Execute Action only if changed
        if action != lastAction {
            executeAction(action)

            if lastAction != nil {
                notifications.notifyChargingStateChanged(to: action)
            }
            lastAction = action
        }

        // Safety Checks
        if battery.temperature >= settings.tempSafetyCutoff {
            notifications.notifySafetyStop(temp: battery.temperature)
            overrideAction = nil // Kill override for safety
        } else if battery.temperature >= settings.tempPauseThreshold && lastAction != .rest && lastAction != .forceStop {
            notifications.notifyHighTemperature(temp: battery.temperature)
        }
    }
    
    private func executeAction(_ action: ChargingAction) {
        Task {
            do {
                switch action {
                case .chargeActive:
                    try await smc.enableCharging()
                case .chargeNormal:
                    try await smc.enableCharging()
                case .chargeTrickle:
                    // Trickle charging: disable charging to let battery rest/drain slightly
                    // The algorithm will re-enable when battery drops below threshold
                    // This is simpler than using the maintain daemon and avoids daemon conflicts
                    try await smc.disableCharging()
                case .rest, .forceStop:
                    try await smc.disableCharging()
                }

                // Aggressively poll for battery state changes after SMC command
                // Poll every 200ms for the first 5 seconds to catch hardware changes quickly
                for i in 0..<25 {
                    try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                    await MainActor.run {
                        self.monitor.updateBatteryState(force: true)
                    }
                }
            } catch {
                // Silently handle SMC errors
            }
        }
    }
}
