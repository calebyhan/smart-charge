import Foundation

enum ChargingAction: String, Equatable, Codable {
    case chargeActive   // Enable charging
    case rest           // Disable charging (normal operation)
    case forceStop      // Disable charging (safety cutoff)

    var description: String {
        switch self {
        case .chargeActive: return "Charging"
        case .rest: return "Not Charging"
        case .forceStop: return "Stopped (Safety)"
        }
    }

    /// Whether this action results in charging being enabled
    var isCharging: Bool {
        self == .chargeActive
    }
}
