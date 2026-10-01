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
    /// 제어 OFF: helper가 건 제한을 풀고 시스템 충전 한도를 원래 값으로 되돌린다.
    case releaseControl
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
        let rawResolution = resolver.resolve(context: context, effectivePolicy: effectivePolicy)
        let resolution = stabilizedResolution(
            rawResolution,
            previous: previous,
            effectivePolicy: effectivePolicy,
            controllerStatus: context.controllerStatus
        )
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
                for: resolution,
                effectivePolicy: effectivePolicy,
                controllerStatus: context.controllerStatus
            )
        )
    }

    private func chargingCommand(
        for resolution: ChargeStateResolution,
        effectivePolicy: EffectiveChargePolicy,
        controllerStatus: ControllerStatus
    ) -> ChargingCommand {
        // 사용자가 제어를 끄면 helper에 남은 충전 제한을 해제한다. 시스템 충전 한도
        // backend는 한도가 재부팅 후에도 유지되므로, helper가 오류·read-only 상태여도 해제를 시도한다.
        if !effectivePolicy.isControlEnabled {
            // nil(상태 모름)이면 helper가 제한을 건 적이 없으므로 해제하지 않는다.
            // 같은 제어 OFF 구간에서 해제가 한 번 성공하면 ControllerCommandApplier가 반복 전송을 막는다.
            guard controllerStatus.helperConnection == .connected,
                  controllerStatus.mode != .monitoringOnly,
                  controllerStatus.isChargingEnabled != nil else {
                return .noChange
            }
            return .releaseControl
        }

        return chargingCommand(for: resolution.state, controllerStatus: controllerStatus)
    }

    private func stabilizedResolution(
        _ resolution: ChargeStateResolution,
        previous: ChargeState,
        effectivePolicy: EffectiveChargePolicy,
        controllerStatus: ControllerStatus
    ) -> ChargeStateResolution {
        guard resolution.reason == .waitingWithinPolicyBand else {
            return resolution
        }

        guard controllerStatus.mode == .fullControl, effectivePolicy.isControlEnabled else {
            return resolution
        }

        if controllerStatus.isChargingEnabled == true {
            return ChargeStateResolution(
                state: .charging,
                reason: .belowRechargeThreshold,
                selectedBattery: resolution.selectedBattery
            )
        }

        switch previous {
        case .charging:
            return ChargeStateResolution(
                state: .charging,
                reason: .belowRechargeThreshold,
                selectedBattery: resolution.selectedBattery
            )
        case .holdingAtLimit, .waitingForRecharge, .suspended, .errorReadOnly:
            return resolution
        case .temporaryOverride:
            return ChargeStateResolution(
                state: .waitingForRecharge,
                reason: .waitingWithinPolicyBand,
                selectedBattery: resolution.selectedBattery
            )
        }
    }
}
