import SwiftUI
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var manager = SmartChargeManager.shared // The source of truth
    var updateCheckTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable sudden termination to ensure applicationWillTerminate is always called
        // This is critical for re-enabling charging when the app quits
        ProcessInfo.processInfo.disableSuddenTermination()

        // Install privileged helper for power metrics (prompts for admin password on first run)
        PrivilegedHelperManager.shared.installHelperIfNeeded { _, _ in
            // Silent installation
        }

        // Set up launch at login based on user preference (default: true)
        LaunchHelper.setLaunchAtLogin(manager.settings.launchAtLogin)

        // Create the status item in the menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            // Set initial icon
            updateMenuBarIcon()
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Subscribe to battery state changes to update icon
        setupIconUpdateObserver()

        // Set up periodic update checks (daily)
        setupUpdateChecker()

        // Create the popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 500)
        popover.behavior = .transient
        // Inject manager here
        popover.contentViewController = NSHostingController(rootView: DashboardView(manager: manager))
        self.popover = popover
    }

    func applicationWillTerminate(_ notification: Notification) {
        // CRITICAL: Re-enable charging before quitting to prevent battery from being stuck
        // This ensures the battery can charge even when the app is not running
        do {
            try SMCController.shared.enableChargingSync()
        } catch {
            // Log error but continue quitting - this is a best-effort safety measure
            print("Warning: Failed to re-enable charging on quit: \(error)")
        }
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent, let button = statusItem?.button else { return }

        if event.type == .rightMouseUp {
            // Show context menu on right-click
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Quit Smart Charge", action: #selector(quitApp), keyEquivalent: "q"))
            statusItem?.menu = menu
            button.performClick(nil)
            statusItem?.menu = nil // Reset so left-click works again
        } else {
            // Toggle popover on left-click
            if let popover = popover {
                if popover.isShown {
                    popover.performClose(sender)
                } else {
                    // Activate the app so the popover is immediately interactive
                    NSApp.activate(ignoringOtherApps: true)
                    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                }
            }
        }
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Icon Update

    private func setupIconUpdateObserver() {
        // Observe battery state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateMenuBarIcon),
            name: NSNotification.Name("BatteryStateDidChange"),
            object: nil
        )
    }

    @objc private func updateMenuBarIcon() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let button = self.statusItem?.button else { return }

            let state = self.manager.monitor.state
            let action = self.manager.currentAction

            button.image = BatteryIconRenderer.renderIcon(
                percentage: state.percent,
                isCharging: state.isCharging,
                isPluggedIn: state.isPluggedIn,
                action: action
            )
        }
    }

    // MARK: - Update Checker

    private func setupUpdateChecker() {
        // Check for updates daily (24 hours)
        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
            // Update checks happen in DashboardView when popover opens
            // This timer is just a backstop for long-running sessions
            print("Daily update check timer fired")
        }
    }
}
