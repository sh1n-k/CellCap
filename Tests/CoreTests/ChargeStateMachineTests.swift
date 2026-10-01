import Foundation
import Core
import Shared
import Testing

@Test
func stateMachinePrefersReadOnlyWhenHelperFails() {
    let engine = PolicyEngine()
    let context = ChargeStateContext(
        battery: BatterySnapshot(chargePercent: 70, isPowerConnected: true, isCharging: false),
        policy: ChargePolicy(),
        controllerStatus: ControllerStatus(
            mode: .fullControl,
            helperConnection: .disconnected,
            lastErrorDescription: "XPC timeout"
        ),
        now: Date(timeIntervalSince1970: 1_000)
    )

    let result = engine.evaluate(context: context, from: .waitingForRecharge).resolution
    #expect(result.state == ChargeState.errorReadOnly)
    #expect(result.reason == ChargeTransitionReason.helperFailure)
}

@Test
func stateMachineReturnsTemporaryOverrideBeforeThresholdRules() {
    let engine = PolicyEngine()
    let context = ChargeStateContext(
        battery: BatterySnapshot(chargePercent: 81, isPowerConnected: true, isCharging: true),
        policy: ChargePolicy(
            upperLimit: 80,
            rechargeThreshold: 75,
            temporaryOverrideUntil: Date(timeIntervalSince1970: 2_000)
        ),
        controllerStatus: ControllerStatus(
            mode: .fullControl,
            helperConnection: .connected
        ),
        now: Date(timeIntervalSince1970: 1_500)
    )

    let result = engine.evaluate(context: context, from: .waitingForRecharge).resolution
    #expect(result.state == ChargeState.temporaryOverride)
    #expect(result.reason == ChargeTransitionReason.temporaryOverride)
}

@Test
func stateMachineReturnsChargingBelowRechargeThreshold() {
    let engine = PolicyEngine()
    let context = ChargeStateContext(
        battery: BatterySnapshot(chargePercent: 74, isPowerConnected: true, isCharging: false),
        policy: ChargePolicy(upperLimit: 80, rechargeThreshold: 75),
        controllerStatus: ControllerStatus(
            mode: .fullControl,
            helperConnection: .connected
        ),
        now: Date(timeIntervalSince1970: 1_000)
    )

    let transition = engine.evaluate(context: context, from: ChargeState.waitingForRecharge).transition
    #expect(transition.current == ChargeState.charging)
    #expect(transition.reason == ChargeTransitionReason.belowRechargeThreshold)
}

@Test
func stateMachineKeepsChargingAfterCrossingRechargeThresholdUntilUpperLimit() {
    let engine = PolicyEngine()
    let context = ChargeStateContext(
        battery: BatterySnapshot(chargePercent: 56, isPowerConnected: true, isCharging: true),
        policy: ChargePolicy(upperLimit: 60, rechargeThreshold: 55),
        controllerStatus: ControllerStatus(
            mode: .fullControl,
            helperConnection: .connected,
            isChargingEnabled: true
        ),
        now: Date(timeIntervalSince1970: 1_000)
    )

    let transition = engine.evaluate(context: context, from: .charging).transition
    #expect(transition.current == .charging)
    #expect(transition.reason == .belowRechargeThreshold)
}

@Test
func stateMachineWaitsWithinBandAfterHoldingAtLimit() {
    let engine = PolicyEngine()
    let context = ChargeStateContext(
        battery: BatterySnapshot(chargePercent: 56, isPowerConnected: true, isCharging: false),
        policy: ChargePolicy(upperLimit: 60, rechargeThreshold: 55),
        controllerStatus: ControllerStatus(
            mode: .fullControl,
            helperConnection: .connected,
            isChargingEnabled: false
        ),
        now: Date(timeIntervalSince1970: 1_000)
    )

    let transition = engine.evaluate(context: context, from: .holdingAtLimit).transition
    #expect(transition.current == .waitingForRecharge)
    #expect(transition.reason == .waitingWithinPolicyBand)
}

@Test
func stateMachineReturnsHoldingAtLimitWhenBatteryIsFullEnough() {
    let engine = PolicyEngine()
    let context = ChargeStateContext(
        battery: BatterySnapshot(chargePercent: 80, isPowerConnected: true, isCharging: false),
        policy: ChargePolicy(upperLimit: 80, rechargeThreshold: 75),
        controllerStatus: ControllerStatus(
            mode: .fullControl,
            helperConnection: .connected
        ),
        now: Date(timeIntervalSince1970: 1_000)
    )

    let result = engine.evaluate(context: context, from: .waitingForRecharge).resolution
    #expect(result.state == ChargeState.holdingAtLimit)
    #expect(result.reason == ChargeTransitionReason.atUpperLimit)
}

@Test
func stateMachineSuspendsWhenControlIsDisabled() {
    let engine = PolicyEngine()
    let context = ChargeStateContext(
        battery: BatterySnapshot(chargePercent: 70, isPowerConnected: true, isCharging: false),
        policy: ChargePolicy(isControlEnabled: false),
        controllerStatus: ControllerStatus(
            mode: .fullControl,
            helperConnection: .connected
        ),
        now: Date(timeIntervalSince1970: 1_000)
    )

    let result = engine.evaluate(context: context, from: .waitingForRecharge).resolution
    #expect(result.state == ChargeState.suspended)
    #expect(result.reason == ChargeTransitionReason.controlSuspended)
}

@Test
func stateMachineSuspendsWhenControllerIsReadOnlyWithoutFailure() {
    let engine = PolicyEngine()
    let context = ChargeStateContext(
        battery: BatterySnapshot(chargePercent: 70, isPowerConnected: true, isCharging: false),
        policy: ChargePolicy(isControlEnabled: true),
        controllerStatus: ControllerStatus(
            mode: .readOnly,
            helperConnection: .connected,
            isChargingEnabled: nil,
            lastErrorDescription: nil
        ),
        now: Date(timeIntervalSince1970: 1_000)
    )

    let result = engine.evaluate(context: context, from: .waitingForRecharge).resolution
    #expect(result.state == ChargeState.suspended)
    #expect(result.reason == ChargeTransitionReason.controlSuspended)
}
