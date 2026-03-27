import Core
import Foundation
import Shared
import Testing

@Test
func xpcChargeControllerReturnsReadOnlyFallbackWhenTransportFails() async {
    let transport = MockHelperServiceTransport(
        statusResult: .failure(HelperTransportError.connectionFailure("timeout")),
        selfTestResult: .failure(HelperTransportError.connectionFailure("timeout"))
    )
    let controller = XPCChargeController(transport: transport)

    let status = await controller.getControllerStatus()
    let selfTest = await controller.selfTest()

    #expect(status.mode == .readOnly)
    #expect(status.helperConnection == .disconnected)
    #expect(status.lastErrorDescription == "XPC 연결 실패: timeout")
    #expect(selfTest.outcome == .failed)
}

@Test
func xpcChargeControllerDelegatesCapabilityProbeSummary() async throws {
    let report = CapabilityReport(
        statuses: [
            CapabilityStatus(key: .appleSilicon, support: .supported, reason: "ok"),
            CapabilityStatus(key: .chargeControl, support: .experimental, reason: "stub")
        ],
        recommendedControllerMode: .readOnly
    )
    let status = ControllerStatus(
        mode: .readOnly,
        helperConnection: .connected,
        lastErrorDescription: "stub"
    )
    let transport = MockHelperServiceTransport(
        capabilityProbeResult: .success(
            HelperCapabilityProbeSummary(report: report, status: status)
        )
    )
    let controller = XPCChargeController(transport: transport)

    let summary = try await controller.capabilityProbe()

    #expect(summary.report == report)
    #expect(summary.status == status)
}

private struct MockHelperServiceTransport: HelperServiceTransporting {
    var statusResult: Result<ControllerStatus, Error> = .success(
        ControllerStatus(mode: .readOnly, helperConnection: .connected)
    )
    var selfTestResult: Result<HelperSelfTestSummary, Error> = .success(
        HelperSelfTestSummary(
            result: ControllerSelfTestResult(outcome: .degraded, message: "stub"),
            status: nil
        )
    )
    var capabilityProbeResult: Result<HelperCapabilityProbeSummary, Error> = .success(
        HelperCapabilityProbeSummary(
            report: CapabilityReport(
                statuses: [
                    CapabilityStatus(key: .appleSilicon, support: .supported, reason: "ok"),
                    CapabilityStatus(key: .chargeControl, support: .experimental, reason: "stub")
                ],
                recommendedControllerMode: .readOnly
            ),
            status: ControllerStatus(mode: .readOnly, helperConnection: .connected)
        )
    )

    func fetchControllerStatus() async throws -> ControllerStatus {
        try statusResult.get()
    }

    func selfTest() async throws -> HelperSelfTestSummary {
        try selfTestResult.get()
    }

    func capabilityProbe() async throws -> HelperCapabilityProbeSummary {
        try capabilityProbeResult.get()
    }

    func setChargingEnabled(_ enabled: Bool) async throws -> ControllerStatus {
        try statusResult.get()
    }

    func setTemporaryOverride(until: Date?) async throws -> ControllerStatus {
        try statusResult.get()
    }
}
