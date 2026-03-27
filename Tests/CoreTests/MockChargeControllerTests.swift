import Foundation
import Core
import Shared
import Testing

@Test
func mockControllerRecordsCommandsAndExposesUpdatedStatus() async throws {
    let controller = MockChargeController(
        initialStatus: ControllerStatus(
            mode: .fullControl,
            helperConnection: .connected,
            isChargingEnabled: true
        ),
        selfTestResult: ControllerSelfTestResult(
            outcome: .passed,
            message: "Mock environment healthy."
        )
    )

    try await controller.setChargingEnabled(false)
    try await controller.setTemporaryOverride(until: Date(timeIntervalSince1970: 3_000))

    let status = await controller.getControllerStatus()
    let commands = await controller.recordedCommands()
    let selfTest = await controller.selfTest()

    #expect(status.isChargingEnabled == false)
    #expect(commands == [
        .setChargingEnabled(false),
        .setTemporaryOverride(Date(timeIntervalSince1970: 3_000))
    ])
    #expect(selfTest.outcome == .passed)
}
