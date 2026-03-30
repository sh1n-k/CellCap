import Foundation
import Shared

public enum AppRuntimeTrigger: Sendable, Equatable {
    case appLaunch
    case manualRefresh
    case policyChanged
    case batteryEvent(BatteryMonitorTrigger)
    case resynchronization
}

public struct AppRuntimeUpdate: Sendable, Equatable {
    public var appState: AppState
    public var transitionReason: ChargeTransitionReason
    public var capabilityReport: CapabilityReport
    public var lastTrigger: AppRuntimeTrigger
    public var chargingCommand: ChargingCommand

    public init(
        appState: AppState,
        transitionReason: ChargeTransitionReason,
        capabilityReport: CapabilityReport,
        lastTrigger: AppRuntimeTrigger,
        chargingCommand: ChargingCommand
    ) {
        self.appState = appState
        self.transitionReason = transitionReason
        self.capabilityReport = capabilityReport
        self.lastTrigger = lastTrigger
        self.chargingCommand = chargingCommand
    }
}

public protocol AppRuntimeServicing: Sendable {
    func makeUpdateStream() async -> AsyncStream<AppRuntimeUpdate>
    func start() async
    func refresh(trigger: AppRuntimeTrigger) async
    func setPolicy(_ policy: ChargePolicy) async
    func diagnosticsSummary() async -> DiagnosticsSummary
    func exportDiagnostics() async throws -> DiagnosticsExportArtifact
    func recentDiagnosticEvents(limit: Int?) async -> [DiagnosticEvent]
}

public actor AppRuntimeOrchestrator: AppRuntimeServicing {
    private let batteryMonitor: any BatteryMonitoring
    private let controller: any ChargeController
    private let helperInstallChecker: any HelperInstallChecking
    private let policyStore: any ChargePolicyStoring
    private let policyEngine: PolicyEngine
    private let dateProvider: any DateProviding
    private let eventLogger: any EventLogging
    private let capabilityReportResolver: any CapabilityReportResolving
    private let runtimeSafetyGate: any RuntimeSafetyGating
    private let controllerCommandApplier: any ControllerCommandApplying
    private let selfTestPolicy: any SelfTestPolicying

    private var currentUpdate: AppRuntimeUpdate
    private var latestSystemSnapshot: BatterySnapshot?
    private var continuations: [UUID: AsyncStream<AppRuntimeUpdate>.Continuation] = [:]
    private var monitorTask: Task<Void, Never>?
    private var started = false

    public init(
        initialPolicy: ChargePolicy = ChargePolicy(),
        batteryMonitor: any BatteryMonitoring,
        controller: any ChargeController,
        capabilityChecker: any CapabilityChecking = CapabilityChecker(),
        capabilityProber: (any HelperCapabilityProbing)? = nil,
        helperInstallChecker: any HelperInstallChecking = SystemHelperInstallChecker(),
        policyStore: any ChargePolicyStoring = DiscardingChargePolicyStore(),
        policyEngine: PolicyEngine = PolicyEngine(),
        dateProvider: any DateProviding = SystemDateProvider(),
        eventLogger: any EventLogging = EventLogger()
    ) {
        self.batteryMonitor = batteryMonitor
        self.controller = controller
        self.helperInstallChecker = helperInstallChecker
        self.policyStore = policyStore
        self.policyEngine = policyEngine
        self.dateProvider = dateProvider
        self.eventLogger = eventLogger
        self.capabilityReportResolver = CapabilityReportResolver(
            capabilityChecker: capabilityChecker,
            capabilityProber: capabilityProber,
            eventLogger: eventLogger
        )
        self.runtimeSafetyGate = RuntimeSafetyGate()
        self.controllerCommandApplier = ControllerCommandApplier(
            controller: controller,
            eventLogger: eventLogger
        )
        self.selfTestPolicy = SelfTestPolicy(
            controller: controller,
            eventLogger: eventLogger
        )

        let initialStatus = ControllerStatus(
            mode: .readOnly,
            helperConnection: .unavailable,
            isChargingEnabled: nil,
            temporaryOverrideUntil: nil,
            lastErrorDescription: "초기 동기화 전입니다.",
            checkedAt: dateProvider.now
        )
        let initialState = AppState(
            battery: nil,
            policy: initialPolicy,
            controllerStatus: initialStatus,
            chargeState: .suspended,
            lastUpdatedAt: dateProvider.now
        )
        self.currentUpdate = AppRuntimeUpdate(
            appState: initialState,
            transitionReason: .missingBattery,
            capabilityReport: capabilityChecker.evaluate(snapshot: nil),
            lastTrigger: .appLaunch,
            chargingCommand: .noChange
        )
    }

    deinit {
        monitorTask?.cancel()
    }

    public func makeUpdateStream() -> AsyncStream<AppRuntimeUpdate> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation

            if started {
                continuation.yield(currentUpdate)
            }

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { await self.removeContinuation(id) }
            }
        }
    }

    public func start() async {
        guard !started else { return }
        started = true

        await restorePersistedPolicyIfNeeded()

        await eventLogger.record(
            level: .notice,
            category: .runtime,
            message: "앱 런타임 동기화를 시작합니다.",
            details: ["trigger": AppRuntimeTrigger.appLaunch.debugName],
            userFacingSummary: nil
        )

        let monitorStream = batteryMonitor.makeUpdateStream(emitInitialSnapshot: false)
        monitorTask = Task {
            do {
                for try await update in monitorStream {
                    await self.handleBatteryMonitorUpdate(update)
                }
            } catch {
                await self.refresh(trigger: .resynchronization)
            }
        }

        await synchronize(
            trigger: .appLaunch,
            preferredSnapshot: try? batteryMonitor.currentSnapshot(now: dateProvider.now),
            allowResynchronization: true
        )
    }

    public func refresh(trigger: AppRuntimeTrigger = .manualRefresh) async {
        await synchronize(
            trigger: trigger,
            preferredSnapshot: try? batteryMonitor.currentSnapshot(now: dateProvider.now),
            allowResynchronization: true
        )
    }

    public func setPolicy(_ policy: ChargePolicy) async {
        let previousPolicy = currentUpdate.appState.policy
        await eventLogger.record(
            level: .notice,
            category: .policyChanged,
            message: "충전 정책이 변경되었습니다.",
            details: [
                "previousUpperLimit": String(previousPolicy.upperLimit),
                "previousRechargeThreshold": String(previousPolicy.rechargeThreshold),
                "nextUpperLimit": String(policy.upperLimit),
                "nextRechargeThreshold": String(policy.rechargeThreshold),
                "overrideUntil": policy.temporaryOverrideUntil?.ISO8601Format() ?? "nil"
            ],
            userFacingSummary: "충전 정책을 다시 계산합니다."
        )
        await persistPolicy(
            policy,
            reason: "user-update",
            userFacingSummary: "변경한 충전 정책을 저장하지 못했습니다."
        )
        currentUpdate.appState.policy = policy
        await synchronize(
            trigger: .policyChanged,
            preferredSnapshot: latestSystemSnapshot,
            allowResynchronization: true
        )
    }

    public func diagnosticsSummary() async -> DiagnosticsSummary {
        await eventLogger.diagnosticsSummary(currentUpdate: currentUpdate)
    }

    public func exportDiagnostics() async throws -> DiagnosticsExportArtifact {
        try await eventLogger.exportDiagnostics(currentUpdate: currentUpdate)
    }

    public func recentDiagnosticEvents(limit: Int? = nil) async -> [DiagnosticEvent] {
        await eventLogger.recentEvents(limit: limit)
    }

    private func handleBatteryMonitorUpdate(_ update: BatteryMonitorUpdate) async {
        await eventLogger.record(
            level: .info,
            category: .runtime,
            message: "BatteryMonitor 이벤트를 수신했습니다.",
            details: [
                "trigger": update.trigger.rawValue,
                "chargePercent": update.snapshot.map { String($0.chargePercent) } ?? "nil",
                "powerConnected": update.snapshot.map { String($0.isPowerConnected) } ?? "nil"
            ],
            userFacingSummary: nil
        )

        latestSystemSnapshot = update.snapshot
        await synchronize(
            trigger: .batteryEvent(update.trigger),
            preferredSnapshot: update.snapshot,
            allowResynchronization: update.trigger == .didWake || update.trigger == .powerSourceChanged
        )
    }

    private func synchronize(
        trigger: AppRuntimeTrigger,
        preferredSnapshot: BatterySnapshot?,
        allowResynchronization: Bool
    ) async {
        let previousPolicy = currentUpdate.appState.policy
        let now = dateProvider.now
        let systemSnapshot = preferredSnapshot ?? latestSystemSnapshot ?? (try? batteryMonitor.currentSnapshot(now: now))
        latestSystemSnapshot = systemSnapshot ?? latestSystemSnapshot

        let helperInstallStatus = await helperInstallChecker.currentStatus(now: now)
        var controllerStatus = await controller.getControllerStatus()
        let selfTestResult = await selfTestPolicy.performIfNeeded(
            trigger: trigger,
            helperInstallStatus: helperInstallStatus,
            controllerStatus: controllerStatus
        )
        var capabilityReport = await capabilityReportResolver.resolve(
            snapshot: systemSnapshot,
            controllerStatus: controllerStatus,
            trigger: trigger,
            helperInstallStatus: helperInstallStatus
        )
        let preflightGate = runtimeSafetyGate.apply(
            controllerStatus: controllerStatus,
            capabilityReport: capabilityReport,
            selfTestResult: selfTestResult,
            now: now
        )
        controllerStatus = preflightGate.controllerStatus
        capabilityReport = preflightGate.capabilityReport
        var evaluation = policyEngine.evaluate(
            context: ChargeStateContext(
                battery: systemSnapshot,
                batterySnapshots: buildSnapshotCandidates(systemSnapshot: systemSnapshot),
                policy: currentUpdate.appState.policy,
                controllerStatus: controllerStatus,
                now: now
            ),
            from: currentUpdate.appState.chargeState
        )
        controllerStatus = await controllerCommandApplier.applyIfNeeded(
            controllerStatus: controllerStatus,
            capabilityReport: capabilityReport,
            evaluation: evaluation,
            now: now
        )
        capabilityReport = await capabilityReportResolver.resolve(
            snapshot: systemSnapshot,
            controllerStatus: controllerStatus,
            trigger: trigger,
            helperInstallStatus: helperInstallStatus
        )
        let finalGate = runtimeSafetyGate.apply(
            controllerStatus: controllerStatus,
            capabilityReport: capabilityReport,
            selfTestResult: selfTestResult,
            now: now
        )
        controllerStatus = finalGate.controllerStatus
        capabilityReport = finalGate.capabilityReport
        evaluation = policyEngine.evaluate(
            context: ChargeStateContext(
                battery: systemSnapshot,
                batterySnapshots: buildSnapshotCandidates(systemSnapshot: systemSnapshot),
                policy: currentUpdate.appState.policy,
                controllerStatus: controllerStatus,
                now: now
            ),
            from: currentUpdate.appState.chargeState
        )

        let previousState = currentUpdate.appState.chargeState
        let nextUpdate = AppRuntimeUpdate(
            appState: AppState(
                battery: evaluation.resolution.selectedBattery,
                policy: ChargePolicy(
                    upperLimit: evaluation.effectivePolicy.upperLimit,
                    rechargeThreshold: evaluation.effectivePolicy.rechargeThreshold,
                    temporaryOverrideUntil: evaluation.effectivePolicy.temporaryOverrideUntil,
                    isControlEnabled: evaluation.effectivePolicy.isControlEnabled
                ),
                controllerStatus: controllerStatus,
                chargeState: evaluation.transition.current,
                lastUpdatedAt: now
            ),
            transitionReason: evaluation.transition.reason,
            capabilityReport: capabilityReport,
            lastTrigger: trigger,
            chargingCommand: evaluation.chargingCommand
        )

        await eventLogger.record(
            level: nextUpdate.appState.chargeState == .errorReadOnly ? .error : .notice,
            category: .stateTransition,
            message: "상태를 재평가했습니다.",
            details: [
                "trigger": trigger.debugName,
                "previousState": previousState.rawValue,
                "currentState": nextUpdate.appState.chargeState.rawValue,
                "reason": nextUpdate.transitionReason.rawValue,
                "controllerMode": nextUpdate.appState.controllerStatus.mode.rawValue,
                "helperConnection": nextUpdate.appState.controllerStatus.helperConnection.rawValue,
                "chargingCommand": nextUpdate.chargingCommand.rawValue
            ],
            userFacingSummary: transitionSummary(for: nextUpdate)
        )

        currentUpdate = nextUpdate
        broadcast(nextUpdate)

        if nextUpdate.appState.policy != previousPolicy {
            await persistPolicy(
                nextUpdate.appState.policy,
                reason: "normalized-\(trigger.debugName)",
                userFacingSummary: "정규화된 충전 정책을 저장하지 못했습니다."
            )
        }

        if allowResynchronization && needsResynchronization(update: nextUpdate) {
            await eventLogger.record(
                level: .warning,
                category: .runtime,
                message: "상태 불일치로 재동기화를 수행합니다.",
                details: [
                    "trigger": trigger.debugName,
                    "chargeState": nextUpdate.appState.chargeState.rawValue,
                    "controllerMode": nextUpdate.appState.controllerStatus.mode.rawValue
                ],
                userFacingSummary: "상태 불일치가 감지되어 다시 동기화합니다."
            )
            await synchronize(
                trigger: .resynchronization,
                preferredSnapshot: systemSnapshot,
                allowResynchronization: false
            )
        }
    }

    private func buildSnapshotCandidates(systemSnapshot: BatterySnapshot?) -> [BatterySnapshot] {
        var snapshots: [BatterySnapshot] = []

        if let currentBattery = currentUpdate.appState.battery {
            snapshots.append(
                BatterySnapshot(
                    chargePercent: currentBattery.chargePercent,
                    isPowerConnected: currentBattery.isPowerConnected,
                    isCharging: currentBattery.isCharging,
                    isBatteryPresent: currentBattery.isBatteryPresent,
                    observedAt: currentBattery.observedAt,
                    source: .cached
                )
            )
        }

        if let systemSnapshot {
            snapshots.append(systemSnapshot)
        }

        return snapshots
    }

    private func needsResynchronization(update: AppRuntimeUpdate) -> Bool {
        switch update.chargingCommand {
        case .enableCharging:
            if update.appState.controllerStatus.isChargingEnabled == false {
                return true
            }
        case .disableCharging:
            if update.appState.controllerStatus.isChargingEnabled == true {
                return true
            }
        case .noChange:
            break
        }

        if let controllerOverride = update.appState.controllerStatus.temporaryOverrideUntil,
           controllerOverride != update.appState.policy.temporaryOverrideUntil {
            return true
        }

        return false
    }

    private func broadcast(_ update: AppRuntimeUpdate) {
        continuations.values.forEach { $0.yield(update) }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func transitionSummary(for update: AppRuntimeUpdate) -> String? {
        switch update.appState.chargeState {
        case .errorReadOnly:
            return update.appState.controllerStatus.lastErrorDescription
                ?? "helper 실패로 읽기 전용 상태를 유지합니다."
        case .suspended:
            switch update.appState.controllerStatus.mode {
            case .monitoringOnly:
                return "관측 전용 환경이므로 충전 제어를 중단합니다."
            case .readOnly:
                return "읽기 전용 환경이므로 충전 제어를 중단합니다."
            case .fullControl:
                return update.transitionReason == .controlSuspended ? "정책에 따라 제어를 중단합니다." : nil
            }
        default:
            return nil
        }
    }

    private func restorePersistedPolicyIfNeeded() async {
        do {
            guard let persistedPolicy = try policyStore.load() else { return }
            currentUpdate.appState.policy = persistedPolicy

            await eventLogger.record(
                level: .notice,
                category: .runtime,
                message: "저장된 충전 정책을 복구했습니다.",
                details: [
                    "upperLimit": String(persistedPolicy.upperLimit),
                    "rechargeThreshold": String(persistedPolicy.rechargeThreshold),
                    "overrideUntil": persistedPolicy.temporaryOverrideUntil?.ISO8601Format() ?? "nil",
                    "isControlEnabled": String(persistedPolicy.isControlEnabled)
                ],
                userFacingSummary: "저장된 충전 정책을 불러왔습니다."
            )
        } catch {
            await eventLogger.record(
                level: .error,
                category: .runtime,
                message: "저장된 충전 정책을 읽지 못했습니다.",
                details: [
                    "error": error.localizedDescription
                ],
                userFacingSummary: "저장된 정책을 읽지 못해 기본 정책으로 시작합니다."
            )
        }
    }

    private func persistPolicy(
        _ policy: ChargePolicy,
        reason: String,
        userFacingSummary: String
    ) async {
        do {
            try policyStore.save(policy)
        } catch {
            await eventLogger.record(
                level: .error,
                category: .runtime,
                message: "충전 정책을 저장하지 못했습니다.",
                details: [
                    "reason": reason,
                    "error": error.localizedDescription
                ],
                userFacingSummary: userFacingSummary
            )
        }
    }
}
