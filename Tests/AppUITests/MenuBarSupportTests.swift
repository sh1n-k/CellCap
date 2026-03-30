@testable import AppUI
import Core
import Foundation
import Shared
import Testing

@MainActor
@Test
func menuBarPresentationBuildsHoldingSummaryAndLabels() {
    let viewModel = MenuBarPreviewFactory.makeHolding()

    #expect(viewModel.chargeStateTitle == "상한 유지 중")
    #expect(viewModel.summarySentence == "상한에 도달해 충전을 멈추고 유지하고 있습니다.")
    #expect(viewModel.helperStatusText == "helper 연결 정상")
    #expect(viewModel.capabilityTitle(for: .chargeControl) == "충전 제어")
}

@MainActor
@Test
func menuBarPresentationShowsChargingReadyCopyWhenPowerIsDisconnected() {
    let viewModel = makeViewModel(
        battery: BatterySnapshot(
            chargePercent: 55,
            isPowerConnected: false,
            isCharging: false
        ),
        chargeState: .charging
    )

    #expect(viewModel.chargeStateTitle == "다시 충전 준비")
    #expect(viewModel.summarySentence == "하한 아래입니다. 전원을 연결하면 다시 충전합니다.")
    #expect(viewModel.powerStatusText == "배터리 사용 중")
}

@MainActor
@Test
func menuBarPresentationShowsChargingCopyWhenPowerIsConnectedAndCharging() {
    let viewModel = makeViewModel(
        battery: BatterySnapshot(
            chargePercent: 55,
            isPowerConnected: true,
            isCharging: true
        ),
        chargeState: .charging
    )

    #expect(viewModel.chargeStateTitle == "다시 충전 중")
    #expect(viewModel.summarySentence == "하한 아래로 내려가 충전을 다시 시작했습니다.")
    #expect(viewModel.powerStatusText == "전원 연결됨")
}

@MainActor
@Test
func menuBarPresentationShowsHoldingBaselineCopyWhenPowerIsDisconnected() {
    let viewModel = makeViewModel(
        battery: BatterySnapshot(
            chargePercent: 80,
            isPowerConnected: false,
            isCharging: false
        ),
        chargeState: .holdingAtLimit
    )

    #expect(viewModel.chargeStateTitle == "상한 기준 유지")
    #expect(viewModel.summarySentence == "상한 기준이 적용 중입니다. 전원을 연결해도 바로 충전하지 않습니다.")
}

@MainActor
@Test
func menuBarPresentationShowsTemporaryOverrideReservedCopyWhenPowerIsDisconnected() {
    let viewModel = makeViewModel(
        battery: BatterySnapshot(
            chargePercent: 80,
            isPowerConnected: false,
            isCharging: false
        ),
        policy: ChargePolicy(
            upperLimit: 80,
            rechargeThreshold: 75,
            temporaryOverrideUntil: Date(timeIntervalSince1970: 2_000)
        ),
        chargeState: .temporaryOverride,
        now: Date(timeIntervalSince1970: 1_000)
    )

    #expect(viewModel.chargeStateTitle == "임시 해제 예약")
    #expect(viewModel.summarySentence == "상한 해제가 적용 중입니다. 전원을 연결하면 100% 충전을 허용합니다.")
}

@MainActor
@Test
func menuBarPresentationPrefersControllerErrorForReadOnlyCopy() {
    let viewModel = makeViewModel(
        battery: BatterySnapshot(
            chargePercent: 78,
            isPowerConnected: true,
            isCharging: false
        ),
        controllerStatus: ControllerStatus(
            mode: .readOnly,
            helperConnection: .disconnected,
            isChargingEnabled: nil,
            lastErrorDescription: "XPC 연결이 끊겼습니다."
        ),
        chargeState: .errorReadOnly
    )

    #expect(viewModel.chargeStateTitle == "읽기 전용 오류")
    #expect(viewModel.summarySentence == "XPC 연결이 끊겼습니다.")
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

@MainActor
@Test
func viewModelExposesLaunchAtLoginStateFromManager() {
    let manager = MockLaunchAtLoginManager(
        configuredState: LaunchAtLoginState(
            isEnabled: true,
            statusText: "로그인 후 앱을 자동으로 열고 저장된 정책을 복구합니다.",
            errorText: nil
        )
    )

    let viewModel = makeViewModel(
        battery: BatterySnapshot(
            chargePercent: 80,
            isPowerConnected: true,
            isCharging: false
        ),
        chargeState: .holdingAtLimit,
        launchAtLoginManager: manager
    )

    #expect(viewModel.launchAtLoginEnabled)
    #expect(viewModel.launchAtLoginStatusText == "로그인 후 앱을 자동으로 열고 저장된 정책을 복구합니다.")
}

@MainActor
@Test
func viewModelUpdatesLaunchAtLoginStateWhenToggleChanges() {
    let manager = MockLaunchAtLoginManager(
        configuredState: LaunchAtLoginState(
            isEnabled: true,
            statusText: "자동 실행이 켜져 있습니다.",
            errorText: nil
        ),
        updatedState: LaunchAtLoginState(
            isEnabled: false,
            statusText: "로그인 자동 실행이 꺼져 있어 다음 로그인 때는 자동 복구하지 않습니다.",
            errorText: nil
        )
    )

    let viewModel = makeViewModel(
        battery: BatterySnapshot(
            chargePercent: 80,
            isPowerConnected: true,
            isCharging: false
        ),
        chargeState: .holdingAtLimit,
        launchAtLoginManager: manager
    )

    viewModel.setLaunchAtLoginEnabled(false)

    #expect(viewModel.launchAtLoginEnabled == false)
    #expect(viewModel.launchAtLoginStatusText == "로그인 자동 실행이 꺼져 있어 다음 로그인 때는 자동 복구하지 않습니다.")
    #expect(manager.lastRequestedValue == false)
}

@MainActor
private func makeViewModel(
    battery: BatterySnapshot,
    policy: ChargePolicy = ChargePolicy(upperLimit: 80, rechargeThreshold: 75),
    controllerStatus: ControllerStatus = ControllerStatus(
        mode: .fullControl,
        helperConnection: .connected,
        isChargingEnabled: false
    ),
    chargeState: ChargeState,
    launchAtLoginManager: any LaunchAtLoginManaging = DisabledLaunchAtLoginManager(),
    now: Date = Date(timeIntervalSince1970: 1_000)
) -> MenuBarViewModel {
    MenuBarViewModel(
        appState: AppState(
            battery: battery,
            policy: policy,
            controllerStatus: controllerStatus,
            chargeState: chargeState
        ),
        capabilityReport: CapabilityChecker().evaluate(snapshot: battery),
        launchAtLoginManager: launchAtLoginManager,
        now: { now }
    )
}

private final class MockLaunchAtLoginManager: LaunchAtLoginManaging {
    private let configuredState: LaunchAtLoginState
    private let updatedState: LaunchAtLoginState
    private(set) var lastRequestedValue: Bool?

    init(
        configuredState: LaunchAtLoginState,
        updatedState: LaunchAtLoginState? = nil
    ) {
        self.configuredState = configuredState
        self.updatedState = updatedState ?? configuredState
    }

    func configureDefaultIfNeeded() -> LaunchAtLoginState {
        configuredState
    }

    func setEnabled(_ enabled: Bool) -> LaunchAtLoginState {
        lastRequestedValue = enabled
        return updatedState
    }
}
