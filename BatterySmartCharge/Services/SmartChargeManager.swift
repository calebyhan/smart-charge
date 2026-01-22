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
    private var overrideAction: ChargingAction? {
        didSet {
            // Persist override state for crash recovery
            if let override = overrideAction {
                UserDefaults.standard.set(override.rawValue, forKey: "overrideAction")
            } else {
                UserDefaults.standard.removeObject(forKey: "overrideAction")
            }
        }
    }

    // Expose override state for UI
    var isOverrideActive: Bool {
        return overrideAction != nil
    }

    // Expose Apple optimization detection for UI
    var isAppleOptimizationActive: Bool {
        return appleOptimizationDetected
    }

    private var lastActionChangeTime: Date = .distantPast
    private var retryCount: Int = 0
    private let maxRetries: Int = 5 // Increased from 3 to 5
    private let retryTimeout: TimeInterval = 30 // seconds before retry
    private let stuckResetTimeout: TimeInterval = 300 // 5 minutes - reset after this long

    // Notification debouncing
    private var lastTempWarningTime: Date = .distantPast
    private var lastTempSafetyTime: Date = .distantPast
    private var lastStuckNotificationTime: Date = .distantPast
    private let tempNotificationInterval: TimeInterval = 60 // Only notify once per minute
    private let stuckNotificationInterval: TimeInterval = 300 // Only notify once per 5 minutes

    // Stuck state tracking (separate from action changes)
    private var stuckStateDetectedTime: Date?
    private var lastHardwareState: (isCharging: Bool, timestamp: Date)?
    private var retriesExhausted: Bool = false

    // Apple Optimized Battery Charging detection
    private var appleOptimizationDetected: Bool = false
    private var appleOptimizationDetectedTime: Date?
    private let appleOptimizationDetectionThreshold: TimeInterval = 120 // 2 minutes stuck at ~80%

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
        restoreOverrideState()
        setupSubscriptions()
        setupWakeNotification()

        // Force initial evaluation after subscriptions are set up
        // This ensures we apply the charging algorithm immediately on app launch
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.evaluateState(battery: self.monitor.state)
        }
    }

    private func restoreOverrideState() {
        // Restore override state from UserDefaults for crash recovery
        if let savedRawValue = UserDefaults.standard.string(forKey: "overrideAction"),
           let action = ChargingAction(rawValue: savedRawValue) {
            overrideAction = action
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
            // Re-apply charging state - SMC state may have been reset during sleep
            self?.reapplyChargingState()
        }
    }

    private func reapplyChargingState() {
        // Clear lastAction to force re-execution of SMC command
        // This ensures we re-apply the charging state after wake from sleep
        // or any other event that might have reset SMC state
        lastAction = nil
        retryCount = 0
        lastActionChangeTime = Date()
        evaluateState(battery: monitor.state)
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

        // Clear Apple optimization detection - user explicitly wants control
        if appleOptimizationDetected {
            print("🔧 User override - clearing Apple optimization detection")
            appleOptimizationDetected = false
            appleOptimizationDetectedTime = nil
            stuckStateDetectedTime = nil
            retryCount = 0
        }

        evaluateState(battery: monitor.state)
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
            // Only log if action changed or in debug mode
            if action != lastAction {
                print("🔧 Override active: \(action.description)")
            }
            // Auto-disable override if we reached full charge
            // Clear immediately (atomic operation, no race condition)
            if override == .chargeActive && battery.percent >= 100 {
                overrideAction = nil
                print("✅ Override cleared: battery reached 100%")
                // Re-evaluate with override cleared to get algorithm action
                action = ChargingAlgorithm.determineAction(
                    battery: battery,
                    settings: settings
                )
                print("📊 Algorithm decided: \(action.description)")
                // Optionally notify user
                // notifications.sendNotification(title: "Charge Complete", body: "Reached 100%")
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

        // Execute Action only if changed OR if hardware state doesn't match expected
        let shouldBeCharging = (action == .chargeActive || action == .chargeNormal)
        let hardwareMismatch = battery.isPluggedIn && (shouldBeCharging != battery.isCharging)

        // Check if we should clear Apple optimization detection
        if appleOptimizationDetected {
            let shouldClearAppleMode =
                battery.isCharging || // Apple started charging naturally
                battery.percent < 78 || // Battery drained below Apple's threshold
                battery.percent >= 95 || // Apple finished charging to high level
                !battery.isPluggedIn // User unplugged

            if shouldClearAppleMode {
                print("✅ Apple optimization completed or conditions changed - resuming SmartCharge control")
                print("   └─ Battery: \(battery.percent)%, Charging: \(battery.isCharging), Plugged: \(battery.isPluggedIn)")
                appleOptimizationDetected = false
                appleOptimizationDetectedTime = nil
                stuckStateDetectedTime = nil
                retryCount = 0
                retriesExhausted = false
            }
        }

        // Track stuck states separately from action changes
        if hardwareMismatch && !appleOptimizationDetected {
            // Mismatch detected - start tracking if not already
            if stuckStateDetectedTime == nil {
                stuckStateDetectedTime = Date()
                retriesExhausted = false
                print("⚠️ Hardware mismatch detected: want charging=\(shouldBeCharging), actual=\(battery.isCharging)")
            }

            let timeSinceStuck = Date().timeIntervalSince(stuckStateDetectedTime!)
            let shouldRetry = timeSinceStuck > retryTimeout && retryCount < maxRetries

            // Detect Apple's Optimized Battery Charging
            // Symptoms: stuck at ~80%, wanting to charge, hardware not charging
            if !appleOptimizationDetected &&
               battery.percent >= 78 && battery.percent <= 82 &&
               shouldBeCharging && !battery.isCharging &&
               timeSinceStuck > appleOptimizationDetectionThreshold {

                appleOptimizationDetected = true
                appleOptimizationDetectedTime = Date()
                print("🍎 Apple Optimized Battery Charging detected at \(battery.percent)%")
                print("   └─ Entering passive monitoring mode - will let Apple control charging")
                print("   └─ SmartCharge will resume control when Apple finishes or battery changes")

                // Notify user this is expected behavior
                notifications.sendNotification(
                    title: "Apple Battery Optimization Active",
                    body: "Detected macOS battery health management at \(battery.percent)%. SmartCharge will resume control when Apple's optimization completes."
                )

                // Don't retry anymore - let Apple work
                stuckStateDetectedTime = nil
                retryCount = 0
                retriesExhausted = false
            }

            // Check if we've been stuck for too long even after exhausting retries
            // (only if we haven't detected Apple optimization)
            if !appleOptimizationDetected && retryCount >= maxRetries && timeSinceStuck > stuckResetTimeout {
                // Been stuck for 5+ minutes after max retries - likely Apple's Optimized Battery Charging
                // Reset everything and notify user
                if !retriesExhausted {
                    retriesExhausted = true
                    let now = Date()
                    if now.timeIntervalSince(lastStuckNotificationTime) >= stuckNotificationInterval {
                        print("🚨 Retries exhausted and stuck for 5+ minutes - likely macOS interference")
                        print("💡 Suggestion: Check System Settings > Battery > Optimized Battery Charging")
                        notifications.sendNotification(
                            title: "Charging Control Issue",
                            body: "Unable to control charging at \(battery.percent)%. This may be due to macOS Optimized Battery Charging. Check System Settings > Battery if you want SmartCharge to have full control."
                        )
                        lastStuckNotificationTime = now
                    }
                }

                // Reset stuck state after notification to allow normal operation
                // Don't spam retries if macOS is preventing charging
                stuckStateDetectedTime = nil
                retryCount = 0
                retriesExhausted = false
            }

            if action != lastAction && !appleOptimizationDetected {
                // Action changed while stuck - execute new action but don't reset retry counter
                // Skip if Apple optimization detected (let Apple control it)
                print("🔄 Action changed while stuck: \(lastAction?.description ?? "nil") → \(action.description)")
                executeAction(action)
                if lastAction != nil {
                    notifications.notifyChargingStateChanged(to: action)
                }
                lastAction = action
            } else if shouldRetry && !appleOptimizationDetected {
                // Stuck in same state for too long - retry the SMC command
                // Skip if Apple optimization detected (let Apple control it)
                retryCount += 1
                stuckStateDetectedTime = Date() // Reset stuck timer for next retry
                executeAction(action)
                print("⚠️ Stuck state detected: retry \(retryCount)/\(maxRetries) after \(Int(timeSinceStuck))s")

                if retryCount >= maxRetries {
                    print("🔴 Max retries exhausted - will monitor for 5 minutes before resetting")
                    retriesExhausted = true
                }
            }
        } else if hardwareMismatch && appleOptimizationDetected {
            // In Apple optimization mode - just monitor, don't take action
            // The clearing logic above will handle resuming control
        } else {
            // No mismatch - reset stuck state tracking
            if stuckStateDetectedTime != nil {
                print("✅ Stuck state resolved after \(retryCount) retries")
            }
            stuckStateDetectedTime = nil
            retryCount = 0
            retriesExhausted = false

            if action != lastAction {
                // Action changed normally - execute it
                print("🔄 Action changed: \(lastAction?.description ?? "nil") → \(action.description)")
                executeAction(action)
                if lastAction != nil {
                    notifications.notifyChargingStateChanged(to: action)
                }
                lastAction = action
            }
        }

        // Safety Checks with notification debouncing
        let now = Date()
        if battery.temperature >= settings.tempSafetyCutoff {
            // Critical safety cutoff - always clear override
            overrideAction = nil
            // Debounce notification (max once per minute)
            if now.timeIntervalSince(lastTempSafetyTime) >= tempNotificationInterval {
                notifications.notifySafetyStop(temp: battery.temperature)
                lastTempSafetyTime = now
            }
        } else if battery.temperature >= settings.tempPauseThreshold && lastAction != .rest && lastAction != .forceStop {
            // High temp warning - debounce notification
            if now.timeIntervalSince(lastTempWarningTime) >= tempNotificationInterval {
                notifications.notifyHighTemperature(temp: battery.temperature)
                lastTempWarningTime = now
            }
        }
    }
    
    private func executeAction(_ action: ChargingAction) {
        Task {
            do {
                let shouldBeCharging: Bool
                print("⚡️ Executing action: \(action.description)")
                switch action {
                case .chargeActive:
                    try await smc.enableCharging()
                    shouldBeCharging = true
                    print("   └─ SMC: Charging ENABLED (active)")
                case .chargeNormal:
                    try await smc.enableCharging()
                    shouldBeCharging = true
                    print("   └─ SMC: Charging ENABLED (normal)")
                case .chargeTrickle:
                    // Trickle charging: disable charging to let battery rest/drain slightly
                    // The algorithm will re-enable when battery drops below threshold
                    // This is simpler than using the maintain daemon and avoids daemon conflicts
                    try await smc.disableCharging()
                    shouldBeCharging = false
                    print("   └─ SMC: Charging DISABLED (trickle)")
                case .rest, .forceStop:
                    try await smc.disableCharging()
                    shouldBeCharging = false
                    print("   └─ SMC: Charging DISABLED (rest/stop)")
                }

                // Poll for battery state changes after SMC command
                // Reduced from 25 to 15 iterations (3 seconds instead of 5)
                // Exit early if hardware state matches expectation
                for i in 0..<15 {
                    try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                    await MainActor.run {
                        self.monitor.updateBatteryState(force: true)
                    }

                    // Early exit if hardware state matches what we expect
                    let currentState = await MainActor.run { self.monitor.state }
                    if currentState.isPluggedIn && currentState.isCharging == shouldBeCharging {
                        print("   └─ ✅ Hardware state matched after \(i + 1) polls (\((i + 1) * 200)ms)")
                        break
                    }
                }
            } catch {
                print("   └─ ❌ SMC command failed: \(error)")
            }
        }
    }
}
