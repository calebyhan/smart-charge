import Foundation

enum ChargingAction: Equatable {
    case chargeActive
    case chargeNormal
    case chargeTrickle
    case rest
    case forceStop
    
    var description: String {
        switch self {
        case .chargeActive: return "Active Charging"
        case .chargeNormal: return "Normal Charging"
        case .chargeTrickle: return "Trickle Charging"
        case .rest: return "Idle (Plugged In)"
        case .forceStop: return "Force Stop (Safety)"
        }
    }
}
