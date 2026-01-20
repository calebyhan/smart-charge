# Smart Charge Documentation

Welcome to the detailed documentation for Smart Charge.

## Table of Contents

*   **[User Guide](USER_GUIDE.md)**
    *   Detailed feature specifications.
    *   Configuration and "Charging Modes" (Availability, Longevity, Custom).
    *   User Interface reference (Dashboard, Settings).
    *   Notification types.

*   **[Architecture](ARCHITECTURE.md)**
    *   System components and diagrams.
    *   Data flow references.
    *   Core data models (`BatteryState`, `ChargingMode`, etc.).

*   **[Development](DEVELOPMENT.md)**
    *   Technical stack constraints and requirements.
    *   Project structure.
    *   SMC Integration details.
    *   Build and Release processes.

## Core Philosophy

*   **Availability First**: Never leave users stranded with low battery.
*   **Simple & Deterministic**: Time-based + power-draw logic, minimal "black box" pattern learning.
*   **Manual Control with Smart Defaults**: Users set rules, app executes intelligently.
*   **Native Experience**: Lightweight, fast, macOS-native UI.
