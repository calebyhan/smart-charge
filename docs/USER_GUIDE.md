# User Guide

## Overview

Smart Charge is a macOS menu bar app that intelligently manages your MacBook's battery charging to maximize battery lifespan while ensuring you always have enough power when you need it.

## Charging Thresholds

The core concept is simple: set a **minimum** and **maximum** battery percentage threshold.

*   **Start Threshold** (default: 20%): When your battery drops below this level while plugged in, charging begins.
*   **Stop Threshold** (default: 80%): When your battery reaches this level, charging stops.

This keeps your battery in the "sweet spot" (20-80%) most of the time, which significantly reduces long-term wear compared to keeping it at 100%.

### Why 20-80%?

Lithium-ion batteries experience the most stress when held at very high (>90%) or very low (<10%) charge levels. Keeping the battery in the middle range:
- Reduces chemical stress on the cells
- Minimizes heat generation during charging
- Can extend overall battery lifespan by years

## Configuration

### General Settings

Access settings by clicking the gear icon in the dashboard popover.

*   **Charging Thresholds**: Drag the range slider to set your preferred start/stop percentages.
*   **Launch at Login**: Enable to have Smart Charge start automatically when you log in.
*   **Temperature Unit**: Choose between Celsius and Fahrenheit for temperature display.

### Time Rules

Create custom charging schedules for different times of day. For example:
*   "Morning Commute" — Charge to 90% between 7-8 AM before heading out.
*   "Work Hours" — Maintain 50-60% while at your desk.
*   "Overnight" — Keep at 40-50% while sleeping.

Each rule specifies:
- **Name**: A descriptive label
- **Days**: Which days of the week the rule applies
- **Time Window**: Start and end time
- **Target Range**: Min and max percentage during this window
- **Enabled**: Toggle to activate/deactivate

Rules are evaluated in order. If the current time matches a rule, that rule's target range is used. Time rules are clamped to your hard thresholds (the main start/stop settings).

### Power Thresholds

Configure what constitutes "light" vs "heavy" power usage:
*   **Light Usage**: Below this threshold (default: 15W). Typical for web browsing, documents.
*   **Heavy Usage**: Above this threshold (default: 30W). Video editing, gaming, compiling.

These thresholds are informational for future features and help the algorithm understand your usage patterns.

## User Interface

### Menu Bar Icon

The menu bar icon shows your current battery state:
*   **Fill Level**: Visual representation of charge percentage
*   **Lightning Bolt**: Appears when actively charging
*   **Plug Icon**: Appears when plugged in but not charging (holding)

Left-click the icon to open the dashboard. Right-click to access the quit option.

### Dashboard Popover

Click the menu bar icon to see:

*   **Battery Percentage**: Large header showing current charge level
*   **Status Indicator**: Shows charging state (Charging, Idle, On Battery) with time remaining
*   **Temperature**: Current battery temperature
*   **Sankey Energy Flow**: Visual diagram showing power flow between:
    - AC adapter
    - Battery (charging or discharging)
    - System components (CPU, GPU, Other)
*   **Range Indicator**: Bar showing your current charge relative to your target range
*   **Timeline Chart**: 24-hour history of battery percentage with hover tooltips
*   **Force Full Charge**: Button to override thresholds and charge to 100% (for travel, etc.)

### Applying Changes Indicator

When you see "Applying changes..." with a spinner, Smart Charge is waiting for the hardware to respond to a charging state change. This typically resolves within a few seconds.

### Apple Optimization Notice

If you see "Apple Battery Optimization Active", macOS is controlling charging (typically holding at ~80%). Smart Charge will resume control when Apple's optimization completes. You can override this by clicking "Force Full Charge".

## Notifications

Smart Charge sends notifications for important events:

*   **Charging Status Updated**: When the charging state changes (e.g., "Switched to: Charging").
*   **High Temperature Warning**: When battery temperature exceeds 38°C. Charging is paused.
*   **Safety Cutoff Triggered**: When battery temperature exceeds 42°C. All charging is force-stopped.
*   **Apple Battery Optimization Active**: When macOS Optimized Battery Charging is detected.
*   **Charging Control Issue**: When Smart Charge cannot control charging state (usually due to macOS interference).

## Force Full Charge

When you need 100% battery (travel, long meetings, etc.):

1. Click the menu bar icon to open the dashboard
2. Click "Force Full Charge"
3. The button changes to "Resume Smart Charge" (red)
4. Charging continues to 100%, ignoring your thresholds
5. Once at 100%, the override automatically clears
6. Or click "Resume Smart Charge" to manually cancel the override

Note: Force Full Charge is disabled when not plugged in.

## Temperature Safety

Smart Charge includes temperature-based safety features:

| Temperature | Action |
|-------------|--------|
| Below 35°C | Normal operation |
| 35-38°C | Resume charging if previously paused for heat |
| 38-42°C | Pause charging until temperature drops |
| Above 42°C | Force stop all charging (safety cutoff) |

Temperature readings come from the battery sensor via IOKit.

## Coexistence with macOS

Smart Charge works alongside macOS features:

*   **System Preferences > Battery**: Your macOS battery settings remain in effect for features Smart Charge doesn't control.
*   **Optimized Battery Charging**: When macOS holds your battery at 80% due to usage patterns, Smart Charge detects this and backs off. You'll see a notification and can override with Force Full Charge.
*   **Low Power Mode**: Smart Charge respects system power states.

For best results with Smart Charge, you may want to disable "Optimized Battery Charging" in System Settings > Battery, but this is optional.
