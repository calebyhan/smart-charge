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

    // Action execution tracking (prevent parallel executions)
    private var isExecutingAction: Bool = false
    private var pendingAction: ChargingAction? = nil

    // History tracking with timestamps
    private struct HistoryEntry {
        let timestamp: Date
        let percentage: Double
        let temperature: Double?
    }

    // Public struct for UI consumption
    struct BatteryHistoryEntry {
        let timestamp: Date
        let percentage: Double
        let temperature: Double?
    }

    private var historyWithTime: [HistoryEntry] = []
    private var lastHistorySave: Date = Date()

    // Limits - 288 points = 1 point every 5 mins for 24h
    private let maxHistoryPoints = 288
    private let historyInterval: TimeInterval = 5 * 60 // 5 minutes

    // Health history tracking (weekly snapshots)
    struct HealthHistoryEntry: Codable {
        let timestamp: Date
        let health: Int
        let cycleCount: Int
    }

    @Published var healthHistory: [HealthHistoryEntry] = []
    private let maxHealthHistoryWeeks = 52  // 1 year of data

    // Charging session log (action transitions with reasons)
    struct ChargingSessionEntry: Codable, Identifiable {
        let id: UUID
        let timestamp: Date
        let previousAction: ChargingAction?
        let newAction: ChargingAction
        let reason: String
        let batteryPercent: Int
        let temperature: Double?
    }

    @Published var sessionLog: [ChargingSessionEntry] = []
    private let maxSessionLogEntries = 100

    // Cycle tracking for "estimated cycles saved"
    struct CycleTrackingData: Codable {
        var totalChargePercentAdded: Double
        var trackingStartDate: Date
    }

    @Published var cycleTracking: CycleTrackingData = CycleTrackingData(totalChargePercentAdded: 0, trackingStartDate: Date())
    private var lastChargeStartPercent: Int?

    private init() {
        loadHistoryFromDefaults()
        loadHealthHistory()
        loadSessionLog()
        loadCycleTracking()
        restoreOverrideState()

        // Record initial health snapshot if this is first run or no data exists
        recordInitialHealthSnapshotIfNeeded()

        setupSubscriptions()
        setupWakeNotification()

        // Force initial evaluation after subscriptions are set up
        // This ensures we apply the charging algorithm immediately on app launch
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.evaluateState(battery: self.monitor.state)
            // Record initial session log entry to show startup state
            self.recordInitialSessionLogEntry()
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
                self?.checkAndRecordWeeklyHealth()
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
        // Force fresh battery state before re-evaluating
        monitor.updateBatteryState(force: true)

        // Small delay to let IOKit settle after wake
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            // Clear lastAction to force re-execution of SMC command
            self.lastAction = nil
            self.retryCount = 0
            self.lastActionChangeTime = Date()
            self.evaluateState(battery: self.monitor.state)
        }
    }

    private func recordBatteryOnWake() {
        let battery = monitor.state
        let now = Date()

        // Force record a data point on wake, bypassing the interval check
        let temp = battery.hasValidTemperature ? battery.temperature : nil
        let entry = HistoryEntry(timestamp: now, percentage: Double(battery.percent), temperature: temp)
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
                BatteryHistoryEntry(timestamp: $0.timestamp, percentage: $0.percentage, temperature: $0.temperature)
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

        // Add new entry with timestamp and temperature
        let temp = battery.hasValidTemperature ? battery.temperature : nil
        let entry = HistoryEntry(timestamp: now, percentage: Double(battery.percent), temperature: temp)
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
                BatteryHistoryEntry(timestamp: $0.timestamp, percentage: $0.percentage, temperature: $0.temperature)
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
            .map { HistoryEntry(timestamp: $0.timestamp, percentage: $0.percentage, temperature: $0.temperature) }
            .filter { $0.timestamp >= cutoffTime }

        // Update UI
        historyPoints = historyWithTime.map { $0.percentage }
        historyEntries = historyWithTime.map {
            BatteryHistoryEntry(timestamp: $0.timestamp, percentage: $0.percentage, temperature: $0.temperature)
        }
    }

    private func saveHistoryToDefaults() {
        let codableEntries = historyWithTime.map {
            CodableHistoryEntry(timestamp: $0.timestamp, percentage: $0.percentage, temperature: $0.temperature)
        }

        if let encoded = try? JSONEncoder().encode(codableEntries) {
            UserDefaults.standard.set(encoded, forKey: "batteryHistory")
        }
    }

    // Codable wrapper for persistence
    private struct CodableHistoryEntry: Codable {
        let timestamp: Date
        let percentage: Double
        let temperature: Double?  // Optional for backward compatibility
    }

    // MARK: - Health History

    private func loadHealthHistory() {
        guard let data = UserDefaults.standard.data(forKey: "healthHistory"),
              let decoded = try? JSONDecoder().decode([HealthHistoryEntry].self, from: data) else {
            return
        }
        healthHistory = decoded
    }

    private func saveHealthHistory() {
        if let encoded = try? JSONEncoder().encode(healthHistory) {
            UserDefaults.standard.set(encoded, forKey: "healthHistory")
        }
    }

    /// Record initial health snapshot on first run to populate chart immediately
    private func recordInitialHealthSnapshotIfNeeded() {
        // If no health history exists, record initial snapshot
        guard healthHistory.isEmpty else { return }

        let now = Date()
        let battery = monitor.state
        let entry = HealthHistoryEntry(
            timestamp: now,
            health: battery.health,
            cycleCount: battery.cycleCount
        )

        healthHistory.append(entry)
        saveHealthHistory()

        // Also set the week marker so weekly recording works correctly
        let calendar = Calendar.current
        let currentWeek = calendar.component(.weekOfYear, from: now)
        let currentYear = calendar.component(.year, from: now)
        UserDefaults.standard.set(currentWeek, forKey: "lastHealthRecordWeek")
        UserDefaults.standard.set(currentYear, forKey: "lastHealthRecordYear")
    }

    private func checkAndRecordWeeklyHealth() {
        let calendar = Calendar.current
        let now = Date()
        let currentWeek = calendar.component(.weekOfYear, from: now)
        let currentYear = calendar.component(.year, from: now)

        let lastRecordedWeek = UserDefaults.standard.integer(forKey: "lastHealthRecordWeek")
        let lastRecordedYear = UserDefaults.standard.integer(forKey: "lastHealthRecordYear")

        // Only record once per week
        guard currentWeek != lastRecordedWeek || currentYear != lastRecordedYear else { return }

        let battery = monitor.state
        let entry = HealthHistoryEntry(
            timestamp: now,
            health: battery.health,
            cycleCount: battery.cycleCount
        )

        healthHistory.append(entry)

        // Keep only last 52 weeks
        if healthHistory.count > maxHealthHistoryWeeks {
            healthHistory.removeFirst(healthHistory.count - maxHealthHistoryWeeks)
        }

        // Update UI on main thread
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }

        saveHealthHistory()

        UserDefaults.standard.set(currentWeek, forKey: "lastHealthRecordWeek")
        UserDefaults.standard.set(currentYear, forKey: "lastHealthRecordYear")
    }

    // MARK: - Session Log

    private func loadSessionLog() {
        guard let data = UserDefaults.standard.data(forKey: "chargingSessionLog"),
              let decoded = try? JSONDecoder().decode([ChargingSessionEntry].self, from: data) else {
            return
        }
        sessionLog = decoded
    }

    private func saveSessionLog() {
        if let encoded = try? JSONEncoder().encode(sessionLog) {
            UserDefaults.standard.set(encoded, forKey: "chargingSessionLog")
        }
    }

    /// Record initial session log entry on startup to show current state
    private func recordInitialSessionLogEntry() {
        // Only record if log is empty (first run)
        guard sessionLog.isEmpty else { return }

        let battery = monitor.state
        let action = currentAction
        let reason = "App started - initial state"

        let entry = ChargingSessionEntry(
            id: UUID(),
            timestamp: Date(),
            previousAction: nil,
            newAction: action,
            reason: reason,
            batteryPercent: battery.percent,
            temperature: battery.hasValidTemperature ? battery.temperature : nil
        )

        sessionLog.append(entry)
        saveSessionLog()

        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    private func recordSessionTransition(from previousAction: ChargingAction?, to newAction: ChargingAction, reason: String, battery: BatteryState) {
        let entry = ChargingSessionEntry(
            id: UUID(),
            timestamp: Date(),
            previousAction: previousAction,
            newAction: newAction,
            reason: reason,
            batteryPercent: battery.percent,
            temperature: battery.hasValidTemperature ? battery.temperature : nil
        )

        sessionLog.append(entry)

        // Keep only last N entries
        if sessionLog.count > maxSessionLogEntries {
            sessionLog.removeFirst(sessionLog.count - maxSessionLogEntries)
        }

        DispatchQueue.main.async {
            self.objectWillChange.send()
        }

        saveSessionLog()
    }

    // MARK: - Cycle Tracking

    private func loadCycleTracking() {
        guard let data = UserDefaults.standard.data(forKey: "cycleTracking"),
              let decoded = try? JSONDecoder().decode(CycleTrackingData.self, from: data) else {
            return
        }
        cycleTracking = decoded
    }

    private func saveCycleTracking() {
        if let encoded = try? JSONEncoder().encode(cycleTracking) {
            UserDefaults.standard.set(encoded, forKey: "cycleTracking")
        }
    }

    private func trackChargingStart(percent: Int) {
        lastChargeStartPercent = percent
    }

    private func trackChargingStop(percent: Int) {
        guard let startPercent = lastChargeStartPercent else { return }
        let chargeAdded = max(0, percent - startPercent)
        if chargeAdded > 0 {
            cycleTracking.totalChargePercentAdded += Double(chargeAdded)
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
            saveCycleTracking()
        }
        lastChargeStartPercent = nil
    }

    /// Estimated cycles saved compared to daily 0-100% charging
    var estimatedCyclesSaved: Double {
        let daysSinceStart = max(1, Date().timeIntervalSince(cycleTracking.trackingStartDate) / 86400)
        let hypotheticalCycles = daysSinceStart  // 1 full cycle per day if charging 0-100%
        let actualCycles = cycleTracking.totalChargePercentAdded / 100.0
        return max(0, hypotheticalCycles - actualCycles)
    }

    // MARK: - Predicted Time to Target

    /// Returns predicted minutes to reach target and the target percentage, or nil if not applicable
    func predictTimeToTarget() -> (minutes: Int, target: Int)? {
        let state = monitor.state
        let (_, targetMax) = settings.getTargetRange(for: Date())

        // Only predict when charging toward target
        guard state.isCharging && state.percent < targetMax else { return nil }
        guard state.batteryPower > 0.5 else { return nil }  // Minimum charge rate

        let remainingPercent = Double(targetMax - state.percent)

        // Estimate: batteryPower (W) / ~60Wh capacity = % per hour
        // Simplified: 1W charging ≈ 1.67% per hour for typical MacBook
        let percentPerHour = (state.batteryPower / 60.0) * 100.0
        guard percentPerHour > 0.1 else { return nil }

        let hoursToTarget = remainingPercent / percentPerHour
        let minutesToTarget = Int(hoursToTarget * 60)

        return (minutesToTarget, targetMax)
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
                    settings: settings,
                    lastAction: lastAction
                )
                print("📊 Algorithm decided: \(action.description)")
                // Optionally notify user
                // notifications.sendNotification(title: "Charge Complete", body: "Reached 100%")
            }
        } else {
            action = ChargingAlgorithm.determineAction(
                battery: battery,
                settings: settings,
                lastAction: lastAction
            )
        }

        // Optimistic UI update - update immediately for instant feedback
        DispatchQueue.main.async {
            self.currentAction = action
            // Notify AppDelegate to update menu bar icon
            NotificationCenter.default.post(name: NSNotification.Name("BatteryStateDidChange"), object: nil)
        }

        // Execute Action only if changed OR if hardware state doesn't match expected
        let shouldBeCharging = (action == .chargeActive)
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
                    let reason = overrideAction != nil ? "Manual override" :
                        ChargingAlgorithm.actionReason(battery: battery, settings: settings, lastAction: lastAction)
                    recordSessionTransition(from: lastAction, to: action, reason: reason, battery: battery)

                    // Track cycle throughput
                    if action == .chargeActive {
                        trackChargingStart(percent: battery.percent)
                    } else if lastAction == .chargeActive {
                        trackChargingStop(percent: battery.percent)
                    }
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
                    let reason = overrideAction != nil ? "Manual override" :
                        ChargingAlgorithm.actionReason(battery: battery, settings: settings, lastAction: lastAction)
                    recordSessionTransition(from: lastAction, to: action, reason: reason, battery: battery)

                    // Track cycle throughput
                    if action == .chargeActive {
                        trackChargingStart(percent: battery.percent)
                    } else if lastAction == .chargeActive {
                        trackChargingStop(percent: battery.percent)
                    }
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
        // Check if already executing - if so, queue the action
        if isExecutingAction {
            pendingAction = action
            print("⏸️  Action queued (another action in progress): \(action.description)")
            return
        }

        Task {
            await MainActor.run { isExecutingAction = true }

            do {
                let shouldBeCharging: Bool
                print("⚡️ Executing action: \(action.description)")
                switch action {
                case .chargeActive:
                    try await smc.enableCharging()
                    shouldBeCharging = true
                    print("   └─ SMC: Charging ENABLED")
                case .rest, .forceStop:
                    try await smc.disableCharging()
                    shouldBeCharging = false
                    print("   └─ SMC: Charging DISABLED")
                }

                // Wait for CLI to settle (daemon operations take time)
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

                // Poll for battery state changes after SMC command
                // Exit early if hardware state matches expectation
                for i in 0..<10 {
                    try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                    await MainActor.run { self.monitor.updateBatteryState(force: true) }

                    let state = await MainActor.run { self.monitor.state }
                    if state.isPluggedIn && state.isCharging == shouldBeCharging {
                        print("   └─ ✅ Hardware state matched after \(i + 1) polls (\((i + 1) * 200)ms + 1.5s settle)")
                        break
                    }
                }

                // Verify state via CLI as final check (skip if sudo required)
                if let verification = await smc.verifyChargingState() {
                    let expectedSMC = shouldBeCharging
                    let actualSMC = verification.enabled
                    if expectedSMC != actualSMC {
                        print("   └─ ⚠️ SMC verification mismatch: expected=\(expectedSMC), actual=\(actualSMC)")
                        print("   └─ CLI status: \(verification.status.prefix(100))")
                    } else {
                        print("   └─ ✅ SMC verification passed")
                    }
                }
            } catch {
                print("   └─ ❌ SMC command failed: \(error)")
            }

            // Mark execution complete and handle pending action on main thread
            await MainActor.run {
                self.isExecutingAction = false
                if let pending = self.pendingAction {
                    self.pendingAction = nil
                    print("▶️  Executing queued action: \(pending.description)")
                    self.executeAction(pending)
                }
            }
        }
    }
}
