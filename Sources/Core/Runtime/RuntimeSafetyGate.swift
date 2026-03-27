import Foundation
import Shared

protocol RuntimeSafetyGating: Sendable {
    func apply(
        controllerStatus: ControllerStatus,
        capabilityReport: CapabilityReport,
        selfTestResult: ControllerSelfTestResult?,
        now: Date
    ) -> (controllerStatus: ControllerStatus, capabilityReport: CapabilityReport)
}

struct RuntimeSafetyGate: RuntimeSafetyGating {
    func apply(
        controllerStatus: ControllerStatus,
        capabilityReport: CapabilityReport,
        selfTestResult: ControllerSelfTestResult?,
        now: Date
    ) -> (controllerStatus: ControllerStatus, capabilityReport: CapabilityReport) {
        guard controllerStatus.lastErrorDescription == nil else {
            return (controllerStatus, capabilityReport)
        }

        if let selfTestResult, selfTestResult.outcome != .passed {
            return (
                ControllerStatus(
                    mode: .readOnly,
                    helperConnection: controllerStatus.helperConnection,
                    isChargingEnabled: controllerStatus.isChargingEnabled,
                    temporaryOverrideUntil: controllerStatus.temporaryOverrideUntil,
                    lastErrorDescription: nil,
                    checkedAt: now
                ),
                capabilityReport
                    .replacingStatus(
                        for: .chargeControl,
                        support: .readOnlyFallback,
                        reason: "self-test가 \(selfTestResult.outcome.rawValue) 결과를 반환했습니다: \(selfTestResult.message)"
                    )
                    .replacingRecommendedControllerMode(.readOnly)
            )
        }

        for key in [CapabilityKey.helperInstallation, .helperPrivilege, .chargeControl] {
            guard let status = capabilityReport.status(for: key) else { continue }

            let blockedMode: ControllerStatus.Mode?
            switch status.support {
            case .supported:
                blockedMode = nil
            case .experimental:
                blockedMode = key == .chargeControl ? nil : .readOnly
            case .readOnlyFallback:
                blockedMode = .readOnly
            case .unsupported:
                blockedMode = .monitoringOnly
            }

            guard let blockedMode else { continue }

            return (
                ControllerStatus(
                    mode: blockedMode,
                    helperConnection: controllerStatus.helperConnection,
                    isChargingEnabled: controllerStatus.isChargingEnabled,
                    temporaryOverrideUntil: controllerStatus.temporaryOverrideUntil,
                    lastErrorDescription: nil,
                    checkedAt: now
                ),
                capabilityReport.replacingRecommendedControllerMode(blockedMode)
            )
        }

        return (controllerStatus, capabilityReport)
    }
}
