import Foundation

public enum ChargeState: String, Codable, Sendable, CaseIterable {
    case charging
    case holdingAtLimit
    case waitingForRecharge
    case temporaryOverride
    case suspended
    case errorReadOnly
}
