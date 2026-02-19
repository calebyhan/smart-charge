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

        // Delay to allow window creation before bringing it to front
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // Find and focus the settings window
            for window in NSApp.windows {
                if window.title.contains("Settings") || window.title.contains("Preferences") {
                    window.level = .floating
                    window.orderFrontRegardless()
                    window.makeKeyAndOrderFront(nil)

                    // Ensure the app is activated after the window is ready
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }
}
