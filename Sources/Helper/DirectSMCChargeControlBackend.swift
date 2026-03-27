import CellCapSMCBridge
import Core
import Darwin
import Foundation
import Shared

protocol SMCBridgeReading: Sendable {
    func readStatus() throws -> SMCBridgeStatus
    func setChargingEnabled(_ enabled: Bool) throws
}

protocol HelperPrivilegeProviding: Sendable {
    func hasWritePrivilege() -> Bool
}

struct ProcessPrivilegeProvider: HelperPrivilegeProviding {
    func hasWritePrivilege() -> Bool {
        geteuid() == 0
    }
}

struct SMCBridgeStatus: Sendable, Equatable {
    var serviceAvailable: Bool
    var legacyChargingKeysAvailable: Bool
    var tahoeChargingKeyAvailable: Bool
    var adapterKeyAvailable: Bool
    var batteryChargeKeyAvailable: Bool
    var acPowerKeyAvailable: Bool
    var chargingEnabledKnown: Bool
    var chargingEnabled: Bool
    var externalPowerKnown: Bool
    var externalPowerConnected: Bool
    var batteryChargePercent: Int?
}

struct SystemSMCBridge: SMCBridgeReading {
    func readStatus() throws -> SMCBridgeStatus {
        var status = CellCapSMCStatus()
        var errorBuffer = Array<CChar>(repeating: 0, count: 256)
        guard cellcap_smc_read_status(&status, &errorBuffer, Int32(errorBuffer.count)) else {
            throw ChargeControlBackendError.backendFailure(makeCStringMessage(errorBuffer))
        }

        return SMCBridgeStatus(
            serviceAvailable: status.serviceAvailable,
            legacyChargingKeysAvailable: status.legacyChargingKeysAvailable,
            tahoeChargingKeyAvailable: status.tahoeChargingKeyAvailable,
            adapterKeyAvailable: status.adapterKeyAvailable,
            batteryChargeKeyAvailable: status.batteryChargeKeyAvailable,
            acPowerKeyAvailable: status.acPowerKeyAvailable,
            chargingEnabledKnown: status.chargingEnabledKnown,
            chargingEnabled: status.chargingEnabled,
            externalPowerKnown: status.externalPowerKnown,
            externalPowerConnected: status.externalPowerConnected,
            batteryChargePercent: status.batteryChargePercent >= 0 ? Int(status.batteryChargePercent) : nil
        )
    }

    func setChargingEnabled(_ enabled: Bool) throws {
        var errorBuffer = Array<CChar>(repeating: 0, count: 256)
        guard cellcap_smc_set_charging_enabled(enabled, &errorBuffer, Int32(errorBuffer.count)) else {
            throw ChargeControlBackendError.backendFailure(makeCStringMessage(errorBuffer))
        }
    }
}

actor DirectSMCChargeControlBackend: ChargeControlBackend {
    private let bridge: any SMCBridgeReading
    private let environment: any SystemEnvironmentProviding
    private let privilegeProvider: any HelperPrivilegeProviding

    private var temporaryOverrideUntil: Date?
    private var stickyFailure: String?

    init(
        bridge: any SMCBridgeReading = SystemSMCBridge(),
        environment: any SystemEnvironmentProviding = ProcessInfoEnvironmentProvider(),
        privilegeProvider: any HelperPrivilegeProviding = ProcessPrivilegeProvider()
    ) {
        self.bridge = bridge
        self.environment = environment
        self.privilegeProvider = privilegeProvider
    }

    func probe(snapshot: BatterySnapshot?, now: Date) async -> ChargeControlCapability {
        normalizeOverride(now: now)
        let expectedVersion = CellCapHelperXPC.contractVersion
        let helperBaseStatus = HelperInstallStatus(
            state: .xpcReachable,
            serviceName: CellCapHelperXPC.serviceName,
            helperPath: CellCapHelperXPC.installedBinaryPath,
            plistPath: CellCapHelperXPC.launchDaemonPlistPath,
            helperVersion: expectedVersion,
            expectedVersion: expectedVersion,
            reason: "helper XPC에 도달했습니다.",
            checkedAt: now
        )

        guard environment.isAppleSilicon() else {
            return ChargeControlCapability(
                recommendedMode: .monitoringOnly,
                support: .unsupported,
                reason: "Apple Silicon 전용 충전 제어 경로입니다.",
                helperPrivilegeSupport: .readOnlyFallback,
                helperPrivilegeReason: "이 환경에서는 helper 권한 확인이 의미가 없습니다.",
                helperInstallStatus: helperBaseStatus,
                isChargingEnabled: nil,
                temporaryOverrideUntil: nil,
                lastErrorDescription: nil
            )
        }

        let version = environment.operatingSystemVersion
        guard version.majorVersion >= 26 else {
            return ChargeControlCapability(
                recommendedMode: .monitoringOnly,
                support: .unsupported,
                reason: "macOS 26 이상에서만 저수준 충전 제어를 시도합니다.",
                helperPrivilegeSupport: .readOnlyFallback,
                helperPrivilegeReason: "이 환경에서는 helper 권한 확인이 의미가 없습니다.",
                helperInstallStatus: helperBaseStatus,
                isChargingEnabled: nil,
                temporaryOverrideUntil: nil,
                lastErrorDescription: nil
            )
        }

        guard snapshot?.isBatteryPresent != false else {
            return ChargeControlCapability(
                recommendedMode: .monitoringOnly,
                support: .unsupported,
                reason: "내장 배터리가 없는 환경에서는 충전 제어를 수행할 수 없습니다.",
                helperPrivilegeSupport: .readOnlyFallback,
                helperPrivilegeReason: "내장 배터리가 없어 helper 권한 확인이 의미가 없습니다.",
                helperInstallStatus: helperBaseStatus,
                isChargingEnabled: nil,
                temporaryOverrideUntil: nil,
                lastErrorDescription: nil
            )
        }

        do {
            let status = try bridge.readStatus()
            guard status.serviceAvailable else {
                return ChargeControlCapability(
                    recommendedMode: .readOnly,
                    support: .readOnlyFallback,
                    reason: "AppleSMC 서비스에 연결하지 못했습니다.",
                    helperPrivilegeSupport: .readOnlyFallback,
                    helperPrivilegeReason: "AppleSMC 서비스에 연결하지 못했습니다.",
                    helperInstallStatus: HelperInstallStatus(
                        state: .permissionMismatch,
                        serviceName: helperBaseStatus.serviceName,
                        helperPath: helperBaseStatus.helperPath,
                        plistPath: helperBaseStatus.plistPath,
                        helperVersion: helperBaseStatus.helperVersion,
                        expectedVersion: helperBaseStatus.expectedVersion,
                        reason: "AppleSMC 서비스에 연결하지 못했습니다.",
                        checkedAt: now
                    ),
                    isChargingEnabled: nil,
                    temporaryOverrideUntil: temporaryOverrideUntil,
                    lastErrorDescription: stickyFailure
                )
            }

            let hasChargingControl = status.legacyChargingKeysAvailable || status.tahoeChargingKeyAvailable
            guard hasChargingControl else {
                return ChargeControlCapability(
                    recommendedMode: .monitoringOnly,
                    support: .unsupported,
                    reason: "이 기기에서는 알려진 충전 제어 SMC 키를 찾지 못했습니다.",
                    helperPrivilegeSupport: .readOnlyFallback,
                    helperPrivilegeReason: "충전 제어 SMC 키가 없어 helper 권한으로도 제어할 수 없습니다.",
                    helperInstallStatus: helperBaseStatus,
                    isChargingEnabled: status.chargingEnabledKnown ? status.chargingEnabled : nil,
                    temporaryOverrideUntil: temporaryOverrideUntil,
                    lastErrorDescription: nil
                )
            }

            guard privilegeProvider.hasWritePrivilege() else {
                return ChargeControlCapability(
                    recommendedMode: .readOnly,
                    support: .readOnlyFallback,
                    reason: "SMC 쓰기에는 root 권한 helper가 필요합니다.",
                    helperPrivilegeSupport: .readOnlyFallback,
                    helperPrivilegeReason: "SMC 쓰기에는 root 권한 helper가 필요합니다.",
                    helperInstallStatus: HelperInstallStatus(
                        state: .permissionMismatch,
                        serviceName: helperBaseStatus.serviceName,
                        helperPath: helperBaseStatus.helperPath,
                        plistPath: helperBaseStatus.plistPath,
                        helperVersion: helperBaseStatus.helperVersion,
                        expectedVersion: helperBaseStatus.expectedVersion,
                        reason: "SMC 쓰기에는 root 권한 helper가 필요합니다.",
                        checkedAt: now
                    ),
                    isChargingEnabled: status.chargingEnabledKnown ? status.chargingEnabled : nil,
                    temporaryOverrideUntil: temporaryOverrideUntil,
                    lastErrorDescription: stickyFailure
                )
            }

            if let stickyFailure {
                return ChargeControlCapability(
                    recommendedMode: .readOnly,
                    support: .readOnlyFallback,
                    reason: stickyFailure,
                    helperPrivilegeSupport: .supported,
                    helperPrivilegeReason: "helper는 root 권한으로 실행 중이지만 최근 명령 실패로 read-only 상태입니다.",
                    helperInstallStatus: helperBaseStatus,
                    isChargingEnabled: status.chargingEnabledKnown ? status.chargingEnabled : nil,
                    temporaryOverrideUntil: temporaryOverrideUntil,
                    lastErrorDescription: stickyFailure
                )
            }

            return ChargeControlCapability(
                recommendedMode: .fullControl,
                support: .experimental,
                reason: "비문서화된 SMC 기반 직접 충전 제어 backend가 활성화되었습니다.",
                helperPrivilegeSupport: .supported,
                helperPrivilegeReason: "helper가 root 권한으로 실행 중입니다.",
                helperInstallStatus: helperBaseStatus,
                isChargingEnabled: status.chargingEnabledKnown ? status.chargingEnabled : nil,
                temporaryOverrideUntil: temporaryOverrideUntil,
                lastErrorDescription: nil
            )
        } catch {
            let message = error.localizedDescription
            return ChargeControlCapability(
                recommendedMode: .readOnly,
                support: .readOnlyFallback,
                reason: message,
                helperPrivilegeSupport: .readOnlyFallback,
                helperPrivilegeReason: message,
                helperInstallStatus: HelperInstallStatus(
                    state: .permissionMismatch,
                    serviceName: helperBaseStatus.serviceName,
                    helperPath: helperBaseStatus.helperPath,
                    plistPath: helperBaseStatus.plistPath,
                    helperVersion: helperBaseStatus.helperVersion,
                    expectedVersion: helperBaseStatus.expectedVersion,
                    reason: message,
                    checkedAt: now
                ),
                isChargingEnabled: nil,
                temporaryOverrideUntil: temporaryOverrideUntil,
                lastErrorDescription: stickyFailure ?? message
            )
        }
    }

    func currentStatus(now: Date) async -> ChargeControlRuntimeStatus {
        normalizeOverride(now: now)

        let capability = await probe(snapshot: nil, now: now)
        return ChargeControlRuntimeStatus(
            recommendedMode: capability.recommendedMode,
            isChargingEnabled: capability.isChargingEnabled,
            temporaryOverrideUntil: temporaryOverrideUntil,
            lastErrorDescription: capability.lastErrorDescription,
            checkedAt: now
        )
    }

    func setChargingEnabled(_ enabled: Bool, now: Date) async throws -> ChargeControlRuntimeStatus {
        let capability = await probe(snapshot: nil, now: now)
        switch capability.recommendedMode {
        case .fullControl:
            break
        case .readOnly:
            throw ChargeControlBackendError.approvalRequired(capability.reason)
        case .monitoringOnly:
            throw ChargeControlBackendError.unsupportedEnvironment(capability.reason)
        }

        try bridge.setChargingEnabled(enabled)
        let refreshed = try bridge.readStatus()
        let actual = refreshed.chargingEnabledKnown ? refreshed.chargingEnabled : nil
        guard actual == enabled else {
            stickyFailure = ChargeControlBackendError.stateVerificationFailed(expected: enabled, actual: actual).localizedDescription
            throw ChargeControlBackendError.stateVerificationFailed(expected: enabled, actual: actual)
        }

        stickyFailure = nil
        return ChargeControlRuntimeStatus(
            recommendedMode: .fullControl,
            isChargingEnabled: actual,
            temporaryOverrideUntil: temporaryOverrideUntil,
            lastErrorDescription: nil,
            checkedAt: now
        )
    }

    func setTemporaryOverride(until: Date?, now: Date) async throws -> ChargeControlRuntimeStatus {
        if let until, until <= now {
            temporaryOverrideUntil = nil
            throw ChargeControlBackendError.commandRejected("temporary override 종료 시각이 이미 지났습니다.")
        }

        let capability = await probe(snapshot: nil, now: now)
        switch capability.recommendedMode {
        case .fullControl:
            temporaryOverrideUntil = until
            stickyFailure = nil
            return ChargeControlRuntimeStatus(
                recommendedMode: .fullControl,
                isChargingEnabled: capability.isChargingEnabled,
                temporaryOverrideUntil: temporaryOverrideUntil,
                lastErrorDescription: nil,
                checkedAt: now
            )
        case .readOnly:
            throw ChargeControlBackendError.approvalRequired(capability.reason)
        case .monitoringOnly:
            throw ChargeControlBackendError.unsupportedEnvironment(capability.reason)
        }
    }

    func selfTest(snapshot: BatterySnapshot?, now: Date) async -> ControllerSelfTestResult {
        let capability = await probe(snapshot: snapshot, now: now)
        switch capability.recommendedMode {
        case .fullControl:
            return ControllerSelfTestResult(
                outcome: .passed,
                message: "AppleSMC 연결과 충전 제어 키를 확인했습니다.",
                checkedAt: now
            )
        case .readOnly:
            return ControllerSelfTestResult(
                outcome: .degraded,
                message: capability.reason,
                checkedAt: now
            )
        case .monitoringOnly:
            return ControllerSelfTestResult(
                outcome: .failed,
                message: capability.reason,
                checkedAt: now
            )
        }
    }

    private func normalizeOverride(now: Date) {
        if let temporaryOverrideUntil, temporaryOverrideUntil <= now {
            self.temporaryOverrideUntil = nil
        }
    }
}

private func makeCStringMessage(_ buffer: [CChar]) -> String {
    let prefix = buffer.prefix { $0 != 0 }
    return String(decoding: prefix.map(UInt8.init(bitPattern:)), as: UTF8.self)
}
