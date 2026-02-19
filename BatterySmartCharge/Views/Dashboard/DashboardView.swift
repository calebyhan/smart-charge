import SwiftUI

struct DashboardView: View {
    @ObservedObject var manager: SmartChargeManager
    @StateObject private var updateChecker = UpdateChecker()

    // Derived state for UI
    var activeTargetRange: (min: Int, max: Int) {
        manager.settings.getTargetRange(for: Date())
    }

    var formattedTemperature: String {
        let tempC = manager.monitor.state.temperature
        if manager.settings.useFahrenheit {
            let tempF = tempC * 9 / 5 + 32
            return String(format: "%.1f°F", tempF)
        } else {
            return String(format: "%.1f°C", tempC)
        }
    }

    // Check if the desired action matches the actual hardware state
    var isStateMismatched: Bool {
        let action = manager.currentAction
        let isCharging = manager.monitor.state.isCharging
        let isPluggedIn = manager.monitor.state.isPluggedIn
        let percent = manager.monitor.state.percent

        // If we want to charge but hardware isn't charging yet (and we're plugged in)
        if action == .chargeActive && !isCharging && isPluggedIn {
            // At very high battery levels (>= 95%), macOS often won't charge even when allowed
            // This is normal Apple behavior to preserve battery longevity
            // Don't show "Applying changes..." to avoid confusing the user
            if percent >= 95 {
                return false
            }
            // Between 80-94%, show mismatch but expect it might take longer to resolve
            return true
        }
        // If we want to rest/stop but hardware is still charging
        if (action == .rest || action == .forceStop) && isCharging && isPluggedIn {
            return true
        }
        return false
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Update Banner
            if updateChecker.newVersionAvailable {
                updateBanner
            }

            // Header
            HStack {
                Text("Battery: \(manager.monitor.state.percent)%")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if manager.monitor.state.isPluggedIn {
                    if manager.monitor.state.isCharging {
                        HStack(spacing: 4) {
                            Label("Charging", systemImage: "bolt.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            // Show time to target if available, otherwise system estimate
                            if let prediction = manager.predictTimeToTarget() {
                                Text("(\(formatTimeRemaining(prediction.minutes)) to \(prediction.target)%)")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            } else if let mins = manager.monitor.state.timeRemaining {
                                Text("(\(formatTimeRemaining(mins)))")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    } else {
                        Label("Idle (Plugged In)", systemImage: "powerplug.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                    }
                } else {
                    HStack(spacing: 4) {
                        Label("On Battery", systemImage: "battery.100percent")
                            .foregroundColor(.orange)
                            .font(.caption)
                        if let mins = manager.monitor.state.timeRemaining, mins < 0 {
                            Text("(\(formatTimeRemaining(abs(mins))) left)")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }
            .padding(.top, 4)

            // Show loading indicator when action and hardware state don't match
            if isStateMismatched && !manager.isAppleOptimizationActive {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .controlSize(.small)
                    Text("Applying changes...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
            }

            // Show Apple optimization indicator
            if manager.isAppleOptimizationActive {
                HStack(spacing: 6) {
                    Image(systemName: "applelogo")
                        .foregroundColor(.blue)
                    Text("Apple Battery Optimization Active")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
            }
            
            Divider()
            
            // Status Section
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    // Show "On Battery" when unplugged, otherwise show the charging action
                    Text(manager.monitor.state.isPluggedIn ? manager.currentAction.description : "On Battery")
                        .font(.headline)
                        .foregroundColor(.primary)

                    // Small spinner next to status when states don't match
                    if isStateMismatched {
                        ProgressView()
                            .scaleEffect(0.6)
                            .controlSize(.small)
                    }
                }

                if manager.monitor.state.temperature > 0.1 {
                    Text("Temp: \(formattedTemperature)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            
            // Sankey Flow
            SankeyEnergyFlowView(
                cpuPower: manager.monitor.state.cpuPower,
                gpuPower: manager.monitor.state.gpuPower,
                totalPower: manager.monitor.state.powerDraw,
                isCharging: manager.monitor.state.isCharging,
                batteryPower: manager.monitor.state.batteryPower
            )
            
            // Battery Range
            BatteryRangeView(
                currentPercent: manager.monitor.state.percent,
                minThreshold: manager.settings.minThreshold,
                maxThreshold: manager.settings.maxThreshold,
                targetMin: activeTargetRange.min,
                targetMax: activeTargetRange.max
            )

            // Active Time Rule Indicator
            if let activeRule = manager.settings.getActiveRule(for: Date()) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.purple)
                        .font(.caption)
                    Text(activeRule.name)
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("(\(activeRule.targetMin)%-\(activeRule.targetMax)%)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Timeline
            TimelineChartView(
                dataPoints: manager.historyPoints,
                historyEntries: manager.historyEntries,
                useFahrenheit: manager.settings.useFahrenheit
            )
            
            Divider()
            
            // Footer / Quick Actions
            HStack {
                Button(action: {
                    toggleChargeToFull()
                }) {
                    if manager.isOverrideActive {
                        Label("Resume Smart Charge", systemImage: "arrow.uturn.backward")
                            .foregroundColor(.red)
                    } else {
                        Label("Force Full Charge", systemImage: "bolt.fill")
                    }
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .controlSize(.small)
                .disabled(!manager.monitor.state.isPluggedIn)
                
                Spacer()
                
                if #available(macOS 14.0, *) {
                    SettingsLink {
                        Image(systemName: "gearshape.fill")
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    .simultaneousGesture(TapGesture().onEnded {
                        bringSettingsToFront()
                    })
                } else {
                    Button(action: {
                        openSettings()
                    }) {
                        Image(systemName: "gearshape.fill")
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                }
            }
        }
        .padding()
        .frame(width: 320)
        .task {
            // Check for updates when view appears
            await updateChecker.checkForUpdates()
        }
    }

    // MARK: - Update Banner

    private var updateBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.blue)
                Text("Update Available: \(updateChecker.latestVersion)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            Button(action: {
                updateChecker.openDownloadPage()
            }) {
                Text("Download & Install")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Actions

    private func toggleChargeToFull() {
        // Check actual override state, not the desired action
        if manager.isOverrideActive {
             manager.stopOverride()
        } else {
             manager.startOverride(action: .chargeActive)
        }
    }
    
    private func openSettings() {
        // For macOS 13 and earlier
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        bringSettingsToFront()
    }

    private func bringSettingsToFront() {
        // Ensure the window appears on top
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows {
                if window.title.contains("Settings") || window.title.contains("Preferences") {
                    window.level = .floating
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                }
            }
        }
    }

    private func formatTimeRemaining(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(mins)m"
        }
    }
}
