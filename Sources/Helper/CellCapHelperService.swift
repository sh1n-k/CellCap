import Core
import Foundation
import Shared

final class CellCapHelperService: NSObject, CellCapHelperXPCProtocol {
    private let capabilityChecker: CapabilityChecker
    private let snapshotProvider: any BatterySnapshotProviding

    init(
        capabilityChecker: CapabilityChecker = CapabilityChecker(),
        snapshotProvider: any BatterySnapshotProviding = SystemBatterySnapshotProvider()
    ) {
        self.capabilityChecker = capabilityChecker
        self.snapshotProvider = snapshotProvider
    }

    func fetchControllerStatus(
        _ request: HelperRequestDTO,
        withReply reply: @escaping (HelperControllerStatusResponseDTO) -> Void
    ) {
        let snapshot = try? snapshotProvider.currentSnapshot(now: request.requestedAt)
        let report = capabilityChecker.evaluate(snapshot: snapshot)
        let status = makeStatus(
            recommendedMode: report.recommendedControllerMode,
            lastErrorDescription: nil,
            checkedAt: request.requestedAt
        )
        reply(HelperControllerStatusResponseDTO(status: ControllerStatusDTO(status: status)))
    }

    func selfTest(
        _ request: HelperSelfTestRequestDTO,
        withReply reply: @escaping (HelperSelfTestResponseDTO) -> Void
    ) {
        let snapshot = try? snapshotProvider.currentSnapshot(now: request.requestedAt)
        let report = capabilityChecker.evaluate(snapshot: snapshot)
        let outcome: ControllerSelfTestResult.Outcome = snapshot == nil ? .failed : .degraded
        let result = ControllerSelfTestResult(
            outcome: outcome,
            message: "Helper XPC 골격은 동작하지만 실제 충전 제어는 아직 stub 상태입니다.",
            checkedAt: request.requestedAt
        )

        reply(
            HelperSelfTestResponseDTO(
                result: ControllerSelfTestResultDTO(result: result),
                status: ControllerStatusDTO(
                    status: makeStatus(
                        recommendedMode: report.recommendedControllerMode,
                        lastErrorDescription: snapshot == nil ? "배터리 스냅샷을 읽지 못했습니다." : nil,
                        checkedAt: request.requestedAt
                    )
                )
            )
        )
    }

    func capabilityProbe(
        _ request: HelperCapabilityProbeRequestDTO,
        withReply reply: @escaping (HelperCapabilityProbeResponseDTO) -> Void
    ) {
        let snapshot = try? snapshotProvider.currentSnapshot(now: request.requestedAt)
        let report = capabilityChecker.evaluate(snapshot: snapshot)
        let status = makeStatus(
            recommendedMode: report.recommendedControllerMode,
            lastErrorDescription: nil,
            checkedAt: request.requestedAt
        )
        reply(
            HelperCapabilityProbeResponseDTO(
                report: CapabilityReportDTO(report: report),
                status: ControllerStatusDTO(status: status)
            )
        )
    }

    func setChargingEnabled(
        _ request: HelperSetChargingEnabledRequestDTO,
        withReply reply: @escaping (HelperCommandResponseDTO) -> Void
    ) {
        reply(
            HelperCommandResponseDTO(
                status: ControllerStatusDTO(status: makeStubFailureStatus(at: request.requestedAt)),
                error: HelperXPCErrorDTO(
                    code: "stubbed-control",
                    message: "실제 충전 on/off 제어는 이번 단계에서 구현하지 않습니다.",
                    isRetryable: false
                )
            )
        )
    }

    func setTemporaryOverride(
        _ request: HelperSetTemporaryOverrideRequestDTO,
        withReply reply: @escaping (HelperCommandResponseDTO) -> Void
    ) {
        reply(
            HelperCommandResponseDTO(
                status: ControllerStatusDTO(status: makeStubFailureStatus(at: request.requestedAt)),
                error: HelperXPCErrorDTO(
                    code: "stubbed-override",
                    message: "temporary override 제어는 이번 단계에서 stub 상태입니다.",
                    isRetryable: false
                )
            )
        )
    }

    private func makeReadOnlyStatus(at date: Date = .now) -> ControllerStatus {
        makeStatus(
            recommendedMode: .readOnly,
            lastErrorDescription: nil,
            checkedAt: date
        )
    }

    private func makeStubFailureStatus(at date: Date) -> ControllerStatus {
        makeStatus(
            recommendedMode: .readOnly,
            lastErrorDescription: "Stub helper는 제어 요청을 수행하지 않습니다.",
            checkedAt: date
        )
    }

    private func makeStatus(
        recommendedMode: ControllerStatus.Mode,
        lastErrorDescription: String?,
        checkedAt: Date
    ) -> ControllerStatus {
        ControllerStatus(
            mode: recommendedMode,
            helperConnection: .connected,
            isChargingEnabled: nil,
            temporaryOverrideUntil: nil,
            lastErrorDescription: lastErrorDescription,
            checkedAt: checkedAt
        )
    }
}
