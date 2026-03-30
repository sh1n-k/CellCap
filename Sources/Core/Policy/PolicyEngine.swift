import Foundation
import Shared

public struct EffectiveChargePolicy: Sendable, Equatable {
    public var upperLimit: Int
    public var rechargeThreshold: Int
    public var temporaryOverrideUntil: Date?
    public var isTemporaryOverrideActive: Bool
    public var isControlEnabled: Bool

    public init(
        upperLimit: Int,
        rechargeThreshold: Int,
        temporaryOverrideUntil: Date?,
        isTemporaryOverrideActive: Bool,
        isControlEnabled: Bool
    ) {
        self.upperLimit = upperLimit
        self.rechargeThreshold = rechargeThreshold
        self.temporaryOverrideUntil = temporaryOverrideUntil
        self.isTemporaryOverrideActive = isTemporaryOverrideActive
        self.isControlEnabled = isControlEnabled
    }
}

public enum ChargingCommand: String, Sendable, Equatable, CaseIterable {
    case enableCharging
    case disableCharging
    case noChange
}

public struct PolicyEvaluation: Sendable, Equatable {
    public var effectivePolicy: EffectiveChargePolicy
    public var resolution: ChargeStateResolution
    public var transition: ChargeTransition
    public var chargingCommand: ChargingCommand

    public init(
        effectivePolicy: EffectiveChargePolicy,
        resolution: ChargeStateResolution,
        transition: ChargeTransition,
        chargingCommand: ChargingCommand
    ) {
        self.effectivePolicy = effectivePolicy
        self.resolution = resolution
        self.transition = transition
        self.chargingCommand = chargingCommand
    }
}

public struct PolicyEngine: Sendable {
    private let resolver: ChargeStateResolver

    public init(resolver: ChargeStateResolver = ChargeStateResolver()) {
        self.resolver = resolver
    }

    public func makeEffectivePolicy(
        from policy: ChargePolicy,
        now: Date = .now
    ) -> EffectiveChargePolicy {
        let upperLimit = min(
            ChargePolicy.maximumUpperLimit,
            max(ChargePolicy.minimumUpperLimit, policy.upperLimit)
        )
        let computedThreshold = policy.rechargeThreshold == upperLimit
            ? max(0, upperLimit - 5)
            : policy.rechargeThreshold
        let rechargeThreshold = min(upperLimit, max(0, computedThreshold))
        let temporaryOverrideUntil = policy.temporaryOverrideUntil.flatMap { overrideUntil in
            overrideUntil > now ? overrideUntil : nil
        }
        let isTemporaryOverrideActive = temporaryOverrideUntil != nil

        return EffectiveChargePolicy(
            upperLimit: upperLimit,
            rechargeThreshold: rechargeThreshold,
            temporaryOverrideUntil: temporaryOverrideUntil,
            isTemporaryOverrideActive: isTemporaryOverrideActive,
            isControlEnabled: policy.isControlEnabled
        )
    }

    public func chargingCommand(
        for state: ChargeState,
        controllerStatus: ControllerStatus
    ) -> ChargingCommand {
        switch state {
        case .charging, .temporaryOverride:
            return controllerStatus.isChargingEnabled == true ? .noChange : .enableCharging
        case .holdingAtLimit, .waitingForRecharge:
            return controllerStatus.isChargingEnabled == false ? .noChange : .disableCharging
        case .suspended, .errorReadOnly:
            return .noChange
        }
    }

    public func evaluate(
        context: ChargeStateContext,
        from previous: ChargeState
    ) -> PolicyEvaluation {
        let effectivePolicy = makeEffectivePolicy(from: context.policy, now: context.now)
        let resolution = resolver.resolve(context: context, effectivePolicy: effectivePolicy)
        let transition = ChargeTransition(
            previous: previous,
            current: resolution.state,
            reason: resolution.reason
        )

        return PolicyEvaluation(
            effectivePolicy: effectivePolicy,
            resolution: resolution,
            transition: transition,
            chargingCommand: chargingCommand(
                for: resolution.state,
                controllerStatus: context.controllerStatus
            )
        )
    }
}
