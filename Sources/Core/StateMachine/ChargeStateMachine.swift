import Foundation
import Shared

public struct ChargeStateContext: Sendable, Equatable {
    public var battery: BatterySnapshot?
    public var batterySnapshots: [BatterySnapshot]
    public var policy: ChargePolicy
    public var controllerStatus: ControllerStatus
    public var now: Date

    public init(
        battery: BatterySnapshot?,
        batterySnapshots: [BatterySnapshot] = [],
        policy: ChargePolicy,
        controllerStatus: ControllerStatus,
        now: Date = .now
    ) {
        self.battery = battery
        self.batterySnapshots = batterySnapshots
        self.policy = policy
        self.controllerStatus = controllerStatus
        self.now = now
    }

    public var snapshotCandidates: [BatterySnapshot] {
        if batterySnapshots.isEmpty {
            return battery.map { [$0] } ?? []
        }

        if let battery {
            return [battery] + batterySnapshots
        }

        return batterySnapshots
    }
}

public enum ChargeTransitionReason: String, Sendable, Equatable, CaseIterable {
    case missingBattery
    case helperFailure
    case controlSuspended
    case temporaryOverride
    case atUpperLimit
    case belowRechargeThreshold
    case waitingWithinPolicyBand
}

public struct ChargeTransition: Sendable, Equatable {
    public var previous: ChargeState
    public var current: ChargeState
    public var reason: ChargeTransitionReason

    public init(previous: ChargeState, current: ChargeState, reason: ChargeTransitionReason) {
        self.previous = previous
        self.current = current
        self.reason = reason
    }
}
