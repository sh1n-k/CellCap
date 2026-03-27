import Foundation

extension AppRuntimeTrigger {
    var debugName: String {
        switch self {
        case .appLaunch:
            return "appLaunch"
        case .manualRefresh:
            return "manualRefresh"
        case .policyChanged:
            return "policyChanged"
        case .batteryEvent(let trigger):
            return "batteryEvent:\(trigger.rawValue)"
        case .resynchronization:
            return "resynchronization"
        }
    }
}
