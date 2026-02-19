import Foundation
import IOKit

// IOReport framework - private Apple API for power metrics
// Provides CPU, GPU, ANE, DRAM, and System Power without sudo
// Based on reverse engineering from powermetrics, mactop, macmon

// MARK: - IOReport C API Declarations

// IOReport types
typealias IOReportSubscriptionRef = CFTypeRef
typealias IOReportSampleRef = CFTypeRef

// RTLD_DEFAULT for dlsym (not available in Swift by default)
private let RTLD_DEFAULT_HANDLE = UnsafeMutableRawPointer(bitPattern: -2)

// IOReport function pointers (loaded dynamically from IOKit.framework)
private typealias IOReportCopyChannelsInGroupFunc = @convention(c) (
    CFString, CFTypeRef?, Int, Int, Int
) -> Unmanaged<CFMutableDictionary>?

private typealias IOReportCreateSubscriptionFunc = @convention(c) (
    CFTypeRef?, CFMutableDictionary, UnsafeMutablePointer<CFMutableDictionary>?, Int, CFTypeRef?
) -> Unmanaged<AnyObject>?

private typealias IOReportCreateSamplesFunc = @convention(c) (
    IOReportSubscriptionRef, CFMutableDictionary, CFTypeRef?
) -> Unmanaged<CFDictionary>?

private typealias IOReportCreateSamplesDeltaFunc = @convention(c) (
    CFDictionary, CFDictionary, CFTypeRef?
) -> Unmanaged<CFDictionary>?

// MARK: - IOReportReader

class IOReportReader {
    static let shared = IOReportReader()

    private var subscription: IOReportSubscriptionRef?
    private var channels: CFMutableDictionary?
    private var lastSample: CFDictionary?
    private var lastSampleTime: Date?
    private let sampleInterval: TimeInterval = 0.5 // 500ms between samples

    private var isAvailable = false

    // Dynamically loaded function pointers
    private var copyChannelsInGroup: IOReportCopyChannelsInGroupFunc?
    private var createSubscription: IOReportCreateSubscriptionFunc?
    private var createSamples: IOReportCreateSamplesFunc?
    private var createSamplesDelta: IOReportCreateSamplesDeltaFunc?

    struct PowerMetrics {
        var cpuPower: Double = 0      // Watts
        var gpuPower: Double = 0      // Watts
        var anePower: Double = 0      // Watts (Apple Neural Engine)
        var dramPower: Double = 0     // Watts (DRAM/memory)
        var systemPower: Double = 0   // Watts (total system if available)
    }

    init() {
        loadIOReportFunctions()
        if isAvailable {
            setupIOReportSubscription()
        }
    }

    deinit {
        // Clean up subscription if needed
        subscription = nil
        channels = nil
        lastSample = nil
    }

    // MARK: - Dynamic Loading

    private func loadIOReportFunctions() {
        // IOReport functions are in the dyld shared cache on modern macOS
        // Use RTLD_DEFAULT to search all loaded libraries instead of trying to dlopen a specific path

        // Load function pointers from global symbol space
        guard let copyChannels = dlsym(RTLD_DEFAULT_HANDLE, "IOReportCopyChannelsInGroup") else {
            isAvailable = false
            return
        }

        guard let createSub = dlsym(RTLD_DEFAULT_HANDLE, "IOReportCreateSubscription") else {
            isAvailable = false
            return
        }

        guard let createSamp = dlsym(RTLD_DEFAULT_HANDLE, "IOReportCreateSamples") else {
            isAvailable = false
            return
        }

        guard let createDelta = dlsym(RTLD_DEFAULT_HANDLE, "IOReportCreateSamplesDelta") else {
            isAvailable = false
            return
        }

        // Cast to function pointers
        copyChannelsInGroup = unsafeBitCast(copyChannels, to: IOReportCopyChannelsInGroupFunc.self)
        createSubscription = unsafeBitCast(createSub, to: IOReportCreateSubscriptionFunc.self)
        createSamples = unsafeBitCast(createSamp, to: IOReportCreateSamplesFunc.self)
        createSamplesDelta = unsafeBitCast(createDelta, to: IOReportCreateSamplesDeltaFunc.self)

        isAvailable = true
    }

    // MARK: - Setup

    private func setupIOReportSubscription() {
        guard let copyChannelsInGroup = copyChannelsInGroup,
              let createSubscription = createSubscription else {
            isAvailable = false
            return
        }

        // Try to subscribe to "Energy Model" group which contains power metrics
        var energyChannels: CFMutableDictionary? = copyChannelsInGroup("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue()

        if energyChannels == nil {
            // Try alternative channel group names
            let alternativeNames = ["energy", "CPU Stats", "GPU Stats"]

            for name in alternativeNames {
                if let ch = copyChannelsInGroup(name as CFString, nil, 0, 0, 0)?.takeRetainedValue() {
                    energyChannels = ch
                    break
                }
            }
        }

        guard let validChannels = energyChannels else {
            isAvailable = false
            return
        }

        channels = validChannels

        // Create subscription
        guard let sub = createSubscription(nil, validChannels, nil, 0, nil)?.takeRetainedValue() else {
            isAvailable = false
            return
        }

        subscription = sub
        isAvailable = true
    }

    // MARK: - Public API

    func getPowerMetrics() -> PowerMetrics? {
        guard isAvailable,
              let subscription = subscription,
              let channels = channels,
              let createSamples = createSamples,
              let createSamplesDelta = createSamplesDelta else {
            return nil
        }

        // Check if enough time has passed since last sample
        let now = Date()
        if let lastTime = lastSampleTime,
           now.timeIntervalSince(lastTime) < sampleInterval {
            return nil // Too soon, skip this sample
        }

        // Get current sample
        guard let currentSample = createSamples(subscription, channels, nil)?.takeRetainedValue() else {
            return nil
        }

        // If we have a previous sample, compute delta
        var metrics = PowerMetrics()

        if let prevSample = lastSample,
           let prevTime = lastSampleTime {

            // Compute delta between samples
            guard let delta = createSamplesDelta(prevSample, currentSample, nil)?.takeRetainedValue() else {
                lastSample = currentSample
                lastSampleTime = now
                return nil
            }

            // Time interval for power calculation (Watts = Joules / seconds)
            let timeInterval = now.timeIntervalSince(prevTime)

            // Parse the delta to extract power values
            metrics = parsePowerMetrics(from: delta, timeInterval: timeInterval)
        }

        // Store current sample for next delta
        lastSample = currentSample
        lastSampleTime = now

        return metrics
    }

    // MARK: - Parsing

    private func parsePowerMetrics(from delta: CFDictionary, timeInterval: TimeInterval) -> PowerMetrics {
        var metrics = PowerMetrics()

        // The delta dictionary contains "IOReportChannels" array with metric objects
        guard let dict = delta as? [String: Any],
              let channelsArray = dict["IOReportChannels"] as? [[String: Any]] else {
            return metrics
        }

        // Parse each channel
        for channel in channelsArray {
            guard let channelName = channel["ChannelName"] as? String,
                  let unit = channel["Unit"] as? String else {
                continue
            }

            // Get energy value (in mJ, uJ, or nJ depending on unit)
            var energyJoules: Double = 0

            if let value = channel["Value"] as? Double {
                // Convert to Joules based on unit
                switch unit {
                case "mJ": energyJoules = value / 1000.0           // millijoules to joules
                case "uJ": energyJoules = value / 1_000_000.0      // microjoules to joules
                case "nJ": energyJoules = value / 1_000_000_000.0  // nanojoules to joules
                default: energyJoules = value // assume already in Joules
                }
            }

            // Convert energy to power: P(W) = E(J) / t(s)
            let powerWatts = timeInterval > 0 ? energyJoules / timeInterval : 0

            // Map channel names to metrics
            // Channel names are like "ECPU", "PCPU", "GPU", "DRAM", "ANE", etc.
            let channelLower = channelName.lowercased()

            if channelLower.contains("cpu") && !channelLower.contains("gpu") {
                // CPU power (sum of E-cluster + P-cluster)
                metrics.cpuPower += powerWatts
            } else if channelLower.contains("gpu") && !channelLower.contains("sram") {
                // GPU power (excluding GPU SRAM)
                metrics.gpuPower += powerWatts
            } else if channelLower.contains("ane") {
                // Apple Neural Engine
                metrics.anePower += powerWatts
            } else if channelLower.contains("dram") || channelLower.contains("soc_dram") {
                // DRAM power
                metrics.dramPower += powerWatts
            } else if channelLower.contains("system") || channelLower.contains("package") {
                // System or package power (if available)
                metrics.systemPower = powerWatts
            }
        }

        // If system power wasn't explicitly provided, estimate it
        if metrics.systemPower < 0.1 {
            // System = CPU + GPU + ANE + DRAM (+ other on-chip components)
            metrics.systemPower = metrics.cpuPower + metrics.gpuPower + metrics.anePower + metrics.dramPower
        }

        return metrics
    }

    // MARK: - Individual metric accessors

    func readCPUPower() -> Double? {
        guard let metrics = getPowerMetrics() else { return nil }
        return metrics.cpuPower > 0 ? metrics.cpuPower : nil
    }

    func readGPUPower() -> Double? {
        guard let metrics = getPowerMetrics() else { return nil }
        return metrics.gpuPower > 0 ? metrics.gpuPower : nil
    }

    func readDRAMPower() -> Double? {
        guard let metrics = getPowerMetrics() else { return nil }
        return metrics.dramPower > 0 ? metrics.dramPower : nil
    }

    func readSystemPower() -> Double? {
        guard let metrics = getPowerMetrics() else { return nil }
        return metrics.systemPower > 0 ? metrics.systemPower : nil
    }
}
