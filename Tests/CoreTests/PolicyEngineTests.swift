import Foundation
import Core
import Shared
import Testing

@Test
func policyEngineClampsLimitsIntoSupportedRange() {
    let engine = PolicyEngine()
    let effectivePolicy = engine.makeEffectivePolicy(
        from: ChargePolicy(
            upperLimit: 110,
            rechargeThreshold: 120
        )
    )

    #expect(effectivePolicy.upperLimit == 100)
    #expect(effectivePolicy.rechargeThreshold == 100)
}

@Test
func policyEngineKeepsRechargeThresholdBelowUpperLimit() {
    let engine = PolicyEngine()
    let effectivePolicy = engine.makeEffectivePolicy(
        from: ChargePolicy(
            upperLimit: 60,
            rechargeThreshold: 80
        )
    )

    #expect(effectivePolicy.upperLimit == 60)
    #expect(effectivePolicy.rechargeThreshold == 60)
}

@Test
func policyEngineMarksOverrideInactiveAfterDeadline() {
    let engine = PolicyEngine()
    let effectivePolicy = engine.makeEffectivePolicy(
        from: ChargePolicy(
            upperLimit: 80,
            rechargeThreshold: 75,
            temporaryOverrideUntil: Date(timeIntervalSince1970: 100)
        ),
        now: Date(timeIntervalSince1970: 200)
    )

    #expect(!effectivePolicy.isTemporaryOverrideActive)
}

@Test
func policyEngineRequestsChargingDisableAtLimit() {
    let engine = PolicyEngine()
    let evaluation = engine.evaluate(
        context: ChargeStateContext(
            battery: BatterySnapshot(
                chargePercent: 80,
                isPowerConnected: true,
                isCharging: true
            ),
            policy: ChargePolicy(upperLimit: 80, rechargeThreshold: 75),
            controllerStatus: ControllerStatus(
                mode: .fullControl,
                helperConnection: .connected,
                isChargingEnabled: true
            ),
            now: Date(timeIntervalSince1970: 1_000)
        ),
        from: .charging
    )

    #expect(evaluation.transition.current == .holdingAtLimit)
    #expect(evaluation.chargingCommand == .disableCharging)
}

@Test
func policyEngineKeepsChargingWithinBandAfterRechargeStarts() {
    let engine = PolicyEngine()
    let evaluation = engine.evaluate(
        context: ChargeStateContext(
            battery: BatterySnapshot(
                chargePercent: 56,
                isPowerConnected: true,
                isCharging: true
            ),
            policy: ChargePolicy(upperLimit: 60, rechargeThreshold: 55),
            controllerStatus: ControllerStatus(
                mode: .fullControl,
                helperConnection: .connected,
                isChargingEnabled: true
            ),
            now: Date(timeIntervalSince1970: 1_000)
        ),
        from: .charging
    )

    #expect(evaluation.transition.current == .charging)
    #expect(evaluation.transition.reason == .belowRechargeThreshold)
    #expect(evaluation.chargingCommand == .noChange)
}

@Test
func policyEngineWaitsWithinBandAfterHoldingAtLimit() {
    let engine = PolicyEngine()
    let evaluation = engine.evaluate(
        context: ChargeStateContext(
            battery: BatterySnapshot(
                chargePercent: 59,
                isPowerConnected: true,
                isCharging: false
            ),
            policy: ChargePolicy(upperLimit: 60, rechargeThreshold: 55),
            controllerStatus: ControllerStatus(
                mode: .fullControl,
                helperConnection: .connected,
                isChargingEnabled: false
            ),
            now: Date(timeIntervalSince1970: 1_000)
        ),
        from: .holdingAtLimit
    )

    #expect(evaluation.transition.current == .waitingForRecharge)
    #expect(evaluation.transition.reason == .waitingWithinPolicyBand)
    #expect(evaluation.chargingCommand == .noChange)
}

@Test
func policyEngineUsesSelectedSnapshotFromSourcePriority() {
    let engine = PolicyEngine()
    let cachedSnapshot = BatterySnapshot(
        chargePercent: 20,
        isPowerConnected: true,
        isCharging: false,
        observedAt: Date(timeIntervalSince1970: 1_000),
        source: .cached
    )
    let systemSnapshot = BatterySnapshot(
        chargePercent: 82,
        isPowerConnected: true,
        isCharging: false,
        observedAt: Date(timeIntervalSince1970: 900),
        source: .system
    )

    let evaluation = engine.evaluate(
        context: ChargeStateContext(
            battery: nil,
            batterySnapshots: [cachedSnapshot, systemSnapshot],
            policy: ChargePolicy(upperLimit: 80, rechargeThreshold: 75),
            controllerStatus: ControllerStatus(
                mode: .fullControl,
                helperConnection: .connected,
                isChargingEnabled: true
            ),
            now: Date(timeIntervalSince1970: 1_500)
        ),
        from: .charging
    )

    #expect(evaluation.resolution.selectedBattery == systemSnapshot)
    #expect(evaluation.transition.current == .holdingAtLimit)
}

@Test
func policyEngineClampsTooLowAndNegativeInputs() {
    let engine = PolicyEngine()
    let effectivePolicy = engine.makeEffectivePolicy(
        from: ChargePolicy(
            upperLimit: 10,
            rechargeThreshold: -20
        )
    )

    #expect(effectivePolicy.upperLimit == ChargePolicy.minimumUpperLimit)
    #expect(effectivePolicy.rechargeThreshold == 0)
}

@Test
func policyEngineReturnsToThresholdRulesAfterOverrideExpires() {
    let engine = PolicyEngine()
    let evaluation = engine.evaluate(
        context: ChargeStateContext(
            battery: BatterySnapshot(
                chargePercent: 80,
                isPowerConnected: true,
                isCharging: true
            ),
            policy: ChargePolicy(
                upperLimit: 80,
                rechargeThreshold: 75,
                temporaryOverrideUntil: Date(timeIntervalSince1970: 100)
            ),
            controllerStatus: ControllerStatus(
                mode: .fullControl,
                helperConnection: .connected,
                isChargingEnabled: true
            ),
            now: Date(timeIntervalSince1970: 200)
        ),
        from: .temporaryOverride
    )

    #expect(evaluation.effectivePolicy.isTemporaryOverrideActive == false)
    #expect(evaluation.transition.current == .holdingAtLimit)
    #expect(evaluation.transition.reason == .atUpperLimit)
}
