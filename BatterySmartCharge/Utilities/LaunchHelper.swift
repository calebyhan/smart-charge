import Foundation
import ServiceManagement

struct LaunchHelper {
    static func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                let service = SMAppService.mainApp
                if enabled {
                    try service.register()
                } else {
                    try service.unregister()
                }
            } catch {
                // Silently handle errors
            }
        }
    }
}
