import Core
import Foundation
import Shared

protocol ChargeControlBackend: Sendable {
    func probe(snapshot: BatterySnapshot?, now: Date) async -> ChargeControlCapability
    func currentStatus(now: Date) async -> ChargeControlRuntimeStatus
    func setChargingEnabled(_ enabled: Bool, now: Date) async throws -> ChargeControlRuntimeStatus
    func setTemporaryOverride(until: Date?, now: Date) async throws -> ChargeControlRuntimeStatus
    func selfTest(snapshot: BatterySnapshot?, now: Date) async -> ControllerSelfTestResult
}

struct ChargeControlCapability: Sendable, Equatable {
    var recommendedMode: ControllerStatus.Mode
    var support: CapabilitySupport
    var reason: String
    var helperPrivilegeSupport: CapabilitySupport
    var helperPrivilegeReason: String
    var helperInstallStatus: HelperInstallStatus
    var isChargingEnabled: Bool?
    var temporaryOverrideUntil: Date?
    var lastErrorDescription: String?
}

struct ChargeControlRuntimeStatus: Sendable, Equatable {
    var recommendedMode: ControllerStatus.Mode
    var isChargingEnabled: Bool?
    var temporaryOverrideUntil: Date?
    var lastErrorDescription: String?
    var checkedAt: Date
}

enum ChargeControlBackendError: Error, LocalizedError, Sendable, Equatable {
    case unsupportedEnvironment(String)
    case approvalRequired(String)
    case commandRejected(String)
    case stateVerificationFailed(expected: Bool, actual: Bool?)
    case backendFailure(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedEnvironment(let message),
                .approvalRequired(let message),
                .commandRejected(let message),
                .backendFailure(let message):
            return message
        case .stateVerificationFailed(let expected, let actual):
            return "충전 상태 검증에 실패했습니다. expected=\(expected) actual=\(actual.map(String.init) ?? "nil")"
        }
    }
}

actor StubChargeControlBackend: ChargeControlBackend {
    func probe(snapshot: BatterySnapshot?, now: Date) async -> ChargeControlCapability {
        ChargeControlCapability(
            recommendedMode: .monitoringOnly,
            support: .unsupported,
            reason: "저수준 충전 제어 backend가 아직 연결되지 않았습니다.",
            helperPrivilegeSupport: .readOnlyFallback,
            helperPrivilegeReason: "helper 권한을 확인할 수 없습니다.",
            helperInstallStatus: HelperInstallStatus(
                state: .xpcReachable,
                serviceName: CellCapHelperXPC.serviceName,
                helperPath: CellCapHelperXPC.installedBinaryPath,
                plistPath: CellCapHelperXPC.launchDaemonPlistPath,
                helperVersion: CellCapHelperXPC.contractVersion,
                expectedVersion: CellCapHelperXPC.contractVersion,
                reason: "helper는 실행 중이지만 backend가 stub입니다.",
                checkedAt: now
            ),
            isChargingEnabled: nil,
            temporaryOverrideUntil: nil,
            lastErrorDescription: nil
        )
    }

    func currentStatus(now: Date) async -> ChargeControlRuntimeStatus {
        ChargeControlRuntimeStatus(
            recommendedMode: .monitoringOnly,
            isChargingEnabled: nil,
            temporaryOverrideUntil: nil,
            lastErrorDescription: nil,
            checkedAt: now
        )
    }

    func setChargingEnabled(_ enabled: Bool, now: Date) async throws -> ChargeControlRuntimeStatus {
        throw ChargeControlBackendError.unsupportedEnvironment("저수준 충전 제어 backend가 연결되지 않았습니다.")
    }

    func setTemporaryOverride(until: Date?, now: Date) async throws -> ChargeControlRuntimeStatus {
        throw ChargeControlBackendError.unsupportedEnvironment("저수준 충전 제어 backend가 연결되지 않았습니다.")
    }

    func selfTest(snapshot: BatterySnapshot?, now: Date) async -> ControllerSelfTestResult {
        ControllerSelfTestResult(
            outcome: .failed,
            message: "저수준 충전 제어 backend가 연결되지 않았습니다.",
            checkedAt: now
        )
    }
}
