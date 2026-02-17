import Foundation
import IOKit
import IOKit.ps
import Combine

class BatteryMonitor: ObservableObject {
    @Published var state: BatteryState = .empty

    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.smartcharge.batterymonitor", qos: .utility)
    private var powerSourceNotification: CFRunLoopSource?
    private var lastUpdateTime: Date = .distantPast
    private let minUpdateInterval: TimeInterval = 0.5 // Minimum 500ms between updates

    // Track plug state ourselves - macOS reports ExternalConnected=No when we disable charging via SMC
    private var lastKnownPluggedInState: Bool = false
    private var ambiguousStateStartTime: Date? = nil
    private let ambiguousStateTimeout: TimeInterval = 2.0 // 2 seconds

    // Hysteresis for charging detection to prevent oscillation at threshold
    private var lastKnownChargingState: Bool = false
    private let chargingOnThreshold: Double = 1.0   // Must exceed 1W to start "charging"
    private let chargingOffThreshold: Double = 0.2  // Must drop below 0.2W to stop "charging"

    init() {
        startMonitoring()
        setupPowerSourceNotifications()
    }

    deinit {
        if let notification = powerSourceNotification {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), notification, .defaultMode)
        }
    }
    
    func startMonitoring() {
        // Poll every 0.5 seconds for highly responsive charging detection
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateBatteryState()
        }
        updateBatteryState() // Initial update
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    @objc func updateBatteryState() {
        updateBatteryState(force: false)
    }

    func updateBatteryState(force: Bool = false) {
        let now = Date()

        // Debounce: skip update if less than minUpdateInterval has passed (unless forced)
        if !force {
            guard now.timeIntervalSince(lastUpdateTime) >= minUpdateInterval else {
                return
            }
        }

        lastUpdateTime = now

        queue.async { [weak self] in
            guard let self = self else { return }

            let snapshot = self.getIOKitBatteryInfo()

            DispatchQueue.main.async {
                self.state = snapshot
            }
        }
    }
    
    private func getIOKitBatteryInfo() -> BatteryState {
        // Create a snapshot of power source information
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return .empty
        }
        
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            
            // We only care about the internal battery
            if let type = desc[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType {
                
                let currentCap = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
                let maxCap = desc[kIOPSMaxCapacityKey] as? Int ?? 100

                // Get voltage and current from IOPowerSources API
                var voltage = desc[kIOPSVoltageKey] as? Double ?? 0
                var current = desc[kIOPSCurrentKey] as? Double ?? 0 // Positive if charging, negative if discharging

                // IOPowerSources API doesn't always provide these values, so fall back to IORegistry
                if voltage == 0 || current == 0 {
                    let registryValues = self.getVoltageAndAmperageFromRegistry()
                    if voltage == 0 {
                        voltage = registryValues.voltage
                    }
                    if current == 0 {
                        current = registryValues.amperage
                    }
                }

                // More robust charging detection
                var isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
                let powerSourceState = desc[kIOPSPowerSourceStateKey] as? String
                let externalConnected = desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue

                // Calculate battery power to determine actual charging state
                let batteryPowerW = (voltage / 1000.0) * (current / 1000.0)

                // macOS bug: When we disable charging via SMC, macOS reports ExternalConnected=No
                // even though the adapter is physically connected.
                //
                // Solution: Sticky state with explicit unplug detection
                // - Trust IOKit when it says plugged in (no false positives)
                // - Trust battery power flow when charging (physics - must be plugged to charge)
                // - Trust battery discharge (physics - if discharging, definitely unplugged)
                // - If IOKit reports unplugged AND not charging, likely actually unplugged
                // - Otherwise use sticky state (assume still plugged if we were before)

                var isPluggedIn = self.lastKnownPluggedInState  // Start with last known state

                if externalConnected {
                    // IOKit says plugged in - always trust (no false positives)
                    isPluggedIn = true
                    self.ambiguousStateStartTime = nil // Clear ambiguous timer
                } else if batteryPowerW > self.chargingOnThreshold {
                    // Battery clearly charging - must be plugged despite IOKit saying otherwise
                    isPluggedIn = true
                    self.ambiguousStateStartTime = nil // Clear ambiguous timer
                } else if batteryPowerW < -1.0 {
                    // Battery clearly discharging (>1W drain) - definitely unplugged
                    isPluggedIn = false
                    self.ambiguousStateStartTime = nil // Clear ambiguous timer
                } else if !externalConnected && batteryPowerW <= 0 && !isCharging {
                    // IOKit says unplugged, battery not charging, power flow zero or negative
                    // Most likely actually unplugged (not just disabled charging)
                    // Wait 2 seconds before clearing sticky state
                    let now = Date()
                    if let startTime = self.ambiguousStateStartTime {
                        // Already in ambiguous state - check if timeout reached
                        if now.timeIntervalSince(startTime) >= self.ambiguousStateTimeout {
                            isPluggedIn = false
                            self.ambiguousStateStartTime = nil
                        }
                        // else: keep sticky state, still within timeout
                    } else {
                        // First time seeing ambiguous state - start timer
                        self.ambiguousStateStartTime = now
                        // Keep sticky state for now
                    }
                } else {
                    // Other ambiguous cases - keep sticky state
                    self.ambiguousStateStartTime = nil
                }
                // else: keep sticky state (ambiguous - could be plugged with charging disabled)

                // Determine charging state with hysteresis to prevent oscillation
                // Use different thresholds for on→off vs off→on transitions
                if self.lastKnownChargingState {
                    // Currently "charging" - only switch to not charging if power drops significantly
                    isCharging = (batteryPowerW > self.chargingOffThreshold)
                } else {
                    // Currently "not charging" - only switch to charging if power rises significantly
                    isCharging = (batteryPowerW > self.chargingOnThreshold)
                }
                self.lastKnownChargingState = isCharging

                // Update sticky state
                self.lastKnownPluggedInState = isPluggedIn

                // Calculate percentage
                let percent = maxCap > 0 ? Int((Double(currentCap) / Double(maxCap)) * 100.0) : 0

                var cpuPowerW = 0.0
                var gpuPowerW = 0.0
                var dramPowerW = 0.0  // DRAM power (new from IOReport)
                var powerDrawW = 0.0

                // Priority 1: Try IOReport (best - no sudo, includes DRAM, accurate)
                var gotIOReportData = false
                if let ioMetrics = IOReportReader.shared.getPowerMetrics() {
                    cpuPowerW = ioMetrics.cpuPower
                    gpuPowerW = ioMetrics.gpuPower
                    dramPowerW = ioMetrics.dramPower
                    // Use systemPower if available (includes everything)
                    if ioMetrics.systemPower > 0.1 {
                        powerDrawW = ioMetrics.systemPower
                    }
                    gotIOReportData = true
                }

                // Priority 2: Fall back to PowerMetrics helper (XPC/subprocess)
                if !gotIOReportData {
                    if let pmCpu = PowerMetricsReader.shared.readCPUPower() {
                        cpuPowerW = pmCpu
                    }
                    if let pmGpu = PowerMetricsReader.shared.readGPUPower() {
                        gpuPowerW = pmGpu
                    }
                }

                // Get TRUE system power - try multiple sources in order of reliability:

                // Strategy depends on whether we're plugged in or not:
                // - UNPLUGGED: All power flows through battery, so voltage×current = total system power
                // - PLUGGED IN: Battery current only shows charging power, not total system consumption
                //               Use IOReport system power if available, otherwise estimate

                let voltageCurrentPower = abs((voltage / 1000.0) * (current / 1000.0))

                // If we already got powerDraw from IOReport systemPower, we're done
                if powerDrawW > 0.1 {
                    // IOReport provided accurate system power - use it
                } else if !isPluggedIn {
                    // UNPLUGGED: Use voltage×current (accurate - all power from battery)
                    if voltageCurrentPower > 0.1 {
                        powerDrawW = voltageCurrentPower
                    } else if let smcPower = SMCNative.shared.readSystemPower() {
                        powerDrawW = smcPower
                    } else if let pmTotal = PowerMetricsReader.shared.readSystemPower() {
                        powerDrawW = pmTotal
                    }
                } else {
                    // PLUGGED IN: Estimate total system consumption
                    // Priority 1: SMC direct reading (Intel Macs)
                    if let smcPower = SMCNative.shared.readSystemPower() {
                        powerDrawW = smcPower
                    }
                    // Priority 2: CPU + GPU + DRAM + estimated display/peripheral overhead
                    // Now includes DRAM from IOReport! Much more accurate than before.
                    else if cpuPowerW > 0 || gpuPowerW > 0 || dramPowerW > 0 {
                        // Known components from measurements
                        let measuredPower = cpuPowerW + gpuPowerW + dramPowerW

                        // Estimate display + SSD + networking + peripherals
                        // Display is the biggest unknown (2-5W depending on brightness)
                        // Other components: ~1-2W total
                        let estimatedOther = 3.5 // Display ~2.5W + other ~1W (conservative)

                        powerDrawW = measuredPower + estimatedOther
                    }
                    // Priority 3: PowerMetrics fallback (CPU+GPU only, no DRAM)
                    else if let pmTotal = PowerMetricsReader.shared.readSystemPower() {
                        // PowerMetrics gives CPU+GPU+ANE but misses DRAM and display
                        let estimatedOtherPower = 5.0 // DRAM ~1-2W + Display ~2-5W + other ~1W
                        powerDrawW = pmTotal + estimatedOtherPower
                    }
                }

                // batteryPowerW already calculated above for isCharging detection

                // Temperature, cycle count & capacity from IORegistry (works on Apple Silicon without sudo)
                let batteryInfo = self.getSmartBatteryInfo()
                var temperature = batteryInfo.temperature
                let cycleCount = batteryInfo.cycleCount
                let health = batteryInfo.health
                let capacityWh = batteryInfo.capacityWh

                // Fallback to PowerMetrics or SMC if IORegistry temp unavailable
                if temperature == 0 {
                    if let pmTemp = PowerMetricsReader.shared.readTemperature() {
                        temperature = pmTemp
                    } else if let smcTemp = SMCNative.shared.readTemperature() {
                        temperature = smcTemp
                    }
                }

                // Get time remaining from macOS (uses smoothed/averaged calculation)
                // Positive = time to full charge, Negative = time until empty
                var timeRemaining: Int? = nil
                let systemTimeRemaining = IOPSGetTimeRemainingEstimate()

                if isCharging && percent < 100 {
                    // Charging: use "Time to Full Charge" from IOKit if available
                    if let timeToFull = desc[kIOPSTimeToFullChargeKey] as? Int, timeToFull > 0 {
                        timeRemaining = timeToFull
                    }
                } else if !isPluggedIn && percent > 0 {
                    // Discharging: use macOS system estimate
                    // kIOPSTimeRemainingUnknown = -1, kIOPSTimeRemainingUnlimited = -2
                    if systemTimeRemaining > 0 {
                        timeRemaining = -Int(systemTimeRemaining / 60) // Convert seconds to minutes, negative for discharge
                    }
                }

                return BatteryState(
                    percent: percent,
                    isCharging: isCharging,
                    isPluggedIn: isPluggedIn,
                    powerDraw: powerDrawW,
                    cpuPower: cpuPowerW,
                    gpuPower: gpuPowerW,
                    batteryPower: batteryPowerW,
                    temperature: temperature,
                    health: health,
                    cycleCount: cycleCount,
                    timeRemaining: timeRemaining
                )
            }
        }
        
        return .empty
    }

    private func getVoltageAndAmperageFromRegistry() -> (voltage: Double, amperage: Double) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            return (0, 0)
        }
        defer { IOObjectRelease(service) }

        var voltage: Double = 0
        var amperage: Double = 0

        // Voltage is in mV
        if let voltRef = IORegistryEntryCreateCFProperty(service, "Voltage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
           let voltValue = voltRef as? Int {
            voltage = Double(voltValue)
        }

        // Amperage is in mA (positive = charging, negative = discharging)
        if let ampRef = IORegistryEntryCreateCFProperty(service, "Amperage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
           let ampValue = ampRef as? Int {
            amperage = Double(ampValue)
        }

        return (voltage, amperage)
    }

    private func getSmartBatteryInfo() -> (temperature: Double, cycleCount: Int, health: Int, capacityWh: Double) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            return (0, 0, 100, 0)
        }
        defer { IOObjectRelease(service) }

        var temperature = 0.0
        var cycleCount = 0
        var health = 100
        var capacityWh = 0.0

        // Temperature is in decikelvin (e.g., 3012 = 301.2K = 28.05°C)
        if let tempRef = IORegistryEntryCreateCFProperty(service, "Temperature" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
           let tempValue = tempRef as? Int {
            temperature = Double(tempValue) / 10.0 - 273.15
        }

        // Cycle count
        if let cycleRef = IORegistryEntryCreateCFProperty(service, "CycleCount" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
           let cycleValue = cycleRef as? Int {
            cycleCount = cycleValue
        }

        // Health: MaxCapacity / DesignCapacity * 100
        if let maxCapRef = IORegistryEntryCreateCFProperty(service, "MaxCapacity" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
           let designCapRef = IORegistryEntryCreateCFProperty(service, "DesignCapacity" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
           let maxCap = maxCapRef as? Int,
           let designCap = designCapRef as? Int,
           designCap > 0 {
            health = Int((Double(maxCap) / Double(designCap)) * 100.0)
        }

        // Get battery capacity in Wh for time remaining calculation
        // AppleRawMaxCapacity is in mAh, Voltage is in mV
        if let rawCapRef = IORegistryEntryCreateCFProperty(service, "AppleRawMaxCapacity" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
           let voltRef = IORegistryEntryCreateCFProperty(service, "Voltage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
           let rawCapMah = rawCapRef as? Int,
           let voltageMv = voltRef as? Int {
            // Wh = (mAh * mV) / 1,000,000
            capacityWh = Double(rawCapMah) * Double(voltageMv) / 1_000_000.0
        }

        return (temperature, cycleCount, health, capacityWh)
    }

    private func setupPowerSourceNotifications() {
        // Set up notification callback for power source changes
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let callback: IOPowerSourceCallbackType = { context in
            guard let context = context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            // Immediately update battery state when power source changes
            monitor.updateBatteryState()
        }

        // Create run loop source for power source notifications
        powerSourceNotification = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue()

        // Add to current run loop
        if let notification = powerSourceNotification {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), notification, .defaultMode)
        }
    }
}
