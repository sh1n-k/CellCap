import Foundation
import Shared

public struct ChargeStateContext: Sendable, Equatable {
    public var battery: BatterySnapshot?
    public var policy: ChargePolicy
    public var controllerStatus: ControllerStatus
    public var now: Date

    public init(
        battery: BatterySnapshot?,
        policy: ChargePolicy,
        controllerStatus: ControllerStatus,
        now: Date = .now
    ) {
        self.battery = battery
        self.policy = policy
        self.controllerStatus = controllerStatus
        self.now = now
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

public struct ChargeStateMachine: Sendable {
    public init() {}

    public func transition(
        from previous: ChargeState,
        context: ChargeStateContext
    ) -> ChargeTransition {
        let result = resolve(context: context)
        return ChargeTransition(previous: previous, current: result.state, reason: result.reason)
    }

    public func resolve(context: ChargeStateContext) -> (state: ChargeState, reason: ChargeTransitionReason) {
        guard let battery = context.battery, battery.isBatteryPresent else {
            return (.suspended, .missingBattery)
        }

        if context.controllerStatus.helperConnection != .connected || context.controllerStatus.lastErrorDescription != nil {
            return (.errorReadOnly, .helperFailure)
        }

        if context.controllerStatus.mode != .fullControl || !context.policy.isControlEnabled {
            return (.suspended, .controlSuspended)
        }

        if context.policy.isTemporaryOverrideActive(at: context.now)
            || (context.controllerStatus.temporaryOverrideUntil.map { $0 > context.now } ?? false) {
            return (.temporaryOverride, .temporaryOverride)
        }

        if battery.chargePercent >= context.policy.upperLimit {
            return (.holdingAtLimit, .atUpperLimit)
        }

        if battery.chargePercent <= context.policy.rechargeThreshold {
            return (.charging, .belowRechargeThreshold)
        }

        return (.waitingForRecharge, .waitingWithinPolicyBand)
    }
}
