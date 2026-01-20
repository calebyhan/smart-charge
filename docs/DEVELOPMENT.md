# Development Guide

## Technical Stack

*   **Language**: Swift 5.9+
*   **Framework**: SwiftUI
*   **OS Requirement**: macOS 13.0 (Ventura) or later.
*   **System Integration**: IOKit (monitoring), SMC (control).

## Project Structure

```
BatterySmartCharge/
├── App/                  # Entry point & Delegate
├── Models/               # Data structures
├── Services/             # Core logic (BatteryMonitor, SMCController)
├── Views/                # SwiftUI Views
│   ├── Dashboard/        # Popover UI
│   ├── Settings/         # Preferences UI
│   └── Components/       # Reusable UI bits
└── Utilities/            # Helpers & Extensions
```

## Setup & Dependencies

### Battery CLI Tool
This project depends on the [battery](https://github.com/actuallymentor/battery) CLI tool to interface with the System Management Controller (SMC).

**Installation:**
The app attempts to auto-install or detect this tool. For development:
1.  Install via Homebrew (if available) or download the binary.
2.  Ensure it is in your `$PATH` or accessible at `/usr/local/bin/battery`.

### Launch Agent
To support "Launch at Login", the app registers a Login Item using the `ServiceManagement` framework (`SMAppService`).

## SMC Integration

We do not write to the SMC directly from Swift to avoid kernel panics and instability. We interface via the `battery` CLI.

**Key Commands Used:**
*   `battery charging on`: Enables power flow to battery.
*   `battery charging off`: Disables power flow (running on AC).
*   `battery maintain <limit>`: Sets hardware charge limit (Intel only).
*   `battery status`: Reads current SMC status.

## Testing Strategy

### Unit Tests
*   **AlgorithmTests**: Verify `determineChargingAction()` returns correct decisions for edge cases (temp > 42°C, power > 30W).
*   **TimeRuleTests**: Ensure time rules trigger correctly across midnight boundaries.

### Manual Verification scenarios
1.  **Heat Safety**: Use a stress test tool to raise CPU temp -> Verify app stops charging.
2.  **Mode Switch**: Change from Availability to Longevity -> Verify target range updates immediately.
