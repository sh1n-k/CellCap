@testable import Helper
import Foundation
import Shared
import SystemSupport
import Testing

@Test
func helperServiceReflectsBackendCapabilityProbe() async {
    let service = CellCapHelperService(
        capabilityChecker: CapabilityChecker(
            environment: HelperMockEnvironmentProvider(
                operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
                isAppleSilicon: true
            )
        ),
        snapshotProvider: HelperFixedSnapshotProvider(
            snapshot: BatterySnapshot(
                chargePercent: 73,
                isPowerConnected: true,
                isCharging: false,
                isBatteryPresent: true
            )
        ),
        backend: HelperMockChargeControlBackend(
            capability: ChargeControlCapability(
                recommendedMode: .fullControl,
                support: .experimental,
                reason: "SMC backend ready",
                helperPrivilegeSupport: .supported,
                helperPrivilegeReason: "helper가 root 권한으로 실행 중입니다.",
                helperInstallStatus: HelperInstallStatus(
                    state: .xpcReachable,
                    serviceName: CellCapHelperXPC.serviceName,
                    helperPath: CellCapHelperXPC.installedBinaryPath,
                    plistPath: CellCapHelperXPC.launchDaemonPlistPath,
                    helperVersion: CellCapHelperXPC.contractVersion,
                    expectedVersion: CellCapHelperXPC.contractVersion,
                    reason: "helper XPC에 도달했습니다.",
                    checkedAt: Date(timeIntervalSince1970: 1_000)
                ),
                isChargingEnabled: false,
                temporaryOverrideUntil: nil,
                lastErrorDescription: nil
            ),
            runtimeStatus: ChargeControlRuntimeStatus(
                recommendedMode: .fullControl,
                isChargingEnabled: false,
                temporaryOverrideUntil: nil,
                lastErrorDescription: nil,
                checkedAt: Date(timeIntervalSince1970: 1_000)
            )
        )
    )

    let (report, status) = await withCheckedContinuation { continuation in
        service.capabilityProbe(HelperCapabilityProbeRequestDTO()) { response in
            continuation.resume(returning: (response.report.makeModel(), response.status.makeModel()))
        }
    }

    #expect(report.recommendedControllerMode == .fullControl)
    #expect(report.status(for: .chargeControl)?.support == .experimental)
    #expect(report.helperInstallStatus?.state == .xpcReachable)
    #expect(status.mode == .fullControl)
    #expect(status.isChargingEnabled == false)
}

@Test
func helperServiceReturnsStructuredErrorWhenChargingCommandFails() async {
    let service = CellCapHelperService(
        capabilityChecker: CapabilityChecker(
            environment: HelperMockEnvironmentProvider(
                operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
                isAppleSilicon: true
            )
        ),
        snapshotProvider: HelperFixedSnapshotProvider(
            snapshot: BatterySnapshot(
                chargePercent: 73,
                isPowerConnected: true,
                isCharging: false,
                isBatteryPresent: true
            )
        ),
        backend: HelperMockChargeControlBackend(
            capability: ChargeControlCapability(
                recommendedMode: .readOnly,
                support: .readOnlyFallback,
                reason: "root 권한 helper가 필요합니다.",
                helperPrivilegeSupport: .readOnlyFallback,
                helperPrivilegeReason: "root 권한 helper가 필요합니다.",
                helperInstallStatus: HelperInstallStatus(
                    state: .permissionMismatch,
                    serviceName: CellCapHelperXPC.serviceName,
                    helperPath: CellCapHelperXPC.installedBinaryPath,
                    plistPath: CellCapHelperXPC.launchDaemonPlistPath,
                    helperVersion: CellCapHelperXPC.contractVersion,
                    expectedVersion: CellCapHelperXPC.contractVersion,
                    reason: "root 권한 helper가 필요합니다.",
                    checkedAt: Date(timeIntervalSince1970: 2_000)
                ),
                isChargingEnabled: false,
                temporaryOverrideUntil: nil,
                lastErrorDescription: nil
            ),
            runtimeStatus: ChargeControlRuntimeStatus(
                recommendedMode: .readOnly,
                isChargingEnabled: false,
                temporaryOverrideUntil: nil,
                lastErrorDescription: nil,
                checkedAt: Date(timeIntervalSince1970: 2_000)
            ),
            chargingError: ChargeControlBackendError.approvalRequired("root 권한 helper가 필요합니다.")
        )
    )

    let (status, errorCode, retryable) = await withCheckedContinuation { continuation in
        service.setChargingEnabled(HelperSetChargingEnabledRequestDTO(enabled: false)) { response in
            continuation.resume(returning: (response.status.makeModel(), response.error?.code, response.error?.isRetryable))
        }
    }

    #expect(status.mode == .readOnly)
    #expect(status.isChargingEnabled == false)
    #expect(errorCode == "charging-command-failed")
    #expect(retryable == false)
}

@Test
func helperServiceMarksNonRetryableCommandErrors() async {
    let service = CellCapHelperService(
        capabilityChecker: CapabilityChecker(
            environment: HelperMockEnvironmentProvider(
                operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
                isAppleSilicon: true
            )
        ),
        snapshotProvider: HelperFixedSnapshotProvider(
            snapshot: BatterySnapshot(
                chargePercent: 73,
                isPowerConnected: true,
                isCharging: false,
                isBatteryPresent: true
            )
        ),
        backend: HelperMockChargeControlBackend(
            capability: ChargeControlCapability(
                recommendedMode: .fullControl,
                support: .experimental,
                reason: "SMC backend ready",
                helperPrivilegeSupport: .supported,
                helperPrivilegeReason: "helper가 root 권한으로 실행 중입니다.",
                helperInstallStatus: HelperInstallStatus(
                    state: .xpcReachable,
                    serviceName: CellCapHelperXPC.serviceName,
                    helperPath: CellCapHelperXPC.installedBinaryPath,
                    plistPath: CellCapHelperXPC.launchDaemonPlistPath,
                    helperVersion: CellCapHelperXPC.contractVersion,
                    expectedVersion: CellCapHelperXPC.contractVersion,
                    reason: "helper XPC에 도달했습니다.",
                    checkedAt: Date(timeIntervalSince1970: 2_100)
                ),
                isChargingEnabled: false,
                temporaryOverrideUntil: nil,
                lastErrorDescription: nil
            ),
            runtimeStatus: ChargeControlRuntimeStatus(
                recommendedMode: .fullControl,
                isChargingEnabled: false,
                temporaryOverrideUntil: nil,
                lastErrorDescription: nil,
                checkedAt: Date(timeIntervalSince1970: 2_100)
            ),
            temporaryOverrideError: ChargeControlBackendError.commandRejected("temporary override 종료 시각이 이미 지났습니다.")
        )
    )

    let retryable = await withCheckedContinuation { continuation in
        service.setTemporaryOverride(
            HelperSetTemporaryOverrideRequestDTO(until: Date(timeIntervalSince1970: 1_000))
        ) { response in
            continuation.resume(returning: response.error?.isRetryable)
        }
    }

    #expect(retryable == false)
}

@Test
func helperServiceMarksStateVerificationFailuresRetryable() async {
    let service = CellCapHelperService(
        capabilityChecker: CapabilityChecker(
            environment: HelperMockEnvironmentProvider(
                operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
                isAppleSilicon: true
            )
        ),
        snapshotProvider: HelperFixedSnapshotProvider(
            snapshot: BatterySnapshot(
                chargePercent: 73,
                isPowerConnected: true,
                isCharging: false,
                isBatteryPresent: true
            )
        ),
        backend: HelperMockChargeControlBackend(
            capability: ChargeControlCapability(
                recommendedMode: .fullControl,
                support: .experimental,
                reason: "SMC backend ready",
                helperPrivilegeSupport: .supported,
                helperPrivilegeReason: "helper가 root 권한으로 실행 중입니다.",
                helperInstallStatus: HelperInstallStatus(
                    state: .xpcReachable,
                    serviceName: CellCapHelperXPC.serviceName,
                    helperPath: CellCapHelperXPC.installedBinaryPath,
                    plistPath: CellCapHelperXPC.launchDaemonPlistPath,
                    helperVersion: CellCapHelperXPC.contractVersion,
                    expectedVersion: CellCapHelperXPC.contractVersion,
                    reason: "helper XPC에 도달했습니다.",
                    checkedAt: Date(timeIntervalSince1970: 2_200)
                ),
                isChargingEnabled: false,
                temporaryOverrideUntil: nil,
                lastErrorDescription: nil
            ),
            runtimeStatus: ChargeControlRuntimeStatus(
                recommendedMode: .fullControl,
                isChargingEnabled: false,
                temporaryOverrideUntil: nil,
                lastErrorDescription: nil,
                checkedAt: Date(timeIntervalSince1970: 2_200)
            ),
            chargingError: ChargeControlBackendError.stateVerificationFailed(expected: false, actual: true)
        )
    )

    let retryable = await withCheckedContinuation { continuation in
        service.setChargingEnabled(HelperSetChargingEnabledRequestDTO(enabled: false)) { response in
            continuation.resume(returning: response.error?.isRetryable)
        }
    }

    #expect(retryable == true)
}

@Test
func helperServiceMarksBackendFailuresRetryable() async {
    let service = CellCapHelperService(
        capabilityChecker: CapabilityChecker(
            environment: HelperMockEnvironmentProvider(
                operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
                isAppleSilicon: true
            )
        ),
        snapshotProvider: HelperFixedSnapshotProvider(
            snapshot: BatterySnapshot(
                chargePercent: 73,
                isPowerConnected: true,
                isCharging: false,
                isBatteryPresent: true
            )
        ),
        backend: HelperMockChargeControlBackend(
            capability: ChargeControlCapability(
                recommendedMode: .fullControl,
                support: .experimental,
                reason: "SMC backend ready",
                helperPrivilegeSupport: .supported,
                helperPrivilegeReason: "helper가 root 권한으로 실행 중입니다.",
                helperInstallStatus: HelperInstallStatus(
                    state: .xpcReachable,
                    serviceName: CellCapHelperXPC.serviceName,
                    helperPath: CellCapHelperXPC.installedBinaryPath,
                    plistPath: CellCapHelperXPC.launchDaemonPlistPath,
                    helperVersion: CellCapHelperXPC.contractVersion,
                    expectedVersion: CellCapHelperXPC.contractVersion,
                    reason: "helper XPC에 도달했습니다.",
                    checkedAt: Date(timeIntervalSince1970: 2_300)
                ),
                isChargingEnabled: false,
                temporaryOverrideUntil: nil,
                lastErrorDescription: nil
            ),
            runtimeStatus: ChargeControlRuntimeStatus(
                recommendedMode: .fullControl,
                isChargingEnabled: false,
                temporaryOverrideUntil: nil,
                lastErrorDescription: nil,
                checkedAt: Date(timeIntervalSince1970: 2_300)
            ),
            chargingError: ChargeControlBackendError.backendFailure("bridge I/O failed")
        )
    )

    let retryable = await withCheckedContinuation { continuation in
        service.setChargingEnabled(HelperSetChargingEnabledRequestDTO(enabled: false)) { response in
            continuation.resume(returning: response.error?.isRetryable)
        }
    }

    #expect(retryable == true)
}

@Test
func helperServiceMarksUnknownCommandErrorsRetryable() async {
    let service = CellCapHelperService(
        capabilityChecker: CapabilityChecker(
            environment: HelperMockEnvironmentProvider(
                operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
                isAppleSilicon: true
            )
        ),
        snapshotProvider: HelperFixedSnapshotProvider(
            snapshot: BatterySnapshot(
                chargePercent: 73,
                isPowerConnected: true,
                isCharging: false,
                isBatteryPresent: true
            )
        ),
        backend: HelperMockChargeControlBackend(
            capability: ChargeControlCapability(
                recommendedMode: .fullControl,
                support: .experimental,
                reason: "SMC backend ready",
                helperPrivilegeSupport: .supported,
                helperPrivilegeReason: "helper가 root 권한으로 실행 중입니다.",
                helperInstallStatus: HelperInstallStatus(
                    state: .xpcReachable,
                    serviceName: CellCapHelperXPC.serviceName,
                    helperPath: CellCapHelperXPC.installedBinaryPath,
                    plistPath: CellCapHelperXPC.launchDaemonPlistPath,
                    helperVersion: CellCapHelperXPC.contractVersion,
                    expectedVersion: CellCapHelperXPC.contractVersion,
                    reason: "helper XPC에 도달했습니다.",
                    checkedAt: Date(timeIntervalSince1970: 2_400)
                ),
                isChargingEnabled: false,
                temporaryOverrideUntil: nil,
                lastErrorDescription: nil
            ),
            runtimeStatus: ChargeControlRuntimeStatus(
                recommendedMode: .fullControl,
                isChargingEnabled: false,
                temporaryOverrideUntil: nil,
                lastErrorDescription: nil,
                checkedAt: Date(timeIntervalSince1970: 2_400)
            ),
            genericChargingError: HelperUnknownCommandError()
        )
    )

    let retryable = await withCheckedContinuation { continuation in
        service.setChargingEnabled(HelperSetChargingEnabledRequestDTO(enabled: false)) { response in
            continuation.resume(returning: response.error?.isRetryable)
        }
    }

    #expect(retryable == true)
}

private actor HelperMockChargeControlBackend: ChargeControlBackend {
    let capability: ChargeControlCapability
    let runtimeStatus: ChargeControlRuntimeStatus
    let chargingError: ChargeControlBackendError?
    let temporaryOverrideError: ChargeControlBackendError?
    let genericChargingError: HelperUnknownCommandError?

    init(
        capability: ChargeControlCapability,
        runtimeStatus: ChargeControlRuntimeStatus,
        chargingError: ChargeControlBackendError? = nil,
        temporaryOverrideError: ChargeControlBackendError? = nil,
        genericChargingError: HelperUnknownCommandError? = nil
    ) {
        self.capability = capability
        self.runtimeStatus = runtimeStatus
        self.chargingError = chargingError
        self.temporaryOverrideError = temporaryOverrideError
        self.genericChargingError = genericChargingError
    }

    func probe(snapshot: BatterySnapshot?, now: Date) async -> ChargeControlCapability {
        capability
    }

    func currentStatus(now: Date) async -> ChargeControlRuntimeStatus {
        runtimeStatus
    }

    func setChargingEnabled(_ enabled: Bool, now: Date) async throws -> ChargeControlRuntimeStatus {
        if let genericChargingError {
            throw genericChargingError
        }
        if let chargingError {
            throw chargingError
        }
        return runtimeStatus
    }

    func setTemporaryOverride(until: Date?, now: Date) async throws -> ChargeControlRuntimeStatus {
        if let temporaryOverrideError {
            throw temporaryOverrideError
        }
        return runtimeStatus
    }

    func selfTest(snapshot: BatterySnapshot?, now: Date) async -> ControllerSelfTestResult {
        ControllerSelfTestResult(outcome: .passed, message: "ok", checkedAt: now)
    }
}

private struct HelperFixedSnapshotProvider: BatterySnapshotProviding {
    let snapshot: BatterySnapshot?

    func currentSnapshot(now: Date) throws -> BatterySnapshot? {
        snapshot
    }
}

private struct HelperUnknownCommandError: Error, Sendable {}

private struct HelperMockEnvironmentProvider: SystemEnvironmentProviding {
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
