@testable import AppUI
import Shared
import Testing

@MainActor
@Test
func menuBarPresentationBuildsHoldingSummaryAndLabels() {
    let viewModel = MenuBarPreviewFactory.makeHolding()

    #expect(viewModel.chargeStateTitle == "상한 유지 중")
    #expect(viewModel.summarySentence.contains("80% 상한"))
    #expect(viewModel.helperStatusText == "helper 연결 정상")
    #expect(viewModel.capabilityTitle(for: .chargeControl) == "충전 제어")
}

@MainActor
@Test
func controlAvailabilityResolverDisablesControlWhenHelperInstallIsNotReady() {
    let resolver = ControlAvailabilityResolver()
    let appState = AppState(
        battery: BatterySnapshot(
            chargePercent: 78,
            isPowerConnected: true,
            isCharging: true
        ),
        policy: ChargePolicy(),
        controllerStatus: ControllerStatus(
            mode: .readOnly,
            helperConnection: .disconnected,
            isChargingEnabled: nil
        ),
        chargeState: .suspended
    )
    let capabilityReport = CapabilityReport(
        statuses: [
            CapabilityStatus(key: .helperInstallation, support: .readOnlyFallback, reason: "helper 미설치"),
            CapabilityStatus(key: .helperPrivilege, support: .readOnlyFallback, reason: "helper 권한 미확인"),
            CapabilityStatus(key: .chargeControl, support: .readOnlyFallback, reason: "read-only")
        ],
        recommendedControllerMode: .readOnly,
        helperInstallStatus: HelperInstallStatus(
            state: .notInstalled,
            serviceName: CellCapHelperXPC.serviceName,
            helperPath: CellCapHelperXPC.installedBinaryPath,
            plistPath: CellCapHelperXPC.launchDaemonPlistPath,
            expectedVersion: CellCapHelperXPC.contractVersion,
            reason: "helper 미설치"
        )
    )

    let availability = resolver.controlAvailability(
        appState: appState,
        capabilityReport: capabilityReport
    )

    #expect(availability.isEnabled == false)
    #expect(availability.reason == "helper 미설치")
    #expect(
        resolver.shouldAutoExpandAdvancedSection(
            appState: appState,
            capabilityReport: capabilityReport
        )
    )
}

@MainActor
@Test
func previewFactoryExposesExpectedFallbackStates() {
    let errorPreview = MenuBarPreviewFactory.makeErrorReadOnly()
    let monitoringPreview = MenuBarPreviewFactory.makeMonitoringOnly()

    #expect(errorPreview.appState.chargeState == .errorReadOnly)
    #expect(errorPreview.controlAvailability.isEnabled == false)
    #expect(monitoringPreview.appState.controllerStatus.mode == .monitoringOnly)
    #expect(monitoringPreview.shouldAutoExpandAdvancedSection)
}
