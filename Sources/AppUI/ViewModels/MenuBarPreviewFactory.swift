import Core
import Shared

@MainActor
enum MenuBarPreviewFactory {
    static func makeHolding() -> MenuBarViewModel {
        MenuBarViewModel(
            appState: AppState(
                battery: BatterySnapshot(
                    chargePercent: 80,
                    isPowerConnected: true,
                    isCharging: false
                ),
                policy: ChargePolicy(
                    upperLimit: 80,
                    rechargeThreshold: 75
                ),
                controllerStatus: ControllerStatus(
                    mode: .fullControl,
                    helperConnection: .connected,
                    isChargingEnabled: false
                ),
                chargeState: .holdingAtLimit
            ),
            transitionReason: .atUpperLimit,
            capabilityReport: CapabilityReport(
                statuses: [
                    CapabilityStatus(key: .appleSilicon, support: .supported, reason: "Apple Silicon 환경입니다."),
                    CapabilityStatus(key: .macOSVersion, support: .supported, reason: "macOS 26+ 조건을 만족합니다."),
                    CapabilityStatus(key: .batteryObservation, support: .supported, reason: "내장 배터리 상태를 읽을 수 있습니다."),
                    CapabilityStatus(key: .powerSourceObservation, support: .supported, reason: "전원 연결 여부를 읽을 수 있습니다."),
                    CapabilityStatus(key: .sleepWakeResynchronization, support: .supported, reason: "sleep/wake 이후 재동기화가 가능합니다."),
                    CapabilityStatus(key: .helperInstallation, support: .supported, reason: "개발용 helper가 설치되어 launchd와 XPC 연결이 모두 확인되었습니다."),
                    CapabilityStatus(key: .helperPrivilege, support: .supported, reason: "helper가 root 권한으로 실행 중입니다."),
                    CapabilityStatus(key: .chargeControl, support: .experimental, reason: "직접 SMC helper backend가 연결되어 충전 제어를 수행할 수 있습니다.")
                ],
                recommendedControllerMode: .fullControl,
                helperInstallStatus: HelperInstallStatus(
                    state: .xpcReachable,
                    serviceName: CellCapHelperXPC.serviceName,
                    helperPath: CellCapHelperXPC.installedBinaryPath,
                    plistPath: CellCapHelperXPC.launchDaemonPlistPath,
                    helperVersion: CellCapHelperXPC.contractVersion,
                    expectedVersion: CellCapHelperXPC.contractVersion,
                    reason: "개발용 helper가 root로 실행 중입니다."
                )
            )
        )
    }

    static func makeErrorReadOnly() -> MenuBarViewModel {
        MenuBarViewModel(
            appState: AppState(
                battery: BatterySnapshot(
                    chargePercent: 78,
                    isPowerConnected: true,
                    isCharging: true
                ),
                policy: ChargePolicy(
                    upperLimit: 80,
                    rechargeThreshold: 75
                ),
                controllerStatus: ControllerStatus(
                    mode: .readOnly,
                    helperConnection: .disconnected,
                    isChargingEnabled: nil,
                    lastErrorDescription: "XPC 연결이 끊겨 제어를 계속할 수 없습니다."
                ),
                chargeState: .errorReadOnly
            ),
            transitionReason: .helperFailure,
            capabilityReport: CapabilityChecker().evaluate(
                snapshot: BatterySnapshot(
                    chargePercent: 78,
                    isPowerConnected: true,
                    isCharging: true
                )
            )
        )
    }

    static func makeMonitoringOnly() -> MenuBarViewModel {
        MenuBarViewModel(
            appState: AppState(
                battery: nil,
                policy: ChargePolicy(
                    upperLimit: 80,
                    rechargeThreshold: 75,
                    isControlEnabled: false
                ),
                controllerStatus: ControllerStatus(
                    mode: .monitoringOnly,
                    helperConnection: .unavailable,
                    isChargingEnabled: nil
                ),
                chargeState: .suspended
            ),
            transitionReason: .missingBattery,
            capabilityReport: CapabilityReport(
                statuses: [
                    CapabilityStatus(key: .appleSilicon, support: .supported, reason: "Apple Silicon 환경입니다."),
                    CapabilityStatus(key: .macOSVersion, support: .supported, reason: "macOS 26+ 조건을 만족합니다."),
                    CapabilityStatus(key: .batteryObservation, support: .unsupported, reason: "내장 배터리를 찾지 못했습니다."),
                    CapabilityStatus(key: .powerSourceObservation, support: .readOnlyFallback, reason: "배터리 미탑재 장비에서는 전원 판정이 제한됩니다."),
                    CapabilityStatus(key: .sleepWakeResynchronization, support: .supported, reason: "sleep/wake 알림은 받을 수 있습니다."),
                    CapabilityStatus(key: .helperInstallation, support: .unsupported, reason: "이 환경에서는 helper를 설치해도 충전 제어를 시도하지 않습니다."),
                    CapabilityStatus(key: .helperPrivilege, support: .unsupported, reason: "helper 권한이 필요하지 않은 관측 전용 환경입니다."),
                    CapabilityStatus(key: .chargeControl, support: .unsupported, reason: "이 환경에서는 SMC 기반 충전 제어를 시도하지 않습니다.")
                ],
                recommendedControllerMode: .monitoringOnly
            )
        )
    }
}

extension MenuBarViewModel {
    static func previewHolding() -> MenuBarViewModel {
        MenuBarPreviewFactory.makeHolding()
    }

    static func previewErrorReadOnly() -> MenuBarViewModel {
        MenuBarPreviewFactory.makeErrorReadOnly()
    }

    static func previewMonitoringOnly() -> MenuBarViewModel {
        MenuBarPreviewFactory.makeMonitoringOnly()
    }
}
