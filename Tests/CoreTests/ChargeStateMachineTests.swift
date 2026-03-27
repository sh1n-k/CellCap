import Foundation
import Core
import Shared
import Testing

@Test
func stateMachinePrefersReadOnlyWhenHelperFails() {
    let machine = ChargeStateMachine()
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

    let result = machine.resolve(context: context)
    #expect(result.state == ChargeState.errorReadOnly)
    #expect(result.reason == ChargeTransitionReason.helperFailure)
}

@Test
func stateMachineReturnsTemporaryOverrideBeforeThresholdRules() {
    let machine = ChargeStateMachine()
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

    let result = machine.resolve(context: context)
    #expect(result.state == ChargeState.temporaryOverride)
    #expect(result.reason == ChargeTransitionReason.temporaryOverride)
}

@Test
func stateMachineReturnsChargingBelowRechargeThreshold() {
    let machine = ChargeStateMachine()
    let context = ChargeStateContext(
        battery: BatterySnapshot(chargePercent: 74, isPowerConnected: true, isCharging: false),
        policy: ChargePolicy(upperLimit: 80, rechargeThreshold: 75),
        controllerStatus: ControllerStatus(
            mode: .fullControl,
            helperConnection: .connected
        ),
        now: Date(timeIntervalSince1970: 1_000)
    )

    let transition = machine.transition(from: ChargeState.waitingForRecharge, context: context)
    #expect(transition.current == ChargeState.charging)
    #expect(transition.reason == ChargeTransitionReason.belowRechargeThreshold)
}

@Test
func stateMachineReturnsHoldingAtLimitWhenBatteryIsFullEnough() {
    let machine = ChargeStateMachine()
    let context = ChargeStateContext(
        battery: BatterySnapshot(chargePercent: 80, isPowerConnected: true, isCharging: false),
        policy: ChargePolicy(upperLimit: 80, rechargeThreshold: 75),
        controllerStatus: ControllerStatus(
            mode: .fullControl,
            helperConnection: .connected
        ),
        now: Date(timeIntervalSince1970: 1_000)
    )

    let result = machine.resolve(context: context)
    #expect(result.state == ChargeState.holdingAtLimit)
    #expect(result.reason == ChargeTransitionReason.atUpperLimit)
}

@Test
func stateMachineSuspendsWhenControlIsDisabled() {
    let machine = ChargeStateMachine()
    let context = ChargeStateContext(
        battery: BatterySnapshot(chargePercent: 70, isPowerConnected: true, isCharging: false),
        policy: ChargePolicy(isControlEnabled: false),
        controllerStatus: ControllerStatus(
            mode: .fullControl,
            helperConnection: .connected
        ),
        now: Date(timeIntervalSince1970: 1_000)
    )

    let result = machine.resolve(context: context)
    #expect(result.state == ChargeState.suspended)
    #expect(result.reason == ChargeTransitionReason.controlSuspended)
}

@Test
func stateMachineSuspendsWhenControllerIsReadOnlyWithoutFailure() {
    let machine = ChargeStateMachine()
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

    let result = machine.resolve(context: context)
    #expect(result.state == ChargeState.suspended)
    #expect(result.reason == ChargeTransitionReason.controlSuspended)
}
