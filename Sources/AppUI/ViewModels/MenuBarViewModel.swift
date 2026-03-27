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
    private let controlAvailabilityResolver: any ControlAvailabilityResolving
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
        controlAvailabilityResolver: any ControlAvailabilityResolving = ControlAvailabilityResolver(),
        runtimeService: (any AppRuntimeServicing)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.appState = appState
        self.overrideDurationMinutes = overrideDurationMinutes
        self.policyEngine = policyEngine
        self.capabilityChecker = capabilityChecker
        self.controlAvailabilityResolver = controlAvailabilityResolver
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
