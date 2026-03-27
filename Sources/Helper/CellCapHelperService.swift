import Core
import Foundation
import Shared

final class CellCapHelperService: NSObject, CellCapHelperXPCProtocol {
    private let capabilityChecker: any CapabilityChecking
    private let snapshotProvider: any BatterySnapshotProviding
    private let dateProvider: any DateProviding

    init(
        capabilityChecker: any CapabilityChecking = CapabilityChecker(),
        snapshotProvider: any BatterySnapshotProviding = SystemBatterySnapshotProvider(),
        dateProvider: any DateProviding = SystemDateProvider()
    ) {
        self.capabilityChecker = capabilityChecker
        self.snapshotProvider = snapshotProvider
        self.dateProvider = dateProvider
    }

    func fetchControllerStatus(
        _ request: HelperRequestDTO,
        withReply reply: @escaping (HelperControllerStatusResponseDTO) -> Void
    ) {
        reply(
            HelperControllerStatusResponseDTO(
                requestIdentifier: request.requestIdentifier,
                controllerStatus: ControllerStatusDTO(makeReadOnlyControllerStatus())
            )
        )
    }

    func selfTest(
        _ request: HelperSelfTestRequestDTO,
        withReply reply: @escaping (HelperSelfTestResponseDTO) -> Void
    ) {
        do {
            let snapshot = try snapshotProvider.currentSnapshot(now: dateProvider.now)
            let controllerStatus = makeReadOnlyControllerStatus(snapshot: snapshot)
            let result = ControllerSelfTestResult(
                outcome: .degraded,
                message: "XPC 경로와 관측 계층은 응답했지만 실제 충전 제어는 아직 stub입니다.",
                checkedAt: dateProvider.now
            )

            reply(
                HelperSelfTestResponseDTO(
                    requestIdentifier: request.requestIdentifier,
                    result: ControllerSelfTestResultDTO(result),
                    controllerStatus: ControllerStatusDTO(controllerStatus)
                )
            )
        } catch {
            let controllerStatus = makeReadOnlyControllerStatus(error: error.localizedDescription)
            reply(
                HelperSelfTestResponseDTO(
                    requestIdentifier: request.requestIdentifier,
                    result: ControllerSelfTestResultDTO(
                        ControllerSelfTestResult(
                            outcome: .failed,
                            message: "관측 계층 초기 self-test가 실패했습니다.",
                            checkedAt: dateProvider.now
                        )
                    ),
                    controllerStatus: ControllerStatusDTO(controllerStatus),
                    error: makeTransportError(
                        code: "self_test_failed",
                        message: "Helper self-test가 실패했습니다.",
                        suggestedFallbackMode: .readOnly,
                        failureReason: error.localizedDescription
                    )
                )
            )
        }
    }

    func capabilityProbe(
        _ request: HelperCapabilityProbeRequestDTO,
        withReply reply: @escaping (HelperCapabilityProbeResponseDTO) -> Void
    ) {
        do {
            let snapshot = try snapshotProvider.currentSnapshot(now: dateProvider.now)
            let report = capabilityChecker.evaluate(snapshot: snapshot)
            let controllerStatus = makeControllerStatus(for: report, error: nil)

            reply(
                HelperCapabilityProbeResponseDTO(
                    requestIdentifier: request.requestIdentifier,
                    capabilityReport: CapabilityReportDTO(report),
                    controllerStatus: ControllerStatusDTO(controllerStatus)
                )
            )
        } catch {
            let report = capabilityChecker.evaluate(snapshot: nil)
            let controllerStatus = makeControllerStatus(for: report, error: error.localizedDescription)

            reply(
                HelperCapabilityProbeResponseDTO(
                    requestIdentifier: request.requestIdentifier,
                    capabilityReport: CapabilityReportDTO(report),
                    controllerStatus: ControllerStatusDTO(controllerStatus),
                    error: makeTransportError(
                        code: "capability_probe_failed",
                        message: "Capability probe가 관측 계층 오류로 degraded 되었습니다.",
                        suggestedFallbackMode: .readOnly,
                        failureReason: error.localizedDescription
                    )
                )
            )
        }
    }

    func setChargingEnabled(
        _ request: HelperSetChargingEnabledRequestDTO,
        withReply reply: @escaping (HelperCommandResponseDTO) -> Void
    ) {
        reply(
            HelperCommandResponseDTO(
                requestIdentifier: request.requestIdentifier,
                controllerStatus: ControllerStatusDTO(
                    makeReadOnlyControllerStatus(error: "충전 on/off 제어는 아직 구현되지 않았습니다.")
                ),
                error: makeTransportError(
                    code: "charging_control_stub",
                    message: "실제 충전 on/off 제어는 아직 stub입니다.",
                    suggestedFallbackMode: .readOnly
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
                requestIdentifier: request.requestIdentifier,
                controllerStatus: ControllerStatusDTO(
                    makeReadOnlyControllerStatus(error: "temporary override 제어는 아직 구현되지 않았습니다.")
                ),
                error: makeTransportError(
                    code: "temporary_override_stub",
                    message: "temporary override 제어는 아직 stub입니다.",
                    suggestedFallbackMode: .readOnly
                )
            )
        )
    }

    private func makeReadOnlyControllerStatus(
        snapshot: BatterySnapshot? = nil,
        error: String? = "실제 충전 제어는 아직 구현되지 않았습니다."
    ) -> ControllerStatus {
        let mode: ControllerStatus.Mode = snapshot?.isBatteryPresent == true ? .readOnly : .monitoringOnly

        return ControllerStatus(
            mode: mode,
            helperConnection: .connected,
            isChargingEnabled: nil,
            temporaryOverrideUntil: nil,
            lastErrorDescription: error,
            checkedAt: dateProvider.now
        )
    }

    private func makeControllerStatus(
        for report: CapabilityReport,
        error: String?
    ) -> ControllerStatus {
        ControllerStatus(
            mode: report.recommendedControllerMode,
            helperConnection: .connected,
            isChargingEnabled: nil,
            temporaryOverrideUntil: nil,
            lastErrorDescription: error ?? "Capability probe 완료. 실제 제어는 이후 단계에서 연결됩니다.",
            checkedAt: dateProvider.now
        )
    }

    private func makeTransportError(
        code: String,
        message: String,
        suggestedFallbackMode: ControllerStatus.Mode,
        failureReason: String? = nil
    ) -> HelperXPCErrorDTO {
        HelperXPCErrorDTO(
            domain: "CellCap.Helper",
            code: code,
            message: message,
            suggestedFallbackModeRawValue: suggestedFallbackMode.rawValue,
            failureReason: failureReason
        )
    }
}
