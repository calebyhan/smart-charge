# Development Guide

## Technical Stack

*   **Language**: Swift 5.9+
*   **Framework**: SwiftUI + AppKit (NSStatusItem, NSPopover)
*   **OS Requirement**: macOS 13.0 (Ventura) or later
*   **System Integration**: IOKit (monitoring), SMC via `battery` CLI (control)

## Project Structure

```
BatterySmartCharge/
├── App/
│   ├── BatterySmartChargeApp.swift    # SwiftUI App entry point
│   └── AppDelegate.swift               # Menu bar setup, lifecycle
├── Models/
│   ├── BatteryState.swift              # Battery snapshot struct
│   ├── ChargingAction.swift            # Enum: chargeActive/rest/forceStop
│   ├── TimeRule.swift                  # Time-based rule struct
│   └── UserSettings.swift              # User preferences (ObservableObject)
├── Services/
│   ├── BatteryMonitor.swift            # IOKit polling, hysteresis logic
│   ├── ChargingAlgorithm.swift         # Pure decision function
│   ├── SmartChargeManager.swift        # Central coordinator (singleton)
│   ├── SMCController.swift             # Battery CLI wrapper
│   ├── NotificationManager.swift       # User notifications
│   └── UpdateChecker.swift             # GitHub release version checking
├── Views/
│   ├── Dashboard/
│   │   ├── DashboardView.swift         # Main popover content
│   │   ├── BatteryRangeView.swift      # Range indicator bar
│   │   ├── SankeyEnergyFlowView.swift  # Energy flow visualization
│   │   └── TimelineChartView.swift     # 24-hour history chart
│   └── Settings/
│       ├── SettingsView.swift          # TabView container + RangeSlider
│       ├── TimeRulesView.swift         # Time rules list
│       └── PowerDrawSettingsView.swift # Power threshold sliders
├── Utilities/
│   ├── BatteryIconRenderer.swift       # Menu bar icon generation
│   ├── IOReportReader.swift            # Direct IOReport power metrics
│   ├── PowerMetricsReader.swift        # powermetrics CLI fallback
│   ├── SMCNative.swift                 # Direct SMC reads (Intel)
│   ├── LaunchHelper.swift              # Login item registration
│   └── PrivilegedHelperManager.swift   # XPC helper installation
└── PowerMetricsHelper/
    └── main.swift                      # Privileged helper for powermetrics
```

## Setup & Dependencies

### Battery CLI Tool

This project depends on the [battery](https://github.com/actuallymentor/battery) CLI tool to interface with the System Management Controller (SMC).

**Installation:**

The app expects the CLI at `/usr/local/bin/battery`. For development:

1. Install via Homebrew: `brew install battery`
2. Or download the binary from the GitHub releases

The installer (`.pkg`) bundles the `battery` CLI automatically.

### Privileged Helper

The `PowerMetricsHelper` is an XPC service that runs `powermetrics` to read CPU/GPU power consumption. It requires admin privileges and is installed on first run.

### Launch Agent

The app uses `SMAppService` (ServiceManagement framework) to register itself as a login item. No separate Launch Agent plist is needed.

## SMC Integration

We do not write to the SMC directly from Swift to avoid kernel panics. All SMC control is via the `battery` CLI.

**Key Commands Used:**

```bash
# Enable charging
sudo battery charging on

# Disable charging (battery holds current level while on AC)
sudo battery charging off

# Check status
sudo battery status
```

**Daemon Conflict Mitigation:**

The `battery` CLI has its own background daemon that can conflict with Smart Charge. On app launch, `SMCController.disableBatteryDaemon()`:

1. Unloads `~/Library/LaunchAgents/battery.plist` if present
2. Deletes the plist to prevent reloading
3. Runs `battery maintain stop` to stop any running maintain process
4. Removes `~/.battery/maintain.percentage` to clear stale state

## Building

### Development Build

```bash
# Open in Xcode
open BatterySmartCharge.xcodeproj

# Build and run (Cmd+R)
```

### Release Build

```bash
# Build Release configuration
xcodebuild -project BatterySmartCharge.xcodeproj \
    -scheme BatterySmartCharge \
    -configuration Release \
    clean build

# Create installer package
./create_installer.sh
```

The installer is created at `dist/BatterySmartCharge-{version}.pkg`.

## Key Implementation Details

### Polling Interval

BatteryMonitor polls IOKit every 0.5 seconds for responsive charging state detection. This is fast enough to catch plug/unplug events quickly while not being a significant CPU burden.

### Hysteresis

Two levels of hysteresis prevent oscillation:

1. **Charging Detection**: Uses different thresholds for on→off (0.2W) vs off→on (1.0W) transitions.
2. **Algorithm Bands**: 3% buffer for charge start, 2% buffer for charge stop within target range.

### Sticky Plug State

macOS reports `ExternalConnected=No` when charging is disabled via SMC (even though the adapter is plugged in). BatteryMonitor maintains a "sticky" plug state with a 2-second timeout for disambiguation.

### Action Execution

When `SmartChargeManager` determines a state change is needed:

1. Sends SMC command via `SMCController`
2. Waits 1.5 seconds for CLI daemon to settle
3. Polls IOKit up to 10 times (200ms each) waiting for hardware state to match
4. Optionally verifies via `battery status` CLI

### Retry Logic

If hardware state doesn't match expected after initial execution:

- Tracks "stuck" state with timestamp
- Retries SMC command after 30 seconds (up to 5 times)
- Detects Apple Optimized Battery Charging if stuck at ~80% for 2+ minutes
- Notifies user if retries exhausted after 5 minutes

## Testing

Currently, the project does not have automated tests. Manual verification scenarios:

1. **Threshold Behavior**: Set thresholds, verify charging starts/stops at correct levels.
2. **Temperature Safety**: Monitor that charging pauses above 38°C (may require external heat source or stress test).
3. **Wake from Sleep**: Verify charging state is re-applied after system wake.
4. **Force Full Charge**: Verify override works and auto-clears at 100%.
5. **Apple Coexistence**: Test with Optimized Battery Charging enabled in System Settings.

## Code Style

- SwiftUI for views, AppKit for menu bar integration
- Combine for reactive state binding
- `@Published` properties in `ObservableObject` classes for UI updates
- Pure functions for algorithm logic (no side effects in `ChargingAlgorithm`)

## Versioning

Version is defined in:
- `BatterySmartCharge.xcodeproj` (Marketing Version)
- `SettingsView.swift` (`AboutView` displays version)
- `README.md` (download links)
- `create_installer.sh` (package filename)

Update all locations when releasing a new version.
