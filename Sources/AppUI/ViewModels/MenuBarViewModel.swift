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
    @Published private(set) var diagnosticsSummary: DiagnosticsSummary?
    @Published private(set) var diagnosticsExportPreview: String?
    @Published var overrideDurationMinutes: Double

    private let policyEngine: PolicyEngine
    private let capabilityChecker: any CapabilityChecking
    private let runtimeService: (any AppRuntimeServicing)?
    private let now: @Sendable () -> Date
    private var updatesTask: Task<Void, Never>?

    init(
        appState: AppState,
        transitionReason: ChargeTransitionReason? = nil,
        capabilityReport: CapabilityReport? = nil,
        overrideDurationMinutes: Double = 120,
        policyEngine: PolicyEngine = PolicyEngine(),
        capabilityChecker: any CapabilityChecking = CapabilityChecker(),
        runtimeService: (any AppRuntimeServicing)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.appState = appState
        self.overrideDurationMinutes = overrideDurationMinutes
        self.policyEngine = policyEngine
        self.capabilityChecker = capabilityChecker
        self.runtimeService = runtimeService
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
        startRuntimeIfNeeded()
    }

    convenience init(service: any AppRuntimeServicing) {
        self.init(
            appState: AppState(
                battery: nil,
                policy: ChargePolicy(),
                controllerStatus: ControllerStatus(
                    mode: .readOnly,
                    helperConnection: .unavailable,
                    isChargingEnabled: nil,
                    temporaryOverrideUntil: nil,
                    lastErrorDescription: "초기 동기화 전입니다."
                ),
                chargeState: .suspended
            ),
            transitionReason: .missingBattery,
            capabilityReport: CapabilityChecker().evaluate(snapshot: nil),
            runtimeService: service
        )
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
        if let installStatus = effectiveHelperInstallStatus {
            switch installStatus.state {
            case .notInstalled:
                return "helper 미설치"
            case .installedButNotBootstrapped:
                return "helper 미기동"
            case .bootstrapped:
                return "helper 등록됨"
            case .xpcReachable:
                break
            case .permissionMismatch:
                return "helper 권한 불일치"
            case .versionMismatch:
                return "helper 버전 불일치"
            }
        }

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

    var helperInstallStateText: String {
        guard let installStatus = effectiveHelperInstallStatus else {
            return "설치 상태 미확인"
        }

        switch installStatus.state {
        case .notInstalled:
            return "미설치"
        case .installedButNotBootstrapped:
            return "설치됨, 미기동"
        case .bootstrapped:
            return "launchd 등록"
        case .xpcReachable:
            return "XPC 연결 확인"
        case .permissionMismatch:
            return "권한 불일치"
        case .versionMismatch:
            return "버전 불일치"
        }
    }

    var helperInstallReasonText: String? {
        effectiveHelperInstallStatus?.reason
            ?? capabilityReport.status(for: .helperInstallation)?.reason
            ?? capabilityReport.status(for: .helperPrivilege)?.reason
    }

    var controlNoticeTitle: String {
        switch appState.controllerStatus.mode {
        case .fullControl:
            return "정책 변경 가능"
        case .readOnly:
            return "지금은 읽기 전용 상태입니다"
        case .monitoringOnly:
            return "지금은 관측 전용 상태입니다"
        }
    }

    var controlNoticeReason: String? {
        controlAvailability.reason
    }

    var temporaryOverrideNoticeTitle: String {
        switch appState.controllerStatus.mode {
        case .fullControl:
            return "임시 해제 가능"
        case .readOnly:
            return "지금은 임시 해제를 시작할 수 없습니다"
        case .monitoringOnly:
            return "지금은 임시 해제를 사용할 수 없습니다"
        }
    }

    var temporaryOverrideNoticeReason: String? {
        temporaryOverrideAvailability.reason
    }

    var isReadOnlyPresentation: Bool {
        !controlAvailability.isEnabled || appState.controllerStatus.mode != .fullControl
    }

    var selectedOverrideDurationLabel: String {
        switch Int(overrideDurationMinutes.rounded()) {
        case 30:
            return "30분"
        case 60:
            return "1시간"
        case 120:
            return "2시간"
        case 240:
            return "4시간"
        default:
            return "\(Int(overrideDurationMinutes.rounded()))분"
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

        if let installStatus = effectiveHelperInstallStatus, installStatus.installationSupport != .supported {
            return .disabled(installStatus.reason)
        }

        for key in [CapabilityKey.helperPrivilege, .chargeControl] {
            guard let status = capabilityReport.status(for: key) else { continue }

            switch status.support {
            case .supported:
                continue
            case .experimental:
                if key == .chargeControl {
                    continue
                }
                return .disabled(status.reason)
            case .unsupported:
                return .disabled(status.reason)
            case .readOnlyFallback:
                return .disabled(status.reason)
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

    private var effectiveHelperInstallStatus: HelperInstallStatus? {
        guard let installStatus = capabilityReport.helperInstallStatus else {
            return nil
        }

        guard appState.controllerStatus.helperConnection == .connected else {
            return installStatus
        }

        switch installStatus.state {
        case .bootstrapped, .installedButNotBootstrapped:
            return HelperInstallStatus(
                state: .xpcReachable,
                serviceName: installStatus.serviceName,
                helperPath: installStatus.helperPath,
                plistPath: installStatus.plistPath,
                helperVersion: installStatus.helperVersion,
                expectedVersion: installStatus.expectedVersion,
                reason: "helper XPC 연결이 확인되었습니다. 권한 및 SMC 키 검사를 계속 진행합니다.",
                checkedAt: installStatus.checkedAt
            )
        case .notInstalled, .xpcReachable, .permissionMismatch, .versionMismatch:
            return installStatus
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

    var diagnosticsSummaryText: String {
        guard let diagnosticsSummary else {
            return "진단 요약이 아직 준비되지 않았습니다."
        }

        var parts: [String] = []
        if let state = diagnosticsSummary.currentChargeState?.rawValue {
            parts.append("상태 \(state)")
        }
        if let mode = diagnosticsSummary.currentControllerMode?.rawValue {
            parts.append("모드 \(mode)")
        }
        if let fallback = diagnosticsSummary.lastReadOnlyFallbackReason {
            parts.append("fallback \(fallback)")
        }
        if let helperInstallState = diagnosticsSummary.helperInstallState?.rawValue {
            parts.append("helper \(helperInstallState)")
        }
        return parts.isEmpty ? "진단 이벤트가 아직 없습니다." : parts.joined(separator: " / ")
    }

    func recomputeState() {
        guard let runtimeService else {
            apply(policy: appState.policy)
            return
        }

        Task {
            await runtimeService.refresh(trigger: .manualRefresh)
        }
    }

    func startTemporaryOverride() {
        guard temporaryOverrideAvailability.isEnabled else { return }
        var policy = appState.policy
        policy.temporaryOverrideUntil = now().addingTimeInterval(overrideDurationMinutes * 60)
        submit(policy: policy)
    }

    func clearTemporaryOverride() {
        var policy = appState.policy
        policy.temporaryOverrideUntil = nil
        submit(policy: policy)
    }

    func updateUpperLimit(_ value: Int) {
        var policy = appState.policy
        let clampedUpperLimit = min(ChargePolicy.maximumUpperLimit, max(ChargePolicy.minimumUpperLimit, value))
        policy.upperLimit = clampedUpperLimit

        if policy.rechargeThreshold > clampedUpperLimit {
            policy.rechargeThreshold = max(0, clampedUpperLimit - 5)
        }

        submit(policy: policy)
    }

    func updateRechargeThreshold(_ value: Int) {
        var policy = appState.policy
        policy.rechargeThreshold = min(policy.upperLimit, max(0, value))
        submit(policy: policy)
    }

    func refreshDiagnostics() {
        guard let runtimeService else { return }
        Task {
            let summary = await runtimeService.diagnosticsSummary()
            await MainActor.run {
                self.diagnosticsSummary = summary
            }
        }
    }

    func prepareDiagnosticsExport() {
        guard let runtimeService else { return }
        Task {
            let artifact = try? await runtimeService.exportDiagnostics()
            await MainActor.run {
                self.diagnosticsExportPreview = artifact?.utf8Contents
            }
        }
    }

    private func submit(policy: ChargePolicy) {
        if let runtimeService {
            Task {
                await runtimeService.setPolicy(policy)
            }
            return
        }

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
        case .helperInstallation:
            return "Helper 설치"
        case .helperPrivilege:
            return "Helper 권한"
        case .chargeControl:
            return "충전 제어"
        }
    }

    private func apply(policy: ChargePolicy) {
        let evaluation = policyEngine.evaluate(
            context: ChargeStateContext(
                battery: appState.battery,
                batterySnapshots: appState.battery.map { [$0] } ?? [],
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

    private func startRuntimeIfNeeded() {
        guard let runtimeService, updatesTask == nil else { return }

        updatesTask = Task { [weak self] in
            guard let self else { return }
            let stream = await runtimeService.makeUpdateStream()
            for await update in stream {
                let summary = await runtimeService.diagnosticsSummary()
                await MainActor.run {
                    self.appState = update.appState
                    self.transitionReason = update.transitionReason
                    self.capabilityReport = update.capabilityReport
                    self.diagnosticsSummary = summary
                }
            }
        }

        Task {
            await runtimeService.start()
            let summary = await runtimeService.diagnosticsSummary()
            await MainActor.run {
                self.diagnosticsSummary = summary
            }
        }
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
                    CapabilityStatus(key: .helperInstallation, support: .unsupported, reason: "이 환경에서는 helper를 설치해도 충전 제어를 시도하지 않습니다."),
                    CapabilityStatus(key: .helperPrivilege, support: .unsupported, reason: "helper 권한이 필요하지 않은 관측 전용 환경입니다."),
                    CapabilityStatus(key: .chargeControl, support: .unsupported, reason: "이 환경에서는 SMC 기반 충전 제어를 시도하지 않습니다.")
                ],
                recommendedControllerMode: .monitoringOnly
            )
        )
    }
}
