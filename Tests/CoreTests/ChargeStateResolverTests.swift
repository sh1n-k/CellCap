import Foundation
import Core
import Shared
import Testing

@Test
func resolverReturnsWaitingWithinPolicyBand() {
    let resolver = ChargeStateResolver()
    let effectivePolicy = EffectiveChargePolicy(
        upperLimit: 80,
        rechargeThreshold: 75,
        temporaryOverrideUntil: nil,
        isTemporaryOverrideActive: false,
        isControlEnabled: true
    )

    let resolution = resolver.resolve(
        context: ChargeStateContext(
            battery: BatterySnapshot(
                chargePercent: 77,
                isPowerConnected: true,
                isCharging: false
            ),
            policy: ChargePolicy(),
            controllerStatus: ControllerStatus(
                mode: .fullControl,
                helperConnection: .connected,
                isChargingEnabled: false
            ),
            now: Date(timeIntervalSince1970: 1_000)
        ),
        effectivePolicy: effectivePolicy
    )

    #expect(resolution.state == .waitingForRecharge)
    #expect(resolution.reason == .waitingWithinPolicyBand)
}

@Test
func resolverReturnsChargingAtOrBelowRechargeThreshold() {
    let resolver = ChargeStateResolver()
    let effectivePolicy = EffectiveChargePolicy(
        upperLimit: 60,
        rechargeThreshold: 55,
        temporaryOverrideUntil: nil,
        isTemporaryOverrideActive: false,
        isControlEnabled: true
    )

    let resolution = resolver.resolve(
        context: ChargeStateContext(
            battery: BatterySnapshot(
                chargePercent: 50,
                isPowerConnected: true,
                isCharging: false
            ),
            policy: ChargePolicy(),
            controllerStatus: ControllerStatus(
                mode: .fullControl,
                helperConnection: .connected,
                isChargingEnabled: false
            ),
            now: Date(timeIntervalSince1970: 1_000)
        ),
        effectivePolicy: effectivePolicy
    )

    #expect(resolution.state == .charging)
    #expect(resolution.reason == .belowRechargeThreshold)
}

@Test
func resolverReturnsHoldingAtLimitAtOrAboveUpperLimit() {
    let resolver = ChargeStateResolver()
    let effectivePolicy = EffectiveChargePolicy(
        upperLimit: 60,
        rechargeThreshold: 55,
        temporaryOverrideUntil: nil,
        isTemporaryOverrideActive: false,
        isControlEnabled: true
    )

    let resolution = resolver.resolve(
        context: ChargeStateContext(
            battery: BatterySnapshot(
                chargePercent: 60,
                isPowerConnected: true,
                isCharging: false
            ),
            policy: ChargePolicy(),
            controllerStatus: ControllerStatus(
                mode: .fullControl,
                helperConnection: .connected,
                isChargingEnabled: false
            ),
            now: Date(timeIntervalSince1970: 1_000)
        ),
        effectivePolicy: effectivePolicy
    )

    #expect(resolution.state == .holdingAtLimit)
    #expect(resolution.reason == .atUpperLimit)
}

@Test
func resolverHonorsControllerOverrideDeadline() {
    let resolver = ChargeStateResolver()
    let effectivePolicy = EffectiveChargePolicy(
        upperLimit: 80,
        rechargeThreshold: 75,
        temporaryOverrideUntil: nil,
        isTemporaryOverrideActive: false,
        isControlEnabled: true
    )

    let resolution = resolver.resolve(
        context: ChargeStateContext(
            battery: BatterySnapshot(
                chargePercent: 85,
                isPowerConnected: true,
                isCharging: false
            ),
            policy: ChargePolicy(),
            controllerStatus: ControllerStatus(
                mode: .fullControl,
                helperConnection: .connected,
                isChargingEnabled: true,
                temporaryOverrideUntil: Date(timeIntervalSince1970: 2_000)
            ),
            now: Date(timeIntervalSince1970: 1_500)
        ),
        effectivePolicy: effectivePolicy
    )

    #expect(resolution.state == .temporaryOverride)
    #expect(resolution.reason == .temporaryOverride)
}

@Test
func resolverPrefersLatestSnapshotWithinSameSourceRank() {
    let older = BatterySnapshot(
        chargePercent: 70,
        isPowerConnected: true,
        isCharging: false,
        observedAt: Date(timeIntervalSince1970: 100),
        source: .system
    )
    let newer = BatterySnapshot(
        chargePercent: 73,
        isPowerConnected: true,
        isCharging: false,
        observedAt: Date(timeIntervalSince1970: 200),
        source: .system
    )

    let selected = ChargeStateResolver.selectPreferredSnapshot(from: [older, newer])
    #expect(selected == newer)
}

@Test
func resolverCanUseCustomSnapshotHook() {
    let resolver = ChargeStateResolver { snapshots in
        snapshots.first { $0.source == .cached }
    }
    let effectivePolicy = EffectiveChargePolicy(
        upperLimit: 80,
        rechargeThreshold: 75,
        temporaryOverrideUntil: nil,
        isTemporaryOverrideActive: false,
        isControlEnabled: true
    )
    let systemSnapshot = BatterySnapshot(
        chargePercent: 82,
        isPowerConnected: true,
        isCharging: false,
        observedAt: Date(timeIntervalSince1970: 100),
        source: .system
    )
    let cachedSnapshot = BatterySnapshot(
        chargePercent: 60,
        isPowerConnected: true,
        isCharging: false,
        observedAt: Date(timeIntervalSince1970: 50),
        source: .cached
    )

    let resolution = resolver.resolve(
        context: ChargeStateContext(
            battery: nil,
            batterySnapshots: [systemSnapshot, cachedSnapshot],
            policy: ChargePolicy(),
            controllerStatus: ControllerStatus(
                mode: .fullControl,
                helperConnection: .connected
            ),
            now: Date(timeIntervalSince1970: 1_000)
        ),
        effectivePolicy: effectivePolicy
    )

    #expect(resolution.selectedBattery == cachedSnapshot)
    #expect(resolution.state == .charging)
}
