import SwiftUI

@main
struct BatterySmartChargeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var manager = SmartChargeManager.shared

    var body: some Scene {
        Settings {
            SettingsView(settings: manager.settings)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    openSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    private func openSettingsWindow() {
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        // Bring settings window to front
        NSApp.activate(ignoringOtherApps: true)

        // Find and focus the settings window
        for window in NSApp.windows {
            if window.title.contains("Settings") || window.title.contains("Preferences") {
                window.makeKeyAndOrderFront(nil)
                window.level = .floating
            }
        }
    }
}
