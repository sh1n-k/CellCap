import Core
import Shared
import SwiftUI

@MainActor
final class MenuBarViewModel: ObservableObject {
    struct ControlAvailability: Equatable {
        let isEnabled: Bool
        let reason: String?

        static let enabled = ControlAvailability(isEnabled: true, reason: nil)

        static func disabled(_ reason: String) -> ControlAvailability {
            ControlAvailability(isEnabled: false, reason: reason)
        }
    }

    @Published private(set) var appState: AppState
    @Published private(set) var transitionReason: ChargeTransitionReason
    @Published private(set) var capabilityReport: CapabilityReport
    @Published var overrideDurationMinutes: Double

    private let policyEngine: PolicyEngine
    private let capabilityChecker: any CapabilityChecking
    private let now: @Sendable () -> Date

    init(
        appState: AppState,
        transitionReason: ChargeTransitionReason? = nil,
        capabilityReport: CapabilityReport? = nil,
        overrideDurationMinutes: Double = 120,
        policyEngine: PolicyEngine = PolicyEngine(),
        capabilityChecker: any CapabilityChecking = CapabilityChecker(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.appState = appState
        self.overrideDurationMinutes = overrideDurationMinutes
        self.policyEngine = policyEngine
        self.capabilityChecker = capabilityChecker
        self.now = now

        let seededReason = transitionReason ?? policyEngine.evaluate(
            context: ChargeStateContext(
                battery: appState.battery,
                policy: appState.policy,
                controllerStatus: appState.controllerStatus,
                now: now()
            ),
            from: appState.chargeState
        ).transition.reason
        self.transitionReason = seededReason
        self.capabilityReport = capabilityReport ?? capabilityChecker.evaluate(snapshot: appState.battery)
    }

    var batteryPercentText: String {
        appState.battery.map { "\($0.chargePercent)%" } ?? "배터리 없음"
    }

    var chargeStateTitle: String {
        switch appState.chargeState {
        case .charging:
            return "다시 충전 중"
        case .holdingAtLimit:
            return "상한 유지 중"
        case .waitingForRecharge:
            return "재충전 대기 중"
        case .temporaryOverride:
            return "임시 해제 중"
        case .suspended:
            return "제어 중단"
        case .errorReadOnly:
            return "읽기 전용 오류"
        }
    }

    var summarySentence: String {
        let percent = appState.battery?.chargePercent ?? 0

        switch appState.chargeState {
        case .charging:
            return "\(appState.policy.rechargeThreshold)% 이하로 내려가 \(percent)%에서 다시 충전 중입니다."
        case .holdingAtLimit:
            return "\(appState.policy.upperLimit)% 상한을 기준으로 충전을 멈추고 유지 중입니다."
        case .waitingForRecharge:
            return "\(appState.policy.rechargeThreshold)% 이하가 될 때까지 \(percent)%에서 대기합니다."
        case .temporaryOverride:
            if let until = appState.policy.temporaryOverrideUntil {
                return "\(timeString(until))까지 상한을 잠시 해제해 전체 충전을 허용합니다."
            }
            return "상한을 잠시 해제해 전체 충전을 허용합니다."
        case .suspended:
            return "제어를 멈추고 관측 모드로 대기합니다."
        case .errorReadOnly:
            return appState.controllerStatus.lastErrorDescription
                ?? "helper 상태를 신뢰할 수 없어 읽기 전용으로 전환했습니다."
        }
    }

    var powerStatusText: String {
        guard let battery = appState.battery else { return "배터리 정보 없음" }
        return battery.isPowerConnected ? "전원 연결됨" : "배터리 전원 사용 중"
    }

    var helperStatusText: String {
        switch appState.controllerStatus.helperConnection {
        case .connected:
            return "helper 연결 정상"
        case .disconnected:
            return "helper 연결 끊김"
        case .unavailable:
            return "helper 미구현"
        }
    }

    var controllerModeLabel: String {
        switch appState.controllerStatus.mode {
        case .fullControl:
            return "Full Control"
        case .readOnly:
            return "Read-only"
        case .monitoringOnly:
            return "Monitoring-only"
        }
    }

    var menuBarSymbolName: String {
        switch appState.chargeState {
        case .holdingAtLimit:
            return "battery.100.bolt"
        case .charging, .temporaryOverride:
            return "bolt.batteryblock"
        case .waitingForRecharge:
            return "battery.75"
        case .suspended:
            return "pause.circle"
        case .errorReadOnly:
            return "exclamationmark.triangle.fill"
        }
    }

    var upperLimitBinding: Binding<Double> {
        Binding(
            get: { Double(self.appState.policy.upperLimit) },
            set: { self.updateUpperLimit(Int($0.rounded())) }
        )
    }

    var rechargeThresholdBinding: Binding<Double> {
        Binding(
            get: { Double(self.appState.policy.rechargeThreshold) },
            set: { self.updateRechargeThreshold(Int($0.rounded())) }
        )
    }

    var controlAvailability: ControlAvailability {
        if let error = appState.controllerStatus.lastErrorDescription, appState.chargeState == .errorReadOnly {
            return .disabled(error)
        }

        guard appState.battery?.isBatteryPresent == true else {
            return .disabled("내장 배터리를 찾지 못했습니다.")
        }

        if let chargeControl = capabilityReport.status(for: .chargeControl) {
            switch chargeControl.support {
            case .supported, .experimental:
                break
            case .unsupported, .readOnlyFallback:
                return .disabled(chargeControl.reason)
            }
        }

        switch appState.controllerStatus.mode {
        case .fullControl:
            return .enabled
        case .readOnly:
            return .disabled("현재 제어 모드가 읽기 전용입니다.")
        case .monitoringOnly:
            return .disabled("현재 기기는 관측 전용 모드입니다.")
        }
    }

    var temporaryOverrideAvailability: ControlAvailability {
        if appState.chargeState == .temporaryOverride {
            return .enabled
        }

        return controlAvailability
    }

    var isTemporaryOverrideActive: Bool {
        appState.policy.isTemporaryOverrideActive(at: now())
    }

    func recomputeState() {
        apply(policy: appState.policy)
    }

    func startTemporaryOverride() {
        guard temporaryOverrideAvailability.isEnabled else { return }
        var policy = appState.policy
        policy.temporaryOverrideUntil = now().addingTimeInterval(overrideDurationMinutes * 60)
        apply(policy: policy)
    }

    func clearTemporaryOverride() {
        var policy = appState.policy
        policy.temporaryOverrideUntil = nil
        apply(policy: policy)
    }

    func updateUpperLimit(_ value: Int) {
        var policy = appState.policy
        let clampedUpperLimit = min(ChargePolicy.maximumUpperLimit, max(ChargePolicy.minimumUpperLimit, value))
        policy.upperLimit = clampedUpperLimit

        if policy.rechargeThreshold > clampedUpperLimit {
            policy.rechargeThreshold = max(0, clampedUpperLimit - 5)
        }

        apply(policy: policy)
    }

    func updateRechargeThreshold(_ value: Int) {
        var policy = appState.policy
        policy.rechargeThreshold = min(policy.upperLimit, max(0, value))
        apply(policy: policy)
    }

    func capabilityLabel(for support: CapabilitySupport) -> String {
        switch support {
        case .supported:
            return "지원"
        case .unsupported:
            return "미지원"
        case .experimental:
            return "실험적"
        case .readOnlyFallback:
            return "읽기 전용"
        }
    }

    func capabilityTitle(for key: CapabilityKey) -> String {
        switch key {
        case .appleSilicon:
            return "Apple Silicon"
        case .macOSVersion:
            return "macOS 26+"
        case .batteryObservation:
            return "배터리 읽기"
        case .powerSourceObservation:
            return "전원 연결 감지"
        case .sleepWakeResynchronization:
            return "sleep/wake 재동기화"
        case .chargeControl:
            return "충전 제어"
        }
    }

    private func apply(policy: ChargePolicy) {
        let evaluation = policyEngine.evaluate(
            context: ChargeStateContext(
                battery: appState.battery,
                policy: policy,
                controllerStatus: appState.controllerStatus,
                now: now()
            ),
            from: appState.chargeState
        )

        let updatedPolicy = ChargePolicy(
            upperLimit: evaluation.effectivePolicy.upperLimit,
            rechargeThreshold: evaluation.effectivePolicy.rechargeThreshold,
            temporaryOverrideUntil: evaluation.effectivePolicy.temporaryOverrideUntil,
            isControlEnabled: evaluation.effectivePolicy.isControlEnabled
        )

        appState = AppState(
            battery: evaluation.resolution.selectedBattery,
            policy: updatedPolicy,
            controllerStatus: appState.controllerStatus,
            chargeState: evaluation.transition.current,
            lastUpdatedAt: now()
        )
        transitionReason = evaluation.transition.reason
        capabilityReport = capabilityChecker.evaluate(snapshot: appState.battery)
    }

    private func timeString(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

extension MenuBarViewModel {
    static func previewHolding() -> MenuBarViewModel {
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
                    CapabilityStatus(key: .chargeControl, support: .experimental, reason: "UI와 정책은 준비되었지만 실제 제어 helper는 아직 stub입니다.")
                ],
                recommendedControllerMode: .readOnly
            )
        )
    }

    static func previewErrorReadOnly() -> MenuBarViewModel {
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

    static func previewMonitoringOnly() -> MenuBarViewModel {
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
                    CapabilityStatus(key: .chargeControl, support: .readOnlyFallback, reason: "이 환경에서는 충전 제어 대신 관측 전용으로 남깁니다.")
                ],
                recommendedControllerMode: .monitoringOnly
            )
        )
    }
}
