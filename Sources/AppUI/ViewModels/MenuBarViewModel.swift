import Core
import Shared
import SwiftUI
import SystemSupport

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

    enum HelperAction: Equatable {
        case install
        case openApprovalSettings
        case reinstall
        case remove
    }

    @Published private(set) var appState: AppState
    @Published private(set) var transitionReason: ChargeTransitionReason
    @Published private(set) var capabilityReport: CapabilityReport
    @Published private(set) var diagnosticsSummary: DiagnosticsSummary?
    @Published private(set) var diagnosticsExportPreview: String?
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var launchAtLoginStatusText: String
    @Published private(set) var launchAtLoginErrorText: String?
    @Published var overrideDurationMinutes: Double
    @Published private(set) var helperActionMessage: String?
    @Published private(set) var isHelperActionRunning = false
    @Published var isForceHelperRemovalConfirmationPresented = false

    private let policyEngine: PolicyEngine
    private let capabilityChecker: any CapabilityChecking
    private let controlAvailabilityResolver = ControlAvailabilityResolver()
    private let launchAtLoginManager: any LaunchAtLoginManaging
    private let runtimeService: (any AppRuntimeServicing)?
    private let helperServiceManager: (any HelperServiceManaging)?
    private var installsAfterForcedRemoval = false
    /// 작업 결과 문구가 가리키는 설치 상태. 이후 상태가 바뀌면 오래된 문구를 지운다.
    private var helperActionMessageState: HelperInstallState?
    private let now: @Sendable () -> Date
    private var updatesTask: Task<Void, Never>?

    init(
        appState: AppState,
        transitionReason: ChargeTransitionReason? = nil,
        capabilityReport: CapabilityReport? = nil,
        overrideDurationMinutes: Double = 120,
        policyEngine: PolicyEngine = PolicyEngine(),
        capabilityChecker: any CapabilityChecking = CapabilityChecker(),
        launchAtLoginManager: any LaunchAtLoginManaging = DisabledLaunchAtLoginManager(),
        runtimeService: (any AppRuntimeServicing)? = nil,
        helperServiceManager: (any HelperServiceManaging)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.appState = appState
        self.overrideDurationMinutes = overrideDurationMinutes
        self.policyEngine = policyEngine
        self.capabilityChecker = capabilityChecker
        self.launchAtLoginManager = launchAtLoginManager
        self.runtimeService = runtimeService
        self.helperServiceManager = helperServiceManager
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
        let launchAtLoginState = launchAtLoginManager.configureDefaultIfNeeded()
        self.launchAtLoginEnabled = launchAtLoginState.isEnabled
        self.launchAtLoginStatusText = launchAtLoginState.statusText
        self.launchAtLoginErrorText = launchAtLoginState.errorText
        startRuntimeIfNeeded()
    }

    convenience init(
        service: any AppRuntimeServicing,
        launchAtLoginManager: any LaunchAtLoginManaging = DisabledLaunchAtLoginManager(),
        helperServiceManager: (any HelperServiceManaging)? = nil
    ) {
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
            launchAtLoginManager: launchAtLoginManager,
            runtimeService: service,
            helperServiceManager: helperServiceManager
        )
    }

    var batteryPercentText: String {
        presentation.batteryPercentText
    }

    var chargeStateTitle: String {
        presentation.chargeStateTitle
    }

    var summarySentence: String {
        presentation.summarySentence
    }

    var powerStatusText: String {
        presentation.powerStatusText
    }

    var helperStatusText: String {
        presentation.helperStatusText
    }

    var controllerModeLabel: String {
        presentation.controllerModeLabel
    }

    var helperInstallStateText: String {
        presentation.helperInstallStateText
    }

    var helperInstallReasonText: String? {
        presentation.helperInstallReasonText
    }

    var compactHelperSummaryText: String {
        presentation.compactHelperSummaryText
    }

    var lastControllerErrorText: String? {
        appState.controllerStatus.lastErrorDescription
    }

    var temporaryOverrideSummaryText: String {
        presentation.temporaryOverrideSummaryText
    }

    var temporaryOverrideRemainingText: String? {
        presentation.temporaryOverrideRemainingText
    }

    var temporaryOverrideProgress: Double? {
        presentation.temporaryOverrideProgress
    }

    var capabilityCountSummary: String {
        presentation.capabilityCountSummary
    }

    var menuBarAccessibilityLabel: String {
        presentation.menuBarAccessibilityLabel
    }

    var shouldAutoExpandAdvancedSection: Bool {
        controlAvailabilityResolver.shouldAutoExpandAdvancedSection(
            appState: appState,
            capabilityReport: capabilityReport
        )
    }

    var advancedSectionStatusText: String {
        presentation.advancedSectionStatusText
    }

    var controlNoticeTitle: String {
        presentation.controlNoticeTitle
    }

    var controlNoticeReason: String? {
        controlAvailability.reason
    }

    var temporaryOverrideNoticeTitle: String {
        presentation.temporaryOverrideNoticeTitle
    }

    var temporaryOverrideNoticeReason: String? {
        temporaryOverrideAvailability.reason
    }

    var isReadOnlyPresentation: Bool {
        presentation.isReadOnlyPresentation
    }

    var selectedOverrideDurationLabel: String {
        presentation.selectedOverrideDurationLabel
    }

    var menuBarSymbolName: String {
        presentation.menuBarSymbolName
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
        controlAvailabilityResolver.controlAvailability(
            appState: appState,
            capabilityReport: capabilityReport
        )
    }

    private var effectiveHelperInstallStatus: HelperInstallStatus? {
        controlAvailabilityResolver.effectiveHelperInstallStatus(
            appState: appState,
            capabilityReport: capabilityReport
        )
    }

    var temporaryOverrideAvailability: ControlAvailability {
        controlAvailabilityResolver.temporaryOverrideAvailability(
            appState: appState,
            capabilityReport: capabilityReport
        )
    }

    var isTemporaryOverrideActive: Bool {
        appState.policy.isTemporaryOverrideActive(at: now())
    }

    var diagnosticsSummaryText: String {
        presentation.diagnosticsSummaryText
    }

    var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { self.launchAtLoginEnabled },
            set: { self.setLaunchAtLoginEnabled($0) }
        )
    }

    var availableHelperActions: [HelperAction] {
        guard helperServiceManager != nil else { return [] }
        return presentation.availableHelperActions
    }

    func helperActionTitle(for action: HelperAction) -> String {
        presentation.helperActionTitle(for: action)
    }

    func performHelperAction(_ action: HelperAction) {
        guard let helperServiceManager, !isHelperActionRunning else { return }

        if action == .openApprovalSettings {
            helperServiceManager.openApprovalSettings()
            return
        }

        runHelperAction {
            switch action {
            case .install:
                return await helperServiceManager.install()
            case .remove, .reinstall:
                let removal = await helperServiceManager.remove(force: false)
                guard action == .reinstall, case .completed = removal else {
                    if case .releaseFailed = removal {
                        await MainActor.run { self.installsAfterForcedRemoval = action == .reinstall }
                    }
                    return removal
                }
                return await helperServiceManager.install()
            case .openApprovalSettings:
                return nil
            }
        }
    }

    func confirmForcedHelperRemoval() {
        guard let helperServiceManager else { return }
        let installsAfterRemoval = installsAfterForcedRemoval
        installsAfterForcedRemoval = false

        runHelperAction {
            let removal = await helperServiceManager.remove(force: true)
            guard installsAfterRemoval, case .completed = removal else { return removal }
            return await helperServiceManager.install()
        }
    }

    private func clearStaleHelperActionMessage() {
        guard let messageState = helperActionMessageState,
              effectiveHelperInstallStatus?.state != messageState else { return }
        helperActionMessage = nil
        helperActionMessageState = nil
    }

    func cancelForcedHelperRemoval() {
        installsAfterForcedRemoval = false
    }

    private func runHelperAction(_ operation: @escaping @Sendable () async -> HelperServiceActionResult?) {
        isHelperActionRunning = true
        helperActionMessage = nil
        helperActionMessageState = nil

        Task {
            let result = await operation()
            await MainActor.run {
                self.isHelperActionRunning = false
                self.helperActionMessage = result?.message
                if case .releaseFailed = result {
                    self.isForceHelperRemovalConfirmationPresented = true
                }
            }
            // 설치/제거 결과가 바로 화면과 제어 가능 여부에 반영되도록 캐시를 우회해 다시 동기화한다.
            await runtimeService?.refresh(trigger: .manualRefresh)
            await MainActor.run {
                self.helperActionMessageState = self.effectiveHelperInstallStatus?.state
            }
        }
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

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        apply(launchAtLoginState: launchAtLoginManager.setEnabled(enabled))
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
        presentation.capabilityLabel(for: support)
    }

    func capabilityTitle(for key: CapabilityKey) -> String {
        presentation.capabilityTitle(for: key)
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

    private func apply(launchAtLoginState: LaunchAtLoginState) {
        launchAtLoginEnabled = launchAtLoginState.isEnabled
        launchAtLoginStatusText = launchAtLoginState.statusText
        launchAtLoginErrorText = launchAtLoginState.errorText
    }

    private func startRuntimeIfNeeded() {
        guard let runtimeService, updatesTask == nil else { return }

        updatesTask = Task { [weak self] in
            guard let self else { return }
            let stream = await runtimeService.makeUpdateStream()
            for await update in stream {
                await MainActor.run {
                    self.appState = update.appState
                    self.transitionReason = update.transitionReason
                    self.capabilityReport = update.capabilityReport
                    self.diagnosticsSummary = update.diagnosticsSummary
                    self.clearStaleHelperActionMessage()
                }
            }
        }

        Task {
            await runtimeService.start()
        }
    }
}

private extension MenuBarViewModel {
    var presentation: MenuBarPresentation {
        MenuBarPresentation(
            appState: appState,
            capabilityReport: capabilityReport,
            diagnosticsSummary: diagnosticsSummary,
            helperInstallStatus: effectiveHelperInstallStatus,
            controlAvailability: controlAvailability,
            temporaryOverrideAvailability: temporaryOverrideAvailability,
            shouldAutoExpandAdvancedSection: shouldAutoExpandAdvancedSection,
            overrideDurationMinutes: overrideDurationMinutes,
            now: now()
        )
    }
}
