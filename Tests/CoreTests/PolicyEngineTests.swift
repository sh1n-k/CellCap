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
func policyEngineKeepsChargingWithinBandWhenControllerAlreadyAllowsCharging() {
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
        from: .suspended
    )

    #expect(evaluation.transition.current == .charging)
    #expect(evaluation.transition.reason == .belowRechargeThreshold)
}

@Test
func policyEngineReleasesChargeLimitWhenControlIsTurnedOff() {
    let engine = PolicyEngine()
    let evaluation = engine.evaluate(
        context: ChargeStateContext(
            battery: BatterySnapshot(
                chargePercent: 70,
                isPowerConnected: true,
                isCharging: false
            ),
            policy: ChargePolicy(upperLimit: 60, rechargeThreshold: 55, isControlEnabled: false),
            controllerStatus: ControllerStatus(
                mode: .fullControl,
                helperConnection: .connected,
                isChargingEnabled: false
            ),
            now: Date(timeIntervalSince1970: 1_000)
        ),
        from: .holdingAtLimit
    )

    #expect(evaluation.transition.current == .suspended)
    #expect(evaluation.transition.reason == .controlSuspended)
    #expect(evaluation.chargingCommand == .releaseControl)
}

@Test
func policyEngineReleasesChargeLimitEvenWhenHelperReportsError() {
    let engine = PolicyEngine()
    let evaluation = engine.evaluate(
        context: ChargeStateContext(
            battery: BatterySnapshot(chargePercent: 70, isPowerConnected: true, isCharging: false),
            policy: ChargePolicy(upperLimit: 60, rechargeThreshold: 55, isControlEnabled: false),
            controllerStatus: ControllerStatus(
                mode: .readOnly,
                helperConnection: .connected,
                isChargingEnabled: false,
                lastErrorDescription: "macOS가 CellCap 충전 한도(60%)를 적용하지 않았습니다."
            ),
            now: Date(timeIntervalSince1970: 1_000)
        ),
        from: .errorReadOnly
    )

    #expect(evaluation.transition.current == .errorReadOnly)
    #expect(evaluation.chargingCommand == .releaseControl)
}

@Test
func policyEngineDoesNotReleaseWithoutReachableControllableHelper() {
    let engine = PolicyEngine()
    for status in [
        ControllerStatus(mode: .monitoringOnly, helperConnection: .connected, isChargingEnabled: false),
        ControllerStatus(mode: .readOnly, helperConnection: .disconnected, isChargingEnabled: false),
        ControllerStatus(mode: .fullControl, helperConnection: .connected, isChargingEnabled: nil)
    ] {
        let evaluation = engine.evaluate(
            context: ChargeStateContext(
                battery: BatterySnapshot(chargePercent: 70, isPowerConnected: true, isCharging: false),
                policy: ChargePolicy(upperLimit: 60, rechargeThreshold: 55, isControlEnabled: false),
                controllerStatus: status,
                now: Date(timeIntervalSince1970: 1_000)
            ),
            from: .suspended
        )

        #expect(evaluation.chargingCommand == .noChange)
    }
}

@Test
func policyEngineRequestsReleaseWhenControlIsOffEvenIfChargingIsAllowed() {
    let engine = PolicyEngine()
    let evaluation = engine.evaluate(
        context: ChargeStateContext(
            battery: BatterySnapshot(
                chargePercent: 70,
                isPowerConnected: true,
                isCharging: true
            ),
            policy: ChargePolicy(upperLimit: 60, rechargeThreshold: 55, isControlEnabled: false),
            controllerStatus: ControllerStatus(
                mode: .fullControl,
                helperConnection: .connected,
                isChargingEnabled: true
            ),
            now: Date(timeIntervalSince1970: 1_000)
        ),
        from: .suspended
    )

    // 충전 허용(한도 100) 상태여도 사용자의 원래 macOS 한도로 되돌려야 하므로 해제를 요청한다.
    #expect(evaluation.transition.current == .suspended)
    #expect(evaluation.chargingCommand == .releaseControl)
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
