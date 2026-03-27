import Foundation
import Shared

protocol SelfTestPolicying: Sendable {
    func performIfNeeded(
        trigger: AppRuntimeTrigger,
        helperInstallStatus: HelperInstallStatus,
        controllerStatus: ControllerStatus
    ) async -> ControllerSelfTestResult?
}

struct SelfTestPolicy: SelfTestPolicying {
    private let controller: any ChargeController
    private let eventLogger: any EventLogging

    init(
        controller: any ChargeController,
        eventLogger: any EventLogging
    ) {
        self.controller = controller
        self.eventLogger = eventLogger
    }

    func performIfNeeded(
        trigger: AppRuntimeTrigger,
        helperInstallStatus: HelperInstallStatus,
        controllerStatus: ControllerStatus
    ) async -> ControllerSelfTestResult? {
        switch trigger {
        case .appLaunch, .manualRefresh:
            guard helperInstallStatus.state != .notInstalled,
                  helperInstallStatus.state != .installedButNotBootstrapped else {
                await eventLogger.record(
                    level: .notice,
                    category: .selfTest,
                    message: "helper 설치 상태가 준비되지 않아 self-test를 건너뜁니다.",
                    details: [
                        "trigger": trigger.debugName,
                        "helperInstallState": helperInstallStatus.state.rawValue
                    ],
                    userFacingSummary: "helper가 아직 설치 또는 기동되지 않아 self-test를 건너뜁니다."
                )
                return nil
            }

            guard controllerStatus.helperConnection == .connected else {
                await eventLogger.record(
                    level: .warning,
                    category: .selfTest,
                    message: "helper 연결이 없어서 self-test를 건너뜁니다.",
                    details: [
                        "trigger": trigger.debugName,
                        "helperConnection": controllerStatus.helperConnection.rawValue
                    ],
                    userFacingSummary: "helper 연결이 되지 않아 self-test를 건너뜁니다."
                )
                return nil
            }

            let result = await controller.selfTest()
            await eventLogger.record(
                level: result.outcome == .failed ? .error : (result.outcome == .degraded ? .warning : .notice),
                category: .selfTest,
                message: result.message,
                details: [
                    "trigger": trigger.debugName,
                    "outcome": result.outcome.rawValue
                ],
                userFacingSummary: result.outcome == .failed ? "self-test 실패로 read-only fallback을 유지합니다." : nil
            )
            return result
        case .policyChanged, .batteryEvent, .resynchronization:
            return nil
        }
    }
}
