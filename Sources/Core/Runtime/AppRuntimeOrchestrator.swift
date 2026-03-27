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
    private let capabilityChecker: any CapabilityChecking
    private let capabilityProber: (any HelperCapabilityProbing)?
    private let policyEngine: PolicyEngine
    private let dateProvider: any DateProviding
    private let eventLogger: any EventLogging

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
        policyEngine: PolicyEngine = PolicyEngine(),
        dateProvider: any DateProviding = SystemDateProvider(),
        eventLogger: any EventLogging = EventLogger()
    ) {
        self.batteryMonitor = batteryMonitor
        self.controller = controller
        self.capabilityChecker = capabilityChecker
        self.capabilityProber = capabilityProber
        self.policyEngine = policyEngine
        self.dateProvider = dateProvider
        self.eventLogger = eventLogger

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
        let now = dateProvider.now
        let systemSnapshot = preferredSnapshot ?? latestSystemSnapshot ?? (try? batteryMonitor.currentSnapshot(now: now))
        latestSystemSnapshot = systemSnapshot ?? latestSystemSnapshot

        await performSelfTestIfNeeded(trigger: trigger)
        let controllerStatus = await controller.getControllerStatus()
        let capabilityReport = await resolveCapabilityReport(
            snapshot: systemSnapshot,
            controllerStatus: controllerStatus,
            trigger: trigger
        )
        let evaluation = policyEngine.evaluate(
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

    private func resolveCapabilityReport(
        snapshot: BatterySnapshot?,
        controllerStatus: ControllerStatus,
        trigger: AppRuntimeTrigger
    ) async -> CapabilityReport {
        let shouldProbeHelper: Bool
        switch trigger {
        case .appLaunch, .manualRefresh, .resynchronization:
            shouldProbeHelper = true
        case .policyChanged:
            shouldProbeHelper = false
        case .batteryEvent(let batteryTrigger):
            shouldProbeHelper = batteryTrigger == .didWake || batteryTrigger == .powerSourceChanged
        }

        let baseReport: CapabilityReport
        if shouldProbeHelper, let capabilityProber {
            do {
                let probe = try await capabilityProber.capabilityProbe()
                await eventLogger.record(
                    level: .notice,
                    category: .capabilityProbe,
                    message: "Capability probe 결과를 저장했습니다.",
                    details: [
                        "recommendedMode": probe.report.recommendedControllerMode.rawValue,
                        "helperMode": probe.status.mode.rawValue
                    ],
                    userFacingSummary: nil
                )
                baseReport = probe.report
            } catch {
                await eventLogger.record(
                    level: .error,
                    category: .capabilityProbe,
                    message: "Capability probe가 실패했습니다: \(error.localizedDescription)",
                    details: ["trigger": trigger.debugName],
                    userFacingSummary: "capability probe 실패로 read-only fallback을 적용합니다."
                )
                baseReport = capabilityChecker.evaluate(snapshot: snapshot)
            }
        } else {
            baseReport = capabilityChecker.evaluate(snapshot: snapshot)
        }

        if controllerStatus.helperConnection != .connected || controllerStatus.lastErrorDescription != nil {
            await eventLogger.record(
                level: .warning,
                category: .helperCommunication,
                message: controllerStatus.lastErrorDescription ?? "Helper 연결이 정상 상태가 아닙니다.",
                details: [
                    "mode": controllerStatus.mode.rawValue,
                    "helperConnection": controllerStatus.helperConnection.rawValue
                ],
                userFacingSummary: "helper 연결 문제로 read-only 또는 monitoring-only 상태를 유지합니다."
            )
            return baseReport.replacingStatus(
                for: .chargeControl,
                support: .readOnlyFallback,
                reason: controllerStatus.lastErrorDescription ?? "helper 연결 실패로 읽기 전용 상태를 유지합니다."
            )
        }

        return baseReport
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

    private func performSelfTestIfNeeded(trigger: AppRuntimeTrigger) async {
        switch trigger {
        case .appLaunch, .manualRefresh:
            let result = await controller.selfTest()
            await eventLogger.record(
                level: result.outcome == .failed ? .error : (result.outcome == .degraded ? .warning : .notice),
                category: .selfTest,
                message: result.message,
                details: [
                    "trigger": trigger.debugName,
                    "outcome": result.outcome.rawValue
                ],
                userFacingSummary: result.outcome == .failed ? "self-test 실패로 read-only fallback을 유지합니다." : nil
            )
        case .policyChanged, .batteryEvent, .resynchronization:
            break
        }
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
}

private extension AppRuntimeTrigger {
    var debugName: String {
        switch self {
        case .appLaunch:
            return "appLaunch"
        case .manualRefresh:
            return "manualRefresh"
        case .policyChanged:
            return "policyChanged"
        case .batteryEvent(let trigger):
            return "batteryEvent:\(trigger.rawValue)"
        case .resynchronization:
            return "resynchronization"
        }
    }
}
