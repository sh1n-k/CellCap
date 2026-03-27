import Foundation

public struct AppState: Codable, Sendable, Equatable {
    public var battery: BatterySnapshot?
    public var policy: ChargePolicy
    public var controllerStatus: ControllerStatus
    public var chargeState: ChargeState
    public var lastUpdatedAt: Date

    public init(
        battery: BatterySnapshot?,
        policy: ChargePolicy,
        controllerStatus: ControllerStatus,
        chargeState: ChargeState,
        lastUpdatedAt: Date = .now
    ) {
        self.battery = battery
        self.policy = policy
        self.controllerStatus = controllerStatus
        self.chargeState = chargeState
        self.lastUpdatedAt = lastUpdatedAt
    }
}
