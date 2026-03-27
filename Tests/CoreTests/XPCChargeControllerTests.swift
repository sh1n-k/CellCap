import Core
import Foundation
import Shared
import Testing

@Test
func xpcChargeControllerReturnsReadOnlyFallbackWhenTransportFails() async {
    let controller = XPCChargeController(
        transport: MockHelperServiceTransport(
            controllerStatusResult: .failure(
                HelperTransportError(
                    domain: "CellCap.XPC",
                    code: "connection_failure",
                    message: "연결이 실패했습니다.",
                    suggestedFallbackMode: .readOnly,
                    failureReason: "mach service not available"
                )
            ),
            selfTestResult: .failure(
                HelperTransportError(
                    domain: "CellCap.XPC",
                    code: "connection_failure",
                    message: "연결이 실패했습니다.",
                    suggestedFallbackMode: .readOnly,
                    failureReason: "helper unreachable"
                )
            )
        )
    )

    let status = await controller.getControllerStatus()
    let selfTest = await controller.selfTest()

    #expect(status.mode == .readOnly)
    #expect(status.helperConnection == .disconnected)
    #expect(status.lastErrorDescription == "mach service not available")
    #expect(selfTest.outcome == .failed)
    #expect(selfTest.message == "helper unreachable")
}

@Test
func xpcChargeControllerDelegatesCapabilityProbeSummary() async throws {
    let expectedReport = CapabilityReport(
        statuses: [
            CapabilityStatus(key: .chargeControl, support: .experimental, reason: "stub")
        ],
        recommendedControllerMode: .readOnly
    )
    let expectedStatus = ControllerStatus(
        mode: .readOnly,
        helperConnection: .connected,
        checkedAt: Date(timeIntervalSince1970: 100)
    )

    let controller = XPCChargeController(
        transport: MockHelperServiceTransport(
            capabilityProbeResult: .success(
                HelperCapabilityProbeSummary(
                    report: expectedReport,
                    controllerStatus: expectedStatus
                )
            )
        )
    )

    let summary = try await controller.capabilityProbe()

    #expect(summary.report == expectedReport)
    #expect(summary.controllerStatus == expectedStatus)
}

private struct MockHelperServiceTransport: HelperServiceTransporting {
    var controllerStatusResult: Result<ControllerStatus, Error> = .success(
        ControllerStatus(mode: .readOnly, helperConnection: .connected)
    )
    var selfTestResult: Result<HelperSelfTestSummary, Error> = .success(
        HelperSelfTestSummary(
            result: ControllerSelfTestResult(outcome: .degraded, message: "stub"),
            controllerStatus: ControllerStatus(mode: .readOnly, helperConnection: .connected)
        )
    )
    var capabilityProbeResult: Result<HelperCapabilityProbeSummary, Error> = .success(
        HelperCapabilityProbeSummary(
            report: CapabilityReport(statuses: [], recommendedControllerMode: .readOnly),
            controllerStatus: ControllerStatus(mode: .readOnly, helperConnection: .connected)
        )
    )

    func fetchControllerStatus() async throws -> ControllerStatus {
        try controllerStatusResult.get()
    }

    func selfTest() async throws -> HelperSelfTestSummary {
        try selfTestResult.get()
    }

    func capabilityProbe() async throws -> HelperCapabilityProbeSummary {
        try capabilityProbeResult.get()
    }

    func setChargingEnabled(_ enabled: Bool) async throws -> ControllerStatus {
        try controllerStatusResult.get()
    }

    func setTemporaryOverride(until: Date?) async throws -> ControllerStatus {
        try controllerStatusResult.get()
    }
}
