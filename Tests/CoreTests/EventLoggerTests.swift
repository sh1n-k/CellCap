import Core
import Foundation
import Shared
import Testing

@Test
func eventLoggerBuildsDiagnosticsSummaryFromStructuredEvents() async {
    let logger = EventLogger()
    let currentUpdate = AppRuntimeUpdate(
        appState: AppState(
            battery: BatterySnapshot(chargePercent: 77, isPowerConnected: true, isCharging: false),
            policy: ChargePolicy(upperLimit: 80, rechargeThreshold: 75),
            controllerStatus: ControllerStatus(
                mode: .readOnly,
                helperConnection: .connected,
                isChargingEnabled: nil,
                lastErrorDescription: nil
            ),
            chargeState: .suspended
        ),
        transitionReason: .controlSuspended,
        capabilityReport: CapabilityReport(
            statuses: [
                CapabilityStatus(key: .chargeControl, support: .readOnlyFallback, reason: "read-only")
            ],
            recommendedControllerMode: .readOnly
        ),
        lastTrigger: .appLaunch,
        chargingCommand: .noChange
    )

    await logger.record(
        level: .notice,
        category: .capabilityProbe,
        message: "Capability probe를 완료했습니다.",
        details: ["recommendedMode": "readOnly"],
        userFacingSummary: nil
    )
    await logger.record(
        level: .warning,
        category: .selfTest,
        message: "Helper self-test degraded",
        details: ["outcome": "degraded"],
        userFacingSummary: nil
    )
    await logger.record(
        level: .warning,
        category: .helperCommunication,
        message: "helper 연결 문제",
        details: [:],
        userFacingSummary: "helper 연결 문제로 read-only 상태를 유지합니다."
    )

    let summary = await logger.diagnosticsSummary(currentUpdate: currentUpdate)

    #expect(summary.eventCount == 3)
    #expect(summary.currentChargeState == .suspended)
    #expect(summary.currentControllerMode == .readOnly)
    #expect(summary.lastCapabilityProbeMessage == "Capability probe를 완료했습니다.")
    #expect(summary.lastSelfTestMessage == "Helper self-test degraded")
    #expect(summary.lastReadOnlyFallbackReason == "helper 연결 문제로 read-only 상태를 유지합니다.")
}

@Test
func eventLoggerExportsStructuredJsonEnvelope() async throws {
    let logger = EventLogger()
    await logger.record(
        level: .error,
        category: .helperCommunication,
        message: "XPC 연결 실패",
        details: ["command": "fetchControllerStatus"],
        userFacingSummary: "helper 연결 실패로 읽기 전용 상태를 유지합니다."
    )

    let artifact = try await logger.exportDiagnostics(currentUpdate: nil)

    #expect(artifact.contentType == "application/json")
    #expect(artifact.suggestedFilename.contains("CellCap-Diagnostics-"))
    #expect(artifact.utf8Contents.contains("\"events\""))
    #expect(artifact.utf8Contents.contains("XPC 연결 실패"))
}
