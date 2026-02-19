import SwiftUI
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var manager = SmartChargeManager.shared // The source of truth
    var updateCheckTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable sudden termination to ensure applicationWillTerminate is always called
        // This is critical for re-enabling charging when the app quits
        ProcessInfo.processInfo.disableSuddenTermination()

        // Disable battery CLI daemon to prevent conflicts with SmartCharge
        // The battery CLI has its own background daemon that can fight with our charging commands
        SMCController.shared.disableBatteryDaemon()

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
        popover.delegate = self
        // Inject manager here
        popover.contentViewController = NSHostingController(rootView: DashboardView(manager: manager))
        self.popover = popover
    }

    // MARK: - NSPopoverDelegate

    func popoverDidShow(_ notification: Notification) {
        // Ensure focus when popover appears
        // Small delay to ensure the window is fully created
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.activate(ignoringOtherApps: true)
            if let popoverWindow = self.popover?.contentViewController?.view.window {
                popoverWindow.makeKey()
                popoverWindow.orderFrontRegardless()
            }
        }
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
                    showPopover(relativeTo: button)
                }
            }
        }
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        guard let popover = popover else { return }

        // Activate app first
        NSApp.activate(ignoringOtherApps: true)

        // Show the popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Ensure the popover's window becomes key and is brought to front
        if let popoverWindow = popover.contentViewController?.view.window {
            popoverWindow.makeKey()
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
