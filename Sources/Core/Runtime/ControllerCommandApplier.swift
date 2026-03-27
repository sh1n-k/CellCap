import Foundation
import Shared

protocol ControllerCommandApplying: Sendable {
    func applyIfNeeded(
        controllerStatus: ControllerStatus,
        capabilityReport: CapabilityReport,
        evaluation: PolicyEvaluation,
        now: Date
    ) async -> ControllerStatus
}

actor ControllerCommandApplier: ControllerCommandApplying {
    private let controller: any ChargeController
    private let eventLogger: any EventLogging
    private var commandInFlight = false

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
            case .noChange:
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
