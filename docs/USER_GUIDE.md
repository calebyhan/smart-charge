# User Guide

## Features & Charging Modes

Smart Charge offers flexible modes to balance battery health with your availability needs.

### 1. Availability Mode (Default)
**Best for**: General daily use.
- **Range**: Maintain 30% - 90%.
- **Behavior**: Ensures you always have enough power for meetings or travel, but avoids keeping the battery at 100% all the time (which causes stress).
- **Schedule**: Charges higher (80%) in the morning/evening, and maintains a moderate level (60-70%) during work hours while plugged in.

### 2. Longevity Mode
**Best for**: Desk warriors who are rarely unplugged.
- **Range**: Maintain 20% - 80%.
- **Behavior**: Aggressively minimizes battery stress. Keeps charge lower on average.

### 3. Custom Mode
**Best for**: Advanced users.
- Fully controls min/max thresholds.
- Unlimited custom time rules.

## Configuration

### Time Rules
You can set specific target ranges for different times of the day.

*   **Example**: "Commute Prep" - Charge to 90% between 7 AM and 8 AM.
*   **Example**: "Weekend Rest" - Maintain roughly 50% all weekend.

Rules are evaluated in order. If the current time matches a rule, that rule's target range is used.

### Power Draw Response
The app monitors how much power your laptop is using (CPU/GPU load).
*   **Light Usage**: The app may "trickle charge" (cycle on/off) even if below target, to reduce heat.
*   **Heavy Usage**: If you are rendering video or gaming, the app will switch to **Active Charging** to prevent battery drain, even if it exceeds your target slightly.

## User Interface

### Menu Bar
*   **Icon**: Shows the current status (Charging, Discharging, Smart Managed).
*   **Text**: Optional battery percentage display.

### Dashboard Popover
Click the menu bar icon to see:
*   **Sankey Diagram**: A flow chart showing where power is going (AC -> Battery -> System).
*   **Range Indicator**: Visual bar showing your current charge vs. your target range.
*   **Next Action**: Tells you what the Smart Algorithm is planning (e.g., "Will start charging in 5 minutes").

## Notifications

*   **Smart Charging Active**: "Maintaining 65% during work hours."
*   **High Power Draw**: "Switching to active charging to sustain load."
*   **Temperature Warning**: "Pausing charging until temperature drops below 38°C."
*   **Critical Temperature**: "Safety Stop: Battery at 43°C."
