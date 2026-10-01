import Foundation
import Shared

actor ControllerCommandApplier {
    private let controller: any ChargeController
    private let eventLogger: any EventLogging
    private var commandInFlight = false
    /// 제어 OFF 구간마다 해제는 한 번만 성공하면 된다. 제어가 다시 켜지면 초기화한다.
    private var hasReleasedForCurrentControlOff = false

    init(
        controller: any ChargeController,
        eventLogger: any EventLogging
    ) {
        self.controller = controller
        self.eventLogger = eventLogger
    }

    func applyIfNeeded(
        controllerStatus: ControllerStatus,
        capabilityReport: CapabilityReport,
        evaluation: PolicyEvaluation,
        now: Date
    ) async -> ControllerStatus {
        guard !commandInFlight else {
            return controllerStatus
        }
        if evaluation.effectivePolicy.isControlEnabled {
            hasReleasedForCurrentControlOff = false
        }
        if evaluation.chargingCommand == .releaseControl {
            return await applyRelease(
                controllerStatus: controllerStatus,
                capabilityReport: capabilityReport,
                now: now
            )
        }
        guard capabilityReport.recommendedControllerMode == .fullControl else {
            return controllerStatus
        }
        guard controllerStatus.mode == .fullControl else {
            return controllerStatus
        }
        guard controllerStatus.helperConnection == .connected else {
            return controllerStatus
        }
        guard controllerStatus.lastErrorDescription == nil else {
            return controllerStatus
        }
        guard canApplyCommands(with: capabilityReport) else {
            return controllerStatus
        }

        var attemptedCommand = false

        do {
            commandInFlight = true
            defer { commandInFlight = false }

            let desiredOverride = evaluation.effectivePolicy.isTemporaryOverrideActive
                ? evaluation.effectivePolicy.temporaryOverrideUntil
                : nil
            if controllerStatus.temporaryOverrideUntil != desiredOverride {
                attemptedCommand = true
                try await controller.setTemporaryOverride(until: desiredOverride)
                await eventLogger.record(
                    level: .notice,
                    category: .runtime,
                    message: "Controller temporary override를 동기화했습니다.",
                    details: [
                        "until": desiredOverride?.ISO8601Format() ?? "nil"
                    ],
                    userFacingSummary: nil
                )
            }

            switch evaluation.chargingCommand {
            case .enableCharging:
                attemptedCommand = true
                try await controller.setChargingEnabled(true)
            case .disableCharging:
                attemptedCommand = true
                try await controller.setChargingEnabled(false)
            case .releaseControl, .noChange:
                break
            }

            guard attemptedCommand else {
                return controllerStatus
            }
            return await controller.getControllerStatus()
        } catch {
            await eventLogger.record(
                level: .error,
                category: .helperCommunication,
                message: "Controller 명령 적용이 실패했습니다: \(error.localizedDescription)",
                details: [
                    "chargingCommand": evaluation.chargingCommand.rawValue
                ],
                userFacingSummary: "저수준 충전 제어 명령 적용에 실패해 read-only fallback을 유지합니다."
            )

            let refreshed = await controller.getControllerStatus()
            if refreshed.lastErrorDescription != nil || refreshed.mode != .fullControl {
                return refreshed
            }

            return ControllerStatus(
                mode: .readOnly,
                helperConnection: refreshed.helperConnection,
                isChargingEnabled: refreshed.isChargingEnabled,
                temporaryOverrideUntil: refreshed.temporaryOverrideUntil,
                lastErrorDescription: error.localizedDescription,
                checkedAt: now
            )
        }
    }

    /// 제어 해제는 오류·read-only 상태에서도 보내야 시스템 충전 한도가 남지 않는다.
    /// 다만 helper 설치·버전이 맞지 않으면 해제 명령 자체를 이해하지 못하므로 보내지 않는다.
    private func applyRelease(
        controllerStatus: ControllerStatus,
        capabilityReport: CapabilityReport,
        now: Date
    ) async -> ControllerStatus {
        guard !hasReleasedForCurrentControlOff,
              controllerStatus.helperConnection == .connected,
              capabilityReport.status(for: .helperInstallation)?.support == .supported,
              capabilityReport.status(for: .helperPrivilege)?.support == .supported else {
            return controllerStatus
        }

        commandInFlight = true
        defer { commandInFlight = false }

        do {
            try await controller.releaseControl()
            hasReleasedForCurrentControlOff = true
            await eventLogger.record(
                level: .notice,
                category: .runtime,
                message: "제어 OFF에 따라 충전 제한을 해제했습니다.",
                details: [:],
                userFacingSummary: nil
            )
        } catch {
            await eventLogger.record(
                level: .error,
                category: .helperCommunication,
                message: "충전 제한 해제가 실패했습니다: \(error.localizedDescription)",
                details: [
                    "chargingCommand": ChargingCommand.releaseControl.rawValue
                ],
                userFacingSummary: "충전 제한 해제에 실패했습니다. 다음 동기화에서 다시 시도합니다."
            )
        }
        return await controller.getControllerStatus()
    }

    private func canApplyCommands(with capabilityReport: CapabilityReport) -> Bool {
        guard capabilityReport.recommendedControllerMode == .fullControl else {
            return false
        }

        for key in [CapabilityKey.helperInstallation, .helperPrivilege, .chargeControl] {
            guard let status = capabilityReport.status(for: key) else { continue }

            switch status.key {
            case .chargeControl:
                switch status.support {
                case .supported, .experimental:
                    continue
                case .unsupported, .readOnlyFallback:
                    return false
                }
            case .helperInstallation, .helperPrivilege:
                guard status.support == .supported else {
                    return false
                }
            default:
                continue
            }
        }

        return true
    }
}
