import Core
import Foundation
import Shared

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
        let replyBox = ReplyBox(reply)
        let requestedAt = request.requestedAt
        let backend = self.backend
        Task {
            let runtimeStatus = await backend.currentStatus(now: requestedAt)
            let status = makeHelperStatus(from: runtimeStatus)
            replyBox.reply(HelperControllerStatusResponseDTO(status: ControllerStatusDTO(status: status)))
        }
    }

    func selfTest(
        _ request: HelperSelfTestRequestDTO,
        withReply reply: @escaping (HelperSelfTestResponseDTO) -> Void
    ) {
        let replyBox = ReplyBox(reply)
        let requestedAt = request.requestedAt
        let snapshotProvider = self.snapshotProvider
        let backend = self.backend
        Task {
            let snapshot = try? snapshotProvider.currentSnapshot(now: requestedAt)
            let result = await backend.selfTest(snapshot: snapshot, now: requestedAt)
            let runtimeStatus = await backend.currentStatus(now: requestedAt)

            replyBox.reply(
                HelperSelfTestResponseDTO(
                    result: ControllerSelfTestResultDTO(result: result),
                    status: ControllerStatusDTO(
                        status: makeHelperStatus(from: runtimeStatus)
                    )
                )
            )
        }
    }

    func capabilityProbe(
        _ request: HelperCapabilityProbeRequestDTO,
        withReply reply: @escaping (HelperCapabilityProbeResponseDTO) -> Void
    ) {
        let replyBox = ReplyBox(reply)
        let requestedAt = request.requestedAt
        let snapshotProvider = self.snapshotProvider
        let capabilityChecker = self.capabilityChecker
        let backend = self.backend
        Task {
            let snapshot = try? snapshotProvider.currentSnapshot(now: requestedAt)
            let report = await makeCapabilityReport(
                snapshot: snapshot,
                now: requestedAt,
                capabilityChecker: capabilityChecker,
                backend: backend
            )
            let runtimeStatus = await backend.currentStatus(now: requestedAt)
            let status = makeHelperStatus(from: runtimeStatus)
            replyBox.reply(
                HelperCapabilityProbeResponseDTO(
                    report: CapabilityReportDTO(report: report),
                    status: ControllerStatusDTO(status: status)
                )
            )
        }
    }

    func setChargingEnabled(
        _ request: HelperSetChargingEnabledRequestDTO,
        withReply reply: @escaping (HelperCommandResponseDTO) -> Void
    ) {
        let replyBox = ReplyBox(reply)
        let requestedAt = request.requestedAt
        let enabled = request.enabled
        let backend = self.backend
        Task {
            do {
                let runtimeStatus = try await backend.setChargingEnabled(enabled, now: requestedAt)
                let status = ControllerStatusDTO(
                    status: makeHelperStatus(from: runtimeStatus)
                )
                replyBox.reply(HelperCommandResponseDTO(status: status))
            } catch {
                let runtimeStatus = await backend.currentStatus(now: requestedAt)
                replyBox.reply(
                    HelperCommandResponseDTO(
                        status: ControllerStatusDTO(
                            status: makeHelperStatus(from: runtimeStatus)
                        ),
                        error: HelperXPCErrorDTO(
                            code: "charging-command-failed",
                            message: error.localizedDescription,
                            isRetryable: true
                        )
                    )
                )
            }
        }
    }

    func setTemporaryOverride(
        _ request: HelperSetTemporaryOverrideRequestDTO,
        withReply reply: @escaping (HelperCommandResponseDTO) -> Void
    ) {
        let replyBox = ReplyBox(reply)
        let requestedAt = request.requestedAt
        let until = request.until
        let backend = self.backend
        Task {
            do {
                let runtimeStatus = try await backend.setTemporaryOverride(until: until, now: requestedAt)
                let status = ControllerStatusDTO(
                    status: makeHelperStatus(from: runtimeStatus)
                )
                replyBox.reply(HelperCommandResponseDTO(status: status))
            } catch {
                let runtimeStatus = await backend.currentStatus(now: requestedAt)
                replyBox.reply(
                    HelperCommandResponseDTO(
                        status: ControllerStatusDTO(
                            status: makeHelperStatus(from: runtimeStatus)
                        ),
                        error: HelperXPCErrorDTO(
                            code: "temporary-override-failed",
                            message: error.localizedDescription,
                            isRetryable: true
                        )
                    )
                )
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
