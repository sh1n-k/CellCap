import Foundation
import Shared
import SystemSupport

final class CellCapHelperService: NSObject, CellCapHelperXPCProtocol {
    private let capabilityChecker: CapabilityChecker
    private let snapshotProvider: any BatterySnapshotProviding
    private let backend: any ChargeControlBackend

    init(
        capabilityChecker: CapabilityChecker = CapabilityChecker(),
        snapshotProvider: any BatterySnapshotProviding = SystemBatterySnapshotProvider(),
        backend: any ChargeControlBackend = DirectSMCChargeControlBackend()
    ) {
        self.capabilityChecker = capabilityChecker
        self.snapshotProvider = snapshotProvider
        self.backend = backend
    }

    func fetchControllerStatus(
        _ request: HelperRequestDTO,
        withReply reply: @escaping (HelperControllerStatusResponseDTO) -> Void
    ) {
        let requestedAt = request.requestedAt
        let backend = self.backend
        replyAsync(reply) {
            let runtimeStatus = await backend.currentStatus(now: requestedAt)
            let status = ControllerStatusDTO(status: makeHelperStatus(from: runtimeStatus))
            return HelperControllerStatusResponseDTO(status: status)
        }
    }

    func selfTest(
        _ request: HelperSelfTestRequestDTO,
        withReply reply: @escaping (HelperSelfTestResponseDTO) -> Void
    ) {
        let requestedAt = request.requestedAt
        let snapshotProvider = self.snapshotProvider
        let backend = self.backend
        replyAsync(reply) {
            let snapshot = currentSnapshot(from: snapshotProvider, now: requestedAt)
            let result = await backend.selfTest(snapshot: snapshot, now: requestedAt)
            let runtimeStatus = await backend.currentStatus(now: requestedAt)

            return HelperSelfTestResponseDTO(
                result: ControllerSelfTestResultDTO(result: result),
                status: ControllerStatusDTO(
                    status: makeHelperStatus(from: runtimeStatus)
                )
            )
        }
    }

    func capabilityProbe(
        _ request: HelperCapabilityProbeRequestDTO,
        withReply reply: @escaping (HelperCapabilityProbeResponseDTO) -> Void
    ) {
        let requestedAt = request.requestedAt
        let snapshotProvider = self.snapshotProvider
        let capabilityChecker = self.capabilityChecker
        let backend = self.backend
        replyAsync(reply) {
            let snapshot = currentSnapshot(from: snapshotProvider, now: requestedAt)
            let report = await makeCapabilityReport(
                snapshot: snapshot,
                now: requestedAt,
                capabilityChecker: capabilityChecker,
                backend: backend
            )
            let runtimeStatus = await backend.currentStatus(now: requestedAt)
            let status = makeHelperStatus(from: runtimeStatus)
            return HelperCapabilityProbeResponseDTO(
                report: CapabilityReportDTO(report: report),
                status: ControllerStatusDTO(status: status)
            )
        }
    }

    func setChargingEnabled(
        _ request: HelperSetChargingEnabledRequestDTO,
        withReply reply: @escaping (HelperCommandResponseDTO) -> Void
    ) {
        let requestedAt = request.requestedAt
        let enabled = request.enabled
        let backend = self.backend
        replyAsync(reply) {
            await performCommandResponse(
                code: "charging-command-failed",
                requestedAt: requestedAt,
                backend: backend
            ) {
                try await backend.setChargingEnabled(enabled, now: requestedAt)
            }
        }
    }

    func setTemporaryOverride(
        _ request: HelperSetTemporaryOverrideRequestDTO,
        withReply reply: @escaping (HelperCommandResponseDTO) -> Void
    ) {
        let requestedAt = request.requestedAt
        let until = request.until
        let backend = self.backend
        replyAsync(reply) {
            await performCommandResponse(
                code: "temporary-override-failed",
                requestedAt: requestedAt,
                backend: backend
            ) {
                try await backend.setTemporaryOverride(until: until, now: requestedAt)
            }
        }
    }
}

private final class ReplyBox<Response>: @unchecked Sendable {
    let reply: (Response) -> Void

    init(_ reply: @escaping (Response) -> Void) {
        self.reply = reply
    }
}

private func replyAsync<Response>(
    _ reply: @escaping (Response) -> Void,
    operation: @escaping @Sendable () async -> Response
) {
    let replyBox = ReplyBox(reply)
    Task {
        replyBox.reply(await operation())
    }
}

private func currentSnapshot(
    from snapshotProvider: any BatterySnapshotProviding,
    now: Date
) -> BatterySnapshot? {
    try? snapshotProvider.currentSnapshot(now: now)
}

private func performCommandResponse(
    code: String,
    requestedAt: Date,
    backend: any ChargeControlBackend,
    operation: @escaping @Sendable () async throws -> ChargeControlRuntimeStatus
) async -> HelperCommandResponseDTO {
    do {
        let runtimeStatus = try await operation()
        return HelperCommandResponseDTO(
            status: ControllerStatusDTO(status: makeHelperStatus(from: runtimeStatus))
        )
    } catch {
        let runtimeStatus = await backend.currentStatus(now: requestedAt)
        return HelperCommandResponseDTO(
            status: ControllerStatusDTO(
                status: makeHelperStatus(from: runtimeStatus)
            ),
            error: HelperXPCErrorDTO(
                code: code,
                message: error.localizedDescription,
                isRetryable: isRetryableHelperCommandError(error)
            )
        )
    }
}

private func isRetryableHelperCommandError(_ error: Error) -> Bool {
    guard let backendError = error as? ChargeControlBackendError else {
        return true
    }

    switch backendError {
    case .unsupportedEnvironment,
            .approvalRequired,
            .commandRejected:
        return false
    case .stateVerificationFailed,
            .backendFailure:
        return true
    }
}

private func makeCapabilityReport(
    snapshot: BatterySnapshot?,
    now: Date,
    capabilityChecker: CapabilityChecker,
    backend: any ChargeControlBackend
) async -> CapabilityReport {
    let baseReport = capabilityChecker.evaluate(snapshot: snapshot)
    let capability = await backend.probe(snapshot: snapshot, now: now)
    return CapabilityReport(
        statuses: baseReport.statuses.map { status in
            switch status.key {
            case .chargeControl:
                return CapabilityStatus(
                    key: .chargeControl,
                    support: capability.support,
                    reason: capability.reason
                )
            case .helperInstallation:
                return CapabilityStatus(
                    key: .helperInstallation,
                    support: capability.helperInstallStatus.installationSupport,
                    reason: capability.helperInstallStatus.reason
                )
            case .helperPrivilege:
                return CapabilityStatus(
                    key: .helperPrivilege,
                    support: capability.helperPrivilegeSupport,
                    reason: capability.helperPrivilegeReason
                )
            default:
                return status
            }
        },
        recommendedControllerMode: capability.recommendedMode,
        helperInstallStatus: capability.helperInstallStatus
    )
}

private func makeHelperStatus(from runtimeStatus: ChargeControlRuntimeStatus) -> ControllerStatus {
    ControllerStatus(
        mode: runtimeStatus.recommendedMode,
        helperConnection: .connected,
        isChargingEnabled: runtimeStatus.isChargingEnabled,
        temporaryOverrideUntil: runtimeStatus.temporaryOverrideUntil,
        lastErrorDescription: runtimeStatus.lastErrorDescription,
        checkedAt: runtimeStatus.checkedAt
    )
}
