@testable import Helper
import Core
import Foundation
import Shared
import Testing

@Test
func directBackendReturnsMonitoringOnlyOnUnsupportedArchitecture() async {
    let backend = DirectSMCChargeControlBackend(
        bridge: MockSMCBridge(status: .capableChargingDisabled),
        environment: BackendMockEnvironmentProvider(
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
        environment: BackendMockEnvironmentProvider(
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
        environment: BackendMockEnvironmentProvider(
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
        environment: BackendMockEnvironmentProvider(
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
        environment: BackendMockEnvironmentProvider(
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

private final class MockSMCBridge: @unchecked Sendable, SMCBridgeReading {
    var status: SMCBridgeStatus
    var postWriteStatus: SMCBridgeStatus?

    init(status: SMCBridgeStatus, postWriteStatus: SMCBridgeStatus? = nil) {
        self.status = status
        self.postWriteStatus = postWriteStatus
    }

    func readStatus() throws -> SMCBridgeStatus {
        postWriteStatus ?? status
    }

    func setChargingEnabled(_ enabled: Bool) throws {
        status.chargingEnabledKnown = true
        status.chargingEnabled = enabled
    }
}

private struct BackendMockEnvironmentProvider: SystemEnvironmentProviding {
    let operatingSystemVersion: OperatingSystemVersion
    let isAppleSiliconValue: Bool

    init(operatingSystemVersion: OperatingSystemVersion, isAppleSilicon: Bool) {
        self.operatingSystemVersion = operatingSystemVersion
        self.isAppleSiliconValue = isAppleSilicon
    }

    func isAppleSilicon() -> Bool {
        isAppleSiliconValue
    }
}

private struct MockPrivilegeProvider: HelperPrivilegeProviding {
    let hasWritePrivilegeValue: Bool

    init(hasWritePrivilege: Bool) {
        self.hasWritePrivilegeValue = hasWritePrivilege
    }

    func hasWritePrivilege() -> Bool {
        hasWritePrivilegeValue
    }
}

private extension SMCBridgeStatus {
    static let capableChargingDisabled = SMCBridgeStatus(
        serviceAvailable: true,
        legacyChargingKeysAvailable: true,
        tahoeChargingKeyAvailable: false,
        adapterKeyAvailable: true,
        batteryChargeKeyAvailable: true,
        acPowerKeyAvailable: true,
        chargingEnabledKnown: true,
        chargingEnabled: false,
        externalPowerKnown: true,
        externalPowerConnected: true,
        batteryChargePercent: 82
    )
}
