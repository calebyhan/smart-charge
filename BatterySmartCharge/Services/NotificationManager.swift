import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()

    // Debounce state for action notifications
    private var lastActionNotificationTime: Date = .distantPast
    private let actionNotificationInterval: TimeInterval = 30  // Max once per 30s

    init() {
        if isBundleValid {
            requestAuthorization()
        }
    }

    private var isBundleValid: Bool {
        return Bundle.main.bundleIdentifier != nil
    }
    
    func requestAuthorization() {
        guard isBundleValid else { return }
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            // Silently handle authorization result
        }
    }
    
    func sendNotification(title: String, body: String, id: String = UUID().uuidString) {
        guard isBundleValid else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func notifyChargingStateChanged(to action: ChargingAction) {
        let now = Date()
        guard now.timeIntervalSince(lastActionNotificationTime) >= actionNotificationInterval else {
            return  // Debounce: skip notification if sent recently
        }
        lastActionNotificationTime = now
        sendNotification(
            title: "Charging Status Updated",
            body: "Switched to: \(action.description)"
        )
    }
    
    func notifyHighTemperature(temp: Double) {
        sendNotification(
            title: "High Temperature Warning",
            body: "Battery temperature is \(String(format: "%.1f", temp))°C. Charging paused."
        )
    }
    
    func notifySafetyStop(temp: Double) {
        sendNotification(
            title: "Safety Cutoff Triggered",
            body: "Battery reached \(String(format: "%.1f", temp))°C. All charging forced off."
        )
    }
}
