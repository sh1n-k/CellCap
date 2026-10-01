import Core
import Foundation
import Shared
import Testing

@Test
func helperInstallRegistersAndReportsApprovalRequirement() async {
    let daemon = MockHelperDaemon(
        status: .notRegistered,
        statusAfterRegister: .requiresApproval,
        registerError: HelperManagerTestError.operationNotPermitted
    )
    let manager = HelperServiceManager(controller: MockChargeController(), daemon: daemon, fileSystem: MockFileSystem(existingFiles: []))

    let result = await manager.install()

    guard case .requiresApproval = result else {
        Issue.record("승인 대기 결과가 아닙니다: \(result)")
        return
    }
    #expect(daemon.recordedCalls() == [.register])
}

@Test
func helperInstallClearsStaleRegistrationBeforeRegistering() async {
    // 이전 방식 helper 기록이나 서명이 바뀐 등록이 남아 enabled로 보이는 경우.
    let daemon = MockHelperDaemon(status: .enabled)
    let manager = HelperServiceManager(controller: MockChargeController(), daemon: daemon, fileSystem: MockFileSystem(existingFiles: []))

    let result = await manager.install()

    #expect(result == .completed("helper를 설치했습니다."))
    #expect(daemon.recordedCalls() == [.unregister, .register])
}

@Test
func helperRemovalReleasesControlBeforeUnregistering() async {
    let controller = MockChargeController()
    let daemon = MockHelperDaemon(status: .enabled)
    let manager = HelperServiceManager(controller: controller, daemon: daemon, fileSystem: MockFileSystem(existingFiles: []))

    let result = await manager.remove(force: false)

    #expect(result == .completed("helper를 제거했습니다."))
    #expect(await controller.recordedCommands() == [.releaseControl])
    #expect(daemon.recordedCalls() == [.unregister])
}

@Test
func helperRemovalStopsWhenReleaseFailsUntilForced() async {
    let daemon = MockHelperDaemon(status: .enabled)
    let manager = HelperServiceManager(controller: FailingReleaseController(), daemon: daemon, fileSystem: MockFileSystem(existingFiles: []))

    let first = await manager.remove(force: false)
    guard case .releaseFailed = first else {
        Issue.record("해제 실패 결과가 아닙니다: \(first)")
        return
    }
    #expect(daemon.recordedCalls().isEmpty)

    let forced = await manager.remove(force: true)
    #expect(forced == .completed("helper를 제거했습니다."))
    #expect(daemon.recordedCalls() == [.unregister])
}

@Test
func helperRemovalSkipsReleaseWhenHelperCannotRun() async {
    let controller = FailingReleaseController()
    let daemon = MockHelperDaemon(status: .requiresApproval)
    let manager = HelperServiceManager(controller: controller, daemon: daemon, fileSystem: MockFileSystem(existingFiles: []))

    let result = await manager.remove(force: false)

    #expect(result == .completed("helper를 제거했습니다."))
    #expect(daemon.recordedCalls() == [.unregister])
}

@Test
func helperRemovalWarnsWhenBaselineRemains() async {
    let daemon = MockHelperDaemon(status: .enabled)
    let manager = HelperServiceManager(
        controller: MockChargeController(),
        daemon: daemon,
        fileSystem: MockFileSystem(existingFiles: [CellCapHelperXPC.chargeLimitBaselinePath])
    )

    let result = await manager.remove(force: false)

    #expect(result.message.contains("복원되지 않았습니다"))
}

private enum HelperManagerTestError: Error {
    case operationNotPermitted
    case releaseFailed
}

private struct FailingReleaseController: ChargeController {
    func setChargingEnabled(_ enabled: Bool) async throws {}
    func setTemporaryOverride(until: Date?) async throws {}
    func releaseControl() async throws { throw HelperManagerTestError.releaseFailed }
    func getControllerStatus() async -> ControllerStatus {
        ControllerStatus(
            mode: .readOnly,
            helperConnection: .disconnected,
            isChargingEnabled: nil,
            temporaryOverrideUntil: nil,
            lastErrorDescription: nil
        )
    }
    func selfTest() async -> ControllerSelfTestResult {
        ControllerSelfTestResult(outcome: .degraded, message: "")
    }
}
