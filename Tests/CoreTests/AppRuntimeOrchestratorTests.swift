import Core
import Foundation
import Shared
import Testing

@Test
func orchestratorBroadcastsInitialLaunchStateFromBatteryAndHelper() async {
    let monitor = MockRuntimeBatteryMonitor(
        currentSnapshotValue: BatterySnapshot(
            chargePercent: 82,
            isPowerConnected: true,
            isCharging: false,
            observedAt: Date(timeIntervalSince1970: 100),
            source: .system
        )
    )
    let controller = SequencedChargeController(
        statuses: [
            ControllerStatus(
                mode: .fullControl,
                helperConnection: .connected,
                isChargingEnabled: false,
                checkedAt: Date(timeIntervalSince1970: 100)
            )
        ]
    )
    let orchestrator = AppRuntimeOrchestrator(
        batteryMonitor: monitor,
        controller: controller,
        capabilityChecker: CapabilityChecker(
            environment: MockRuntimeEnvironmentProvider(
                operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
                isAppleSilicon: true
            )
        ),
        dateProvider: FixedRuntimeDateProvider(now: Date(timeIntervalSince1970: 100))
    )

    let stream = await orchestrator.makeUpdateStream()
    let task = Task {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next()
    }

    await orchestrator.start()
    let update = await task.value

    #expect(update?.lastTrigger == .appLaunch)
    #expect(update?.appState.chargeState == .holdingAtLimit)
    #expect(update?.appState.battery?.source == .system)
}

@Test
func orchestratorResynchronizesWhenControllerStatusDoesNotMatchDesiredCommand() async {
    let monitor = MockRuntimeBatteryMonitor(
        currentSnapshotValue: BatterySnapshot(
            chargePercent: 80,
            isPowerConnected: true,
            isCharging: false,
            observedAt: Date(timeIntervalSince1970: 200),
            source: .system
        )
    )
    let controller = SequencedChargeController(
        statuses: [
            ControllerStatus(
                mode: .fullControl,
                helperConnection: .connected,
                isChargingEnabled: true,
                checkedAt: Date(timeIntervalSince1970: 200)
            ),
            ControllerStatus(
                mode: .fullControl,
                helperConnection: .connected,
                isChargingEnabled: false,
                checkedAt: Date(timeIntervalSince1970: 201)
            )
        ]
    )
    let orchestrator = AppRuntimeOrchestrator(
        batteryMonitor: monitor,
        controller: controller,
        capabilityChecker: CapabilityChecker(
            environment: MockRuntimeEnvironmentProvider(
                operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
                isAppleSilicon: true
            )
        ),
        dateProvider: FixedRuntimeDateProvider(now: Date(timeIntervalSince1970: 200))
    )

    await orchestrator.start()
    let requestCount = await controller.statusRequestCount()

    #expect(requestCount == 2)
}

@Test
func orchestratorFallsBackToReadOnlyWhenHelperIsDisconnected() async {
    let monitor = MockRuntimeBatteryMonitor(
        currentSnapshotValue: BatterySnapshot(
            chargePercent: 79,
            isPowerConnected: true,
            isCharging: true,
            observedAt: Date(timeIntervalSince1970: 300),
            source: .system
        )
    )
    let controller = SequencedChargeController(
        statuses: [
            ControllerStatus(
                mode: .readOnly,
                helperConnection: .disconnected,
                isChargingEnabled: nil,
                lastErrorDescription: "XPC 연결 실패",
                checkedAt: Date(timeIntervalSince1970: 300)
            )
        ]
    )
    let orchestrator = AppRuntimeOrchestrator(
        batteryMonitor: monitor,
        controller: controller,
        capabilityChecker: CapabilityChecker(
            environment: MockRuntimeEnvironmentProvider(
                operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
                isAppleSilicon: true
            )
        ),
        dateProvider: FixedRuntimeDateProvider(now: Date(timeIntervalSince1970: 300))
    )

    let stream = await orchestrator.makeUpdateStream()
    let task = Task {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next()
    }
    await orchestrator.start()
    let update = await task.value

    #expect(update?.appState.chargeState == .errorReadOnly)
    #expect(update?.capabilityReport.status(for: CapabilityKey.chargeControl)?.support == .readOnlyFallback)
}

@Test
func orchestratorReevaluatesOnWakeEvent() async {
    let monitor = MockRuntimeBatteryMonitor(
        currentSnapshotValue: BatterySnapshot(
            chargePercent: 76,
            isPowerConnected: false,
            isCharging: false,
            observedAt: Date(timeIntervalSince1970: 400),
            source: .system
        )
    )
    let controller = SequencedChargeController(
        statuses: [
            ControllerStatus(mode: .fullControl, helperConnection: .connected, isChargingEnabled: false),
            ControllerStatus(mode: .fullControl, helperConnection: .connected, isChargingEnabled: false)
        ]
    )
    let orchestrator = AppRuntimeOrchestrator(
        batteryMonitor: monitor,
        controller: controller,
        capabilityChecker: CapabilityChecker(
            environment: MockRuntimeEnvironmentProvider(
                operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
                isAppleSilicon: true
            )
        ),
        dateProvider: SequenceRuntimeDateProvider(
            dates: [
                Date(timeIntervalSince1970: 400),
                Date(timeIntervalSince1970: 450),
                Date(timeIntervalSince1970: 451)
            ]
        )
    )

    let stream = await orchestrator.makeUpdateStream()
    let task = Task {
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        return await iterator.next()
    }

    await orchestrator.start()
    monitor.emit(
        BatteryMonitorUpdate(
            trigger: .didWake,
            snapshot: BatterySnapshot(
                chargePercent: 74,
                isPowerConnected: true,
                isCharging: false,
                observedAt: Date(timeIntervalSince1970: 450),
                source: .system
            ),
            observedAt: Date(timeIntervalSince1970: 450)
        )
    )

    let update = await task.value
    #expect(update?.lastTrigger == .batteryEvent(.didWake))
    #expect(update?.appState.chargeState == .charging)
}

@Test
func orchestratorReevaluatesWhenPolicyChanges() async {
    let monitor = MockRuntimeBatteryMonitor(
        currentSnapshotValue: BatterySnapshot(
            chargePercent: 78,
            isPowerConnected: true,
            isCharging: false,
            observedAt: Date(timeIntervalSince1970: 500),
            source: .system
        )
    )
    let controller = SequencedChargeController(
        statuses: [
            ControllerStatus(mode: .fullControl, helperConnection: .connected, isChargingEnabled: false),
            ControllerStatus(mode: .fullControl, helperConnection: .connected, isChargingEnabled: false)
        ]
    )
    let orchestrator = AppRuntimeOrchestrator(
        initialPolicy: ChargePolicy(upperLimit: 80, rechargeThreshold: 75),
        batteryMonitor: monitor,
        controller: controller,
        capabilityChecker: CapabilityChecker(
            environment: MockRuntimeEnvironmentProvider(
                operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
                isAppleSilicon: true
            )
        ),
        dateProvider: SequenceRuntimeDateProvider(
            dates: [
                Date(timeIntervalSince1970: 500),
                Date(timeIntervalSince1970: 550)
            ]
        )
    )

    let stream = await orchestrator.makeUpdateStream()
    let task = Task {
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        return await iterator.next()
    }

    await orchestrator.start()
    await orchestrator.setPolicy(
        ChargePolicy(
            upperLimit: 76,
            rechargeThreshold: 72
        )
    )
    let update = await task.value

    #expect(update?.lastTrigger == .policyChanged)
    #expect(update?.appState.chargeState == .holdingAtLimit)
    #expect(update?.appState.policy.upperLimit == 76)
}

@Test
func orchestratorReevaluatesOnPowerSourceChange() async {
    let monitor = MockRuntimeBatteryMonitor(
        currentSnapshotValue: BatterySnapshot(
            chargePercent: 79,
            isPowerConnected: false,
            isCharging: false,
            observedAt: Date(timeIntervalSince1970: 600),
            source: .system
        )
    )
    let controller = SequencedChargeController(
        statuses: [
            ControllerStatus(mode: .fullControl, helperConnection: .connected, isChargingEnabled: false),
            ControllerStatus(mode: .fullControl, helperConnection: .connected, isChargingEnabled: false)
        ]
    )
    let orchestrator = AppRuntimeOrchestrator(
        batteryMonitor: monitor,
        controller: controller,
        capabilityChecker: CapabilityChecker(
            environment: MockRuntimeEnvironmentProvider(
                operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
                isAppleSilicon: true
            )
        ),
        dateProvider: SequenceRuntimeDateProvider(
            dates: [
                Date(timeIntervalSince1970: 600),
                Date(timeIntervalSince1970: 610),
                Date(timeIntervalSince1970: 611)
            ]
        )
    )

    let stream = await orchestrator.makeUpdateStream()
    let task = Task {
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        return await iterator.next()
    }

    await orchestrator.start()
    monitor.emit(
        BatteryMonitorUpdate(
            trigger: .powerSourceChanged,
            snapshot: BatterySnapshot(
                chargePercent: 74,
                isPowerConnected: true,
                isCharging: false,
                observedAt: Date(timeIntervalSince1970: 610),
                source: .system
            ),
            observedAt: Date(timeIntervalSince1970: 610)
        )
    )

    let update = await task.value
    #expect(update?.lastTrigger == .batteryEvent(.powerSourceChanged))
    #expect(update?.appState.battery?.isPowerConnected == true)
    #expect(update?.appState.chargeState == .charging)
}

@Test
func orchestratorTreatsReadOnlyCapabilityModeAsSuspendedNotError() async {
    let monitor = MockRuntimeBatteryMonitor(
        currentSnapshotValue: BatterySnapshot(
            chargePercent: 77,
            isPowerConnected: true,
            isCharging: false,
            observedAt: Date(timeIntervalSince1970: 700),
            source: .system
        )
    )
    let controller = SequencedChargeController(
        statuses: [
            ControllerStatus(
                mode: .readOnly,
                helperConnection: .connected,
                isChargingEnabled: nil,
                lastErrorDescription: nil,
                checkedAt: Date(timeIntervalSince1970: 700)
            )
        ]
    )
    let orchestrator = AppRuntimeOrchestrator(
        batteryMonitor: monitor,
        controller: controller,
        capabilityChecker: CapabilityChecker(
            environment: MockRuntimeEnvironmentProvider(
                operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
                isAppleSilicon: true
            )
        ),
        dateProvider: FixedRuntimeDateProvider(now: Date(timeIntervalSince1970: 700))
    )

    let stream = await orchestrator.makeUpdateStream()
    let task = Task {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next()
    }

    await orchestrator.start()
    let update = await task.value

    #expect(update?.appState.chargeState == .suspended)
    #expect(update?.transitionReason == .controlSuspended)
}

@Test
func orchestratorStoresCapabilityAndSelfTestDiagnostics() async {
    let monitor = MockRuntimeBatteryMonitor(
        currentSnapshotValue: BatterySnapshot(
            chargePercent: 77,
            isPowerConnected: true,
            isCharging: false,
            observedAt: Date(timeIntervalSince1970: 800),
            source: .system
        )
    )
    let controller = SequencedChargeController(
        statuses: [
            ControllerStatus(
                mode: .fullControl,
                helperConnection: .connected,
                isChargingEnabled: false,
                checkedAt: Date(timeIntervalSince1970: 800)
            )
        ],
        selfTestResult: ControllerSelfTestResult(
            outcome: .degraded,
            message: "Helper self-test degraded",
            checkedAt: Date(timeIntervalSince1970: 800)
        )
    )
    let logger = EventLogger()
    let orchestrator = AppRuntimeOrchestrator(
        batteryMonitor: monitor,
        controller: controller,
        capabilityChecker: CapabilityChecker(
            environment: MockRuntimeEnvironmentProvider(
                operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
                isAppleSilicon: true
            )
        ),
        capabilityProber: MockHelperCapabilityProber(),
        dateProvider: FixedRuntimeDateProvider(now: Date(timeIntervalSince1970: 800)),
        eventLogger: logger
    )

    await orchestrator.start()
    let summary = await orchestrator.diagnosticsSummary()
    let events = await orchestrator.recentDiagnosticEvents(limit: nil)

    #expect(summary.lastCapabilityProbeMessage == "Capability probe 결과를 저장했습니다.")
    #expect(summary.lastSelfTestMessage == "Helper self-test degraded")
    #expect(events.contains { $0.category == .capabilityProbe })
    #expect(events.contains { $0.category == .selfTest })
}

private actor SequencedChargeController: ChargeController {
    private var statuses: [ControllerStatus]
    private let selfTestResult: ControllerSelfTestResult
    private var requests = 0

    init(
        statuses: [ControllerStatus],
        selfTestResult: ControllerSelfTestResult = ControllerSelfTestResult(
            outcome: .degraded,
            message: "stub"
        )
    ) {
        self.statuses = statuses
        self.selfTestResult = selfTestResult
    }

    func setChargingEnabled(_ enabled: Bool) async throws {}

    func setTemporaryOverride(until: Date?) async throws {}

    func getControllerStatus() async -> ControllerStatus {
        requests += 1
        if statuses.count > 1 {
            return statuses.removeFirst()
        }
        return statuses.first ?? ControllerStatus(mode: .readOnly, helperConnection: .unavailable)
    }

    func selfTest() async -> ControllerSelfTestResult {
        selfTestResult
    }

    func statusRequestCount() -> Int {
        requests
    }
}

private struct MockHelperCapabilityProber: HelperCapabilityProbing {
    func capabilityProbe() async throws -> HelperCapabilityProbeSummary {
        HelperCapabilityProbeSummary(
            report: CapabilityReport(
                statuses: [
                    CapabilityStatus(key: .appleSilicon, support: .supported, reason: "Apple Silicon 환경입니다."),
                    CapabilityStatus(key: .chargeControl, support: .experimental, reason: "제어 경로는 아직 stub입니다.")
                ],
                recommendedControllerMode: .readOnly
            ),
            status: ControllerStatus(
                mode: .readOnly,
                helperConnection: .connected,
                isChargingEnabled: nil,
                temporaryOverrideUntil: nil,
                lastErrorDescription: nil
            )
        )
    }
}

private final class MockRuntimeBatteryMonitor: @unchecked Sendable, BatteryMonitoring {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<BatteryMonitorUpdate, Error>.Continuation?
    private var currentSnapshotValue: BatterySnapshot?

    init(currentSnapshotValue: BatterySnapshot?) {
        self.currentSnapshotValue = currentSnapshotValue
    }

    func currentSnapshot(now: Date) throws -> BatterySnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return currentSnapshotValue
    }

    func refresh(trigger: BatteryMonitorTrigger, now: Date) throws -> BatteryMonitorUpdate {
        BatteryMonitorUpdate(trigger: trigger, snapshot: try currentSnapshot(now: now), observedAt: now)
    }

    func makeUpdateStream(emitInitialSnapshot: Bool) -> AsyncThrowingStream<BatteryMonitorUpdate, Error> {
        AsyncThrowingStream { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }
    }

    func emit(_ update: BatteryMonitorUpdate) {
        lock.lock()
        currentSnapshotValue = update.snapshot
        let continuation = self.continuation
        lock.unlock()
        continuation?.yield(update)
    }
}

private struct MockRuntimeEnvironmentProvider: SystemEnvironmentProviding {
    let operatingSystemVersion: OperatingSystemVersion
    let isAppleSiliconValue: Bool

    init(operatingSystemVersion: OperatingSystemVersion, isAppleSilicon: Bool) {
        self.operatingSystemVersion = operatingSystemVersion
        self.isAppleSiliconValue = isAppleSilicon
    }

    func isAppleSilicon() -> Bool {
        isAppleSiliconValue
    }
}

private struct FixedRuntimeDateProvider: DateProviding {
    let now: Date
}

private final class SequenceRuntimeDateProvider: @unchecked Sendable, DateProviding {
    private let lock = NSLock()
    private var dates: [Date]

    init(dates: [Date]) {
        self.dates = dates
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return dates.isEmpty ? .distantPast : dates.removeFirst()
    }
}
