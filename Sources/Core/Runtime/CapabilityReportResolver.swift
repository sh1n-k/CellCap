import Foundation
import Shared

protocol CapabilityReportResolving: Sendable {
    func resolve(
        snapshot: BatterySnapshot?,
        controllerStatus: ControllerStatus,
        trigger: AppRuntimeTrigger,
        helperInstallStatus: HelperInstallStatus
    ) async -> CapabilityReport
}

struct CapabilityReportResolver: CapabilityReportResolving {
    private let capabilityChecker: any CapabilityChecking
    private let capabilityProber: (any HelperCapabilityProbing)?
    private let eventLogger: any EventLogging

    init(
        capabilityChecker: any CapabilityChecking,
        capabilityProber: (any HelperCapabilityProbing)?,
        eventLogger: any EventLogging
    ) {
        self.capabilityChecker = capabilityChecker
        self.capabilityProber = capabilityProber
        self.eventLogger = eventLogger
    }

    func resolve(
        snapshot: BatterySnapshot?,
        controllerStatus: ControllerStatus,
        trigger: AppRuntimeTrigger,
        helperInstallStatus: HelperInstallStatus
    ) async -> CapabilityReport {
        var baseReport = capabilityChecker.evaluate(snapshot: snapshot)
            .replacingHelperInstallStatus(helperInstallStatus)
            .replacingStatus(
                for: .helperInstallation,
                support: helperInstallStatus.installationSupport,
                reason: helperInstallStatus.reason
            )
            .replacingStatus(
                for: .helperPrivilege,
                support: helperInstallStatus.privilegeSupport,
                reason: helperInstallStatus.privilegeReason
            )

        if shouldProbeHelper(for: trigger), let capabilityProber {
            do {
                let probe = try await capabilityProber.capabilityProbe()
                let mergedInstallStatus = Self.mergeHelperInstallStatus(
                    local: helperInstallStatus,
                    remote: probe.report.helperInstallStatus
                )
                await eventLogger.record(
                    level: .notice,
                    category: .capabilityProbe,
                    message: "Capability probe 결과를 저장했습니다.",
                    details: [
                        "recommendedMode": probe.report.recommendedControllerMode.rawValue,
                        "helperMode": probe.status.mode.rawValue,
                        "helperInstallState": mergedInstallStatus.state.rawValue
                    ],
                    userFacingSummary: nil
                )
                baseReport = probe.report
                    .replacingHelperInstallStatus(mergedInstallStatus)
                    .replacingStatus(
                        for: .helperInstallation,
                        support: mergedInstallStatus.installationSupport,
                        reason: mergedInstallStatus.reason
                    )
                    .replacingStatus(
                        for: .helperPrivilege,
                        support: mergedInstallStatus.privilegeSupport,
                        reason: mergedInstallStatus.privilegeReason
                    )
            } catch {
                await eventLogger.record(
                    level: .error,
                    category: .capabilityProbe,
                    message: "Capability probe가 실패했습니다: \(error.localizedDescription)",
                    details: ["trigger": trigger.debugName],
                    userFacingSummary: "capability probe 실패로 read-only fallback을 적용합니다."
                )
            }
        }

        if controllerStatus.helperConnection != .connected || controllerStatus.lastErrorDescription != nil {
            await eventLogger.record(
                level: .warning,
                category: .helperCommunication,
                message: controllerStatus.lastErrorDescription ?? "Helper 연결이 정상 상태가 아닙니다.",
                details: [
                    "mode": controllerStatus.mode.rawValue,
                    "helperConnection": controllerStatus.helperConnection.rawValue
                ],
                userFacingSummary: "helper 연결 문제로 read-only 또는 monitoring-only 상태를 유지합니다."
            )
            return baseReport
                .replacingStatus(
                    for: .chargeControl,
                    support: .readOnlyFallback,
                    reason: controllerStatus.lastErrorDescription ?? "helper 연결 실패로 읽기 전용 상태를 유지합니다."
                )
                .replacingStatus(
                    for: .helperInstallation,
                    support: .readOnlyFallback,
                    reason: controllerStatus.lastErrorDescription ?? helperInstallStatus.reason
                )
        }

        return baseReport
    }

    static func mergeHelperInstallStatus(
        local: HelperInstallStatus,
        remote: HelperInstallStatus?
    ) -> HelperInstallStatus {
        guard let remote else { return local }

        let merged = HelperInstallStatus(
            state: remote.state,
            serviceName: remote.serviceName,
            helperPath: local.helperPath,
            plistPath: local.plistPath,
            helperVersion: remote.helperVersion,
            expectedVersion: remote.expectedVersion ?? local.expectedVersion,
            reason: remote.reason,
            checkedAt: remote.checkedAt
        )

        if let helperVersion = merged.helperVersion,
           let expectedVersion = merged.expectedVersion,
           helperVersion != expectedVersion {
            return HelperInstallStatus(
                state: .versionMismatch,
                serviceName: merged.serviceName,
                helperPath: merged.helperPath,
                plistPath: merged.plistPath,
                helperVersion: helperVersion,
                expectedVersion: expectedVersion,
                reason: "helper 버전이 앱 계약 버전과 다릅니다. helper=\(helperVersion) expected=\(expectedVersion)",
                checkedAt: merged.checkedAt
            )
        }

        return merged
    }

    private func shouldProbeHelper(for trigger: AppRuntimeTrigger) -> Bool {
        switch trigger {
        case .appLaunch, .manualRefresh, .resynchronization, .policyChanged:
            return true
        case .batteryEvent(let batteryTrigger):
            return batteryTrigger == .didWake || batteryTrigger == .powerSourceChanged
        }
    }
}
