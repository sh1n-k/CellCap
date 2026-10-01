@testable import Helper
import Foundation
import Shared
import SystemSupport
import Testing

@Test
func directBackendReturnsMonitoringOnlyOnUnsupportedArchitecture() async {
    let backend = DirectSMCChargeControlBackend(
        bridge: MockSMCBridge(status: .capableChargingDisabled),
        environment: MockSystemEnvironmentProvider(
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
            isAppleSilicon: false
        ),
        privilegeProvider: MockPrivilegeProvider(hasWritePrivilege: true)
    )

    let capability = await backend.probe(
        snapshot: BatterySnapshot(chargePercent: 60, isPowerConnected: true, isCharging: false, isBatteryPresent: true),
        now: Date(timeIntervalSince1970: 100)
    )

    #expect(capability.recommendedMode == .monitoringOnly)
    #expect(capability.support == .unsupported)
    #expect(capability.helperInstallStatus.state == .xpcReachable)
}

@Test
func directBackendReturnsReadOnlyWhenPrivilegeIsMissing() async {
    let backend = DirectSMCChargeControlBackend(
        bridge: MockSMCBridge(status: .capableChargingDisabled),
        environment: MockSystemEnvironmentProvider(
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
            isAppleSilicon: true
        ),
        privilegeProvider: MockPrivilegeProvider(hasWritePrivilege: false)
    )

    let capability = await backend.probe(
        snapshot: BatterySnapshot(chargePercent: 60, isPowerConnected: true, isCharging: false, isBatteryPresent: true),
        now: Date(timeIntervalSince1970: 100)
    )

    #expect(capability.recommendedMode == .readOnly)
    #expect(capability.support == .readOnlyFallback)
    #expect(capability.helperInstallStatus.state == .permissionMismatch)
}

@Test
func directBackendReturnsFullControlWhenSMCKeysAndPrivilegeAreAvailable() async {
    let backend = DirectSMCChargeControlBackend(
        bridge: MockSMCBridge(status: .capableChargingDisabled),
        environment: MockSystemEnvironmentProvider(
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
            isAppleSilicon: true
        ),
        privilegeProvider: MockPrivilegeProvider(hasWritePrivilege: true)
    )

    let capability = await backend.probe(
        snapshot: BatterySnapshot(chargePercent: 60, isPowerConnected: true, isCharging: false, isBatteryPresent: true),
        now: Date(timeIntervalSince1970: 100)
    )

    #expect(capability.recommendedMode == .fullControl)
    #expect(capability.isChargingEnabled == false)
    #expect(capability.helperInstallStatus.state == .xpcReachable)
}

@Test
func directBackendRejectsExpiredOverride() async {
    let backend = DirectSMCChargeControlBackend(
        bridge: MockSMCBridge(status: .capableChargingDisabled),
        environment: MockSystemEnvironmentProvider(
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
            isAppleSilicon: true
        ),
        privilegeProvider: MockPrivilegeProvider(hasWritePrivilege: true)
    )

    await #expect(throws: ChargeControlBackendError.self) {
        try await backend.setTemporaryOverride(
            until: Date(timeIntervalSince1970: 99),
            now: Date(timeIntervalSince1970: 100)
        )
    }
}

@Test
func directBackendFallsBackToReadOnlyAfterVerificationFailure() async {
    let bridge = MockSMCBridge(
        status: .capableChargingDisabled,
        postWriteStatus: .capableChargingDisabled
    )
    let backend = DirectSMCChargeControlBackend(
        bridge: bridge,
        environment: MockSystemEnvironmentProvider(
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
            isAppleSilicon: true
        ),
        privilegeProvider: MockPrivilegeProvider(hasWritePrivilege: true)
    )

    await #expect(throws: ChargeControlBackendError.self) {
        try await backend.setChargingEnabled(true, now: Date(timeIntervalSince1970: 100))
    }

    let capability = await backend.probe(
        snapshot: BatterySnapshot(chargePercent: 60, isPowerConnected: true, isCharging: false, isBatteryPresent: true),
        now: Date(timeIntervalSince1970: 101)
    )

    #expect(capability.recommendedMode == .readOnly)
    #expect(capability.lastErrorDescription != nil)
}

@Test
func directBackendReleaseControlEnablesChargingAfterStickyFailure() async throws {
    let bridge = MockSMCBridge(
        status: .capableChargingDisabled,
        postWriteStatus: .capableChargingDisabled
    )
    let backend = DirectSMCChargeControlBackend(
        bridge: bridge,
        environment: MockSystemEnvironmentProvider(
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
            isAppleSilicon: true
        ),
        privilegeProvider: MockPrivilegeProvider(hasWritePrivilege: true)
    )

    await #expect(throws: ChargeControlBackendError.self) {
        try await backend.setChargingEnabled(true, now: Date(timeIntervalSince1970: 100))
    }
    bridge.postWriteStatus = nil

    let released = try await backend.releaseControl(now: Date(timeIntervalSince1970: 101))

    #expect(released.isChargingEnabled == true)
    #expect(released.lastErrorDescription == nil)
}
