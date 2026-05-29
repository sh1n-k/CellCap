import Core
import Foundation
import Shared
import SystemSupport
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
        ],
        selfTestResult: ControllerSelfTestResult(
            outcome: .passed,
            message: "ok",
            checkedAt: Date(timeIntervalSince1970: 100)
        )
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
        capabilityProber: MockHelperCapabilityProber(
            summary: fullControlProbeSummary(
                checkedAt: Date(timeIntervalSince1970: 100),
                isChargingEnabled: false
            )
        ),
        helperInstallChecker: MockHelperInstallChecker(
            status: bootstrappedHelperInstallStatus(at: Date(timeIntervalSince1970: 100))
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
func orchestratorPrefersHelperInstallStatusBeforeCapabilityProbe() async {
    let monitor = MockRuntimeBatteryMonitor(
        currentSnapshotValue: BatterySnapshot(
            chargePercent: 82,
            isPowerConnected: true,
            isCharging: false,
            observedAt: Date(timeIntervalSince1970: 110),
            source: .system
        )
    )
    let controller = SequencedChargeController(
        statuses: [
            ControllerStatus(
                mode: .readOnly,
                helperConnection: .unavailable,
                isChargingEnabled: nil,
                checkedAt: Date(timeIntervalSince1970: 110)
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
        helperInstallChecker: MockHelperInstallChecker(
            status: HelperInstallStatus(
                state: .notInstalled,
                serviceName: CellCapHelperXPC.serviceName,
                helperPath: CellCapHelperXPC.installedBinaryPath,
                plistPath: CellCapHelperXPC.launchDaemonPlistPath,
                helperVersion: nil,
                expectedVersion: CellCapHelperXPC.contractVersion,
                reason: "설치 누락: helper binary, launchd plist",
                checkedAt: Date(timeIntervalSince1970: 110)
            )
        ),
        dateProvider: FixedRuntimeDateProvider(now: Date(timeIntervalSince1970: 110))
    )

    let stream = await orchestrator.makeUpdateStream()
    let task = Task {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next()
    }

    await orchestrator.start()
    let update = await task.value

    #expect(update?.capabilityReport.helperInstallStatus?.state == .notInstalled)
    #expect(update?.capabilityReport.status(for: .helperInstallation)?.support == .readOnlyFallback)
    let selfTestCount = await controller.selfTestRequestCount()
    #expect(selfTestCount == 0)
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
        ],
        selfTestResult: ControllerSelfTestResult(
            outcome: .passed,
            message: "ok",
            checkedAt: Date(timeIntervalSince1970: 200)
        )
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
        capabilityProber: MockHelperCapabilityProber(
            summary: fullControlProbeSummary(
                checkedAt: Date(timeIntervalSince1970: 200),
                isChargingEnabled: true
            )
        ),
        helperInstallChecker: MockHelperInstallChecker(
            status: bootstrappedHelperInstallStatus(at: Date(timeIntervalSince1970: 200))
        ),
        dateProvider: FixedRuntimeDateProvider(now: Date(timeIntervalSince1970: 200))
    )

    await orchestrator.start()
    let requestCount = await controller.statusRequestCount()
    let commands = await controller.commands()

    #expect(requestCount == 2)
    #expect(commands == [.setChargingEnabled(false)])
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
        capabilityProber: MockHelperCapabilityProber(
            summary: fullControlProbeSummary(
                checkedAt: Date(timeIntervalSince1970: 400),
                isChargingEnabled: false
            )
        ),
        helperInstallChecker: MockHelperInstallChecker(
            status: bootstrappedHelperInstallStatus(at: Date(timeIntervalSince1970: 400))
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
    await monitor.waitUntilStreamCount(atLeast: 1)
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
    #expect(update?.diagnosticsSummary.currentChargeState == .charging)
}

@Test
func orchestratorResubscribesAfterBatteryMonitorFailure() async {
    let monitor = MockRuntimeBatteryMonitor(
        currentSnapshotValue: BatterySnapshot(
            chargePercent: 76,
            isPowerConnected: false,
            isCharging: false,
            observedAt: Date(timeIntervalSince1970: 405),
            source: .system
        )
    )
    let controller = SequencedChargeController(
        statuses: [
            ControllerStatus(mode: .fullControl, helperConnection: .connected, isChargingEnabled: false),
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
        capabilityProber: MockHelperCapabilityProber(
            summary: fullControlProbeSummary(
                checkedAt: Date(timeIntervalSince1970: 405),
                isChargingEnabled: false
            )
        ),
        helperInstallChecker: MockHelperInstallChecker(
            status: bootstrappedHelperInstallStatus(at: Date(timeIntervalSince1970: 405))
        ),
        dateProvider: SequenceRuntimeDateProvider(
            dates: [
                Date(timeIntervalSince1970: 405),
                Date(timeIntervalSince1970: 406),
                Date(timeIntervalSince1970: 407),
                Date(timeIntervalSince1970: 408)
            ]
        )
    )

    await orchestrator.start()
    await monitor.waitUntilStreamCount(atLeast: 1)
    monitor.fail(RuntimeMonitorFailure())
    await monitor.waitUntilStreamCount(atLeast: 2)
    let stream = await orchestrator.makeUpdateStream()
    let task = Task {
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        return await iterator.next()
    }
    monitor.emit(
        BatteryMonitorUpdate(
            trigger: .didWake,
            snapshot: BatterySnapshot(
                chargePercent: 70,
                isPowerConnected: true,
                isCharging: false,
                observedAt: Date(timeIntervalSince1970: 408),
                source: .system
            ),
            observedAt: Date(timeIntervalSince1970: 408)
        )
    )

    let update = await task.value
    #expect(update?.lastTrigger == .batteryEvent(.didWake))
    #expect(update?.appState.battery?.chargePercent == 70)
}

@Test
func orchestratorPreservesQueuedBatteryEventsAcrossMonitorRecovery() async {
    let now = Date(timeIntervalSince1970: 430)
    let monitor = MockRuntimeBatteryMonitor(
        currentSnapshotValue: BatterySnapshot(
            chargePercent: 68,
            isPowerConnected: true,
            isCharging: false,
            observedAt: now,
            source: .system
        )
    )
    let controller = SequencedChargeController(
        statuses: [
            ControllerStatus(mode: .fullControl, helperConnection: .connected, isChargingEnabled: false),
            ControllerStatus(mode: .fullControl, helperConnection: .connected, isChargingEnabled: false),
            ControllerStatus(mode: .fullControl, helperConnection: .connected, isChargingEnabled: false)
        ],
        selfTestResult: ControllerSelfTestResult(
            outcome: .passed,
            message: "ok",
            checkedAt: now
        )
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
        capabilityProber: MockHelperCapabilityProber(
            summary: fullControlProbeSummary(
                checkedAt: now,
                isChargingEnabled: false
            )
        ),
        helperInstallChecker: MockHelperInstallChecker(
            status: bootstrappedHelperInstallStatus(at: now)
        ),
        dateProvider: FixedRuntimeDateProvider(now: now)
    )

    await orchestrator.start()
    await monitor.waitUntilStreamCount(atLeast: 1)

    let stream = await orchestrator.makeUpdateStream()
    let task = Task {
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        return [
            await iterator.next(),
            await iterator.next(),
            await iterator.next()
        ]
    }

    monitor.fail(RuntimeMonitorFailure())
    monitor.emitOnNextStream(
        BatteryMonitorUpdate(
            trigger: .didWake,
            snapshot: BatterySnapshot(
                chargePercent: 70,
                isPowerConnected: true,
                isCharging: false,
                observedAt: now,
                source: .system
            ),
            observedAt: now
        )
    )
    monitor.emitOnNextStream(
        BatteryMonitorUpdate(
            trigger: .powerSourceChanged,
            snapshot: BatterySnapshot(
                chargePercent: 71,
                isPowerConnected: false,
                isCharging: false,
                observedAt: now.addingTimeInterval(1),
                source: .system
            ),
            observedAt: now.addingTimeInterval(1)
        )
    )

    let updates = await task.value.compactMap { $0 }

    #expect(updates.count == 3)
    #expect(updates[0].lastTrigger == .resynchronization)
    #expect(updates[1].lastTrigger == .batteryEvent(.didWake))
    #expect(updates[2].lastTrigger == .batteryEvent(.powerSourceChanged))
    #expect(updates[1].appState.battery?.chargePercent == 70)
    #expect(updates[2].appState.battery?.chargePercent == 71)
}

@Test
func orchestratorKeepsPushAndPullDiagnosticsSummaryAlignedDuringResynchronization() async {
    let now = Date(timeIntervalSince1970: 1_700)
    let monitor = MockRuntimeBatteryMonitor(
        currentSnapshotValue: BatterySnapshot(
            chargePercent: 84,
            isPowerConnected: true,
            isCharging: true,
            observedAt: now,
            source: .system
        )
    )
    let controller = BlockingResynchronizingChargeController(now: now)
    let store = MockChargePolicyStore(
        loadedPolicy: ChargePolicy(
            upperLimit: 80,
            rechargeThreshold: 75,
            temporaryOverrideUntil: Date(timeIntervalSince1970: 1_600)
        ),
        saveError: .failedToSave
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
        capabilityProber: MockHelperCapabilityProber(
            summary: fullControlProbeSummary(
                checkedAt: now,
                isChargingEnabled: true
            )
        ),
        helperInstallChecker: MockHelperInstallChecker(
            status: bootstrappedHelperInstallStatus(at: now)
        ),
        policyStore: store,
        dateProvider: FixedRuntimeDateProvider(now: now)
    )

    let stream = await orchestrator.makeUpdateStream()
    let task = Task {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next()
    }

    let startTask = Task {
        await orchestrator.start()
    }
    let update = await task.value
    let summary = await orchestrator.diagnosticsSummary()
    let events = await orchestrator.recentDiagnosticEvents(limit: nil)

    #expect(update?.diagnosticsSummary == summary)
    #expect(events.contains { $0.message == "충전 정책을 저장하지 못했습니다." })
    #expect(events.contains { $0.message == "상태 불일치로 재동기화를 수행합니다." })

    await controller.resumeBlockedStatusRequest()
    await startTask.value
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
        capabilityProber: MockHelperCapabilityProber(
            summary: fullControlProbeSummary(
                checkedAt: Date(timeIntervalSince1970: 500),
                isChargingEnabled: false
            )
        ),
        helperInstallChecker: MockHelperInstallChecker(
            status: bootstrappedHelperInstallStatus(at: Date(timeIntervalSince1970: 500))
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
    let commands = await controller.commands()

    #expect(update?.lastTrigger == .policyChanged)
    #expect(update?.appState.chargeState == .holdingAtLimit)
    #expect(update?.appState.policy.upperLimit == 76)
    #expect(commands.isEmpty)
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
        capabilityProber: MockHelperCapabilityProber(
            summary: fullControlProbeSummary(
                checkedAt: Date(timeIntervalSince1970: 600),
                isChargingEnabled: false
            )
        ),
        helperInstallChecker: MockHelperInstallChecker(
            status: bootstrappedHelperInstallStatus(at: Date(timeIntervalSince1970: 600))
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
    await monitor.waitUntilStreamCount(atLeast: 1)
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
func orchestratorCoalescesPowerSourceChangeWhenSnapshotIsUnchanged() async {
    let monitor = MockRuntimeBatteryMonitor(
        currentSnapshotValue: BatterySnapshot(
            chargePercent: 80,
            isPowerConnected: true,
            isCharging: false,
            observedAt: Date(timeIntervalSince1970: 600),
            source: .system
        )
    )
    let controller = SequencedChargeController(
        statuses: [
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
        capabilityProber: MockHelperCapabilityProber(
            summary: fullControlProbeSummary(
                checkedAt: Date(timeIntervalSince1970: 600),
                isChargingEnabled: false
            )
        ),
        helperInstallChecker: MockHelperInstallChecker(
            status: bootstrappedHelperInstallStatus(at: Date(timeIntervalSince1970: 600))
        ),
        dateProvider: FixedRuntimeDateProvider(now: Date(timeIntervalSince1970: 600))
    )

    let stream = await orchestrator.makeUpdateStream()
    let task = Task {
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        return await iterator.next()
    }

    await orchestrator.start()
    await monitor.waitUntilStreamCount(atLeast: 1)

    // 동일한 스냅샷(충전%/전원/충전여부/배터리존재 모두 같음)의 powerSourceChanged는
    // 코얼레싱되어 broadcast를 만들지 않는다. 이어지는 변경 이벤트만 통과해야 한다.
    monitor.emit(
        BatteryMonitorUpdate(
            trigger: .powerSourceChanged,
            snapshot: BatterySnapshot(
                chargePercent: 80,
                isPowerConnected: true,
                isCharging: false,
                observedAt: Date(timeIntervalSince1970: 601),
                source: .system
            ),
            observedAt: Date(timeIntervalSince1970: 601)
        )
    )
    monitor.emit(
        BatteryMonitorUpdate(
            trigger: .powerSourceChanged,
            snapshot: BatterySnapshot(
                chargePercent: 74,
                isPowerConnected: true,
                isCharging: false,
                observedAt: Date(timeIntervalSince1970: 602),
                source: .system
            ),
            observedAt: Date(timeIntervalSince1970: 602)
        )
    )

    let update = await task.value
    // 코얼레싱이 동작하면 첫 broadcast는 동일 스냅샷(80)을 건너뛴 변경 이벤트(74)다.
    #expect(update?.appState.battery?.chargePercent == 74)
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
        helperInstallChecker: MockHelperInstallChecker(
            status: HelperInstallStatus(
                state: .bootstrapped,
                serviceName: CellCapHelperXPC.serviceName,
                helperPath: CellCapHelperXPC.installedBinaryPath,
                plistPath: CellCapHelperXPC.launchDaemonPlistPath,
                helperVersion: CellCapHelperXPC.contractVersion,
                expectedVersion: CellCapHelperXPC.contractVersion,
                reason: "launchd에 helper가 등록되어 있습니다.",
                checkedAt: Date(timeIntervalSince1970: 800)
            )
        ),
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

@Test
func orchestratorDoesNotApplyCommandsWhenSelfTestFails() async {
    let monitor = MockRuntimeBatteryMonitor(
        currentSnapshotValue: BatterySnapshot(
            chargePercent: 82,
            isPowerConnected: true,
            isCharging: true,
            observedAt: Date(timeIntervalSince1970: 900),
            source: .system
        )
    )
    let controller = SequencedChargeController(
        statuses: [
            ControllerStatus(
                mode: .fullControl,
                helperConnection: .connected,
                isChargingEnabled: true,
                checkedAt: Date(timeIntervalSince1970: 900)
            )
        ],
        selfTestResult: ControllerSelfTestResult(
            outcome: .failed,
            message: "SMC self-test failed",
            checkedAt: Date(timeIntervalSince1970: 900)
        )
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
        capabilityProber: MockHelperCapabilityProber(
            summary: HelperCapabilityProbeSummary(
                report: fullControlCapabilityReport(reason: "SMC helper가 준비되었습니다."),
                status: ControllerStatus(
                    mode: .fullControl,
                    helperConnection: .connected,
                    isChargingEnabled: true,
                    checkedAt: Date(timeIntervalSince1970: 900)
                )
            )
        ),
        helperInstallChecker: MockHelperInstallChecker(
            status: HelperInstallStatus(
                state: .bootstrapped,
                serviceName: CellCapHelperXPC.serviceName,
                helperPath: CellCapHelperXPC.installedBinaryPath,
                plistPath: CellCapHelperXPC.launchDaemonPlistPath,
                helperVersion: CellCapHelperXPC.contractVersion,
                expectedVersion: CellCapHelperXPC.contractVersion,
                reason: "launchd에 helper가 등록되어 있습니다.",
                checkedAt: Date(timeIntervalSince1970: 900)
            )
        ),
        dateProvider: FixedRuntimeDateProvider(now: Date(timeIntervalSince1970: 900))
    )

    await orchestrator.start()
    let commands = await controller.commands()
    let stream = await orchestrator.makeUpdateStream()
    var iterator = stream.makeAsyncIterator()
    let update = await iterator.next()

    #expect(commands.isEmpty)
    #expect(update?.appState.controllerStatus.mode == .readOnly)
    #expect(update?.appState.chargeState == .suspended)
    #expect(update?.capabilityReport.status(for: .chargeControl)?.support == .readOnlyFallback)
}

@Test
func orchestratorDoesNotApplyCommandsWhenCapabilityProbeReportsVersionMismatch() async {
    let monitor = MockRuntimeBatteryMonitor(
        currentSnapshotValue: BatterySnapshot(
            chargePercent: 82,
            isPowerConnected: true,
            isCharging: true,
            observedAt: Date(timeIntervalSince1970: 950),
            source: .system
        )
    )
    let controller = SequencedChargeController(
        statuses: [
            ControllerStatus(
                mode: .fullControl,
                helperConnection: .connected,
                isChargingEnabled: true,
                checkedAt: Date(timeIntervalSince1970: 950)
            )
        ],
        selfTestResult: ControllerSelfTestResult(
            outcome: .passed,
            message: "ok",
            checkedAt: Date(timeIntervalSince1970: 950)
        )
    )
    let versionMismatchStatus = HelperInstallStatus(
        state: .versionMismatch,
        serviceName: CellCapHelperXPC.serviceName,
        helperPath: CellCapHelperXPC.installedBinaryPath,
        plistPath: CellCapHelperXPC.launchDaemonPlistPath,
        helperVersion: "older-helper",
        expectedVersion: CellCapHelperXPC.contractVersion,
        reason: "helper 버전이 앱 계약 버전과 다릅니다.",
        checkedAt: Date(timeIntervalSince1970: 950)
    )
    let report = fullControlCapabilityReport(reason: "helper 버전 불일치로 제어를 차단합니다.")
        .replacingStatus(for: .helperInstallation, support: .readOnlyFallback, reason: versionMismatchStatus.reason)
        .replacingStatus(for: .helperPrivilege, support: .readOnlyFallback, reason: versionMismatchStatus.reason)
        .replacingRecommendedControllerMode(.readOnly)
        .replacingHelperInstallStatus(versionMismatchStatus)
    let orchestrator = AppRuntimeOrchestrator(
        batteryMonitor: monitor,
        controller: controller,
        capabilityChecker: CapabilityChecker(
            environment: MockRuntimeEnvironmentProvider(
                operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
                isAppleSilicon: true
            )
        ),
        capabilityProber: MockHelperCapabilityProber(
            summary: HelperCapabilityProbeSummary(
                report: report,
                status: ControllerStatus(
                    mode: .fullControl,
                    helperConnection: .connected,
                    isChargingEnabled: true,
                    checkedAt: Date(timeIntervalSince1970: 950)
                )
            )
        ),
        helperInstallChecker: MockHelperInstallChecker(
            status: HelperInstallStatus(
                state: .bootstrapped,
                serviceName: CellCapHelperXPC.serviceName,
                helperPath: CellCapHelperXPC.installedBinaryPath,
                plistPath: CellCapHelperXPC.launchDaemonPlistPath,
                helperVersion: nil,
                expectedVersion: CellCapHelperXPC.contractVersion,
                reason: "launchd에 helper가 등록되어 있습니다.",
                checkedAt: Date(timeIntervalSince1970: 950)
            )
        ),
        dateProvider: FixedRuntimeDateProvider(now: Date(timeIntervalSince1970: 950))
    )

    await orchestrator.start()
    let commands = await controller.commands()
    let stream = await orchestrator.makeUpdateStream()
    var iterator = stream.makeAsyncIterator()
    let update = await iterator.next()

    #expect(commands.isEmpty)
    #expect(update?.appState.controllerStatus.mode == .readOnly)
    #expect(update?.capabilityReport.helperInstallStatus?.state == .versionMismatch)
}

@Test
func orchestratorRestoresPersistedPolicyOnStart() async {
    let now = Date(timeIntervalSince1970: 1_100)
    let monitor = MockRuntimeBatteryMonitor(
        currentSnapshotValue: BatterySnapshot(
            chargePercent: 74,
            isPowerConnected: true,
            isCharging: true,
            observedAt: now,
            source: .system
        )
    )
    let controller = SequencedChargeController(
        statuses: [
            ControllerStatus(
                mode: .fullControl,
                helperConnection: .connected,
                isChargingEnabled: true,
                checkedAt: now
            )
        ],
        selfTestResult: ControllerSelfTestResult(
            outcome: .passed,
            message: "ok",
            checkedAt: now
        )
    )
    let persistedPolicy = ChargePolicy(
        upperLimit: 88,
        rechargeThreshold: 70,
        temporaryOverrideUntil: Date(timeIntervalSince1970: 1_400)
    )
    let store = MockChargePolicyStore(loadedPolicy: persistedPolicy)
    let orchestrator = AppRuntimeOrchestrator(
        batteryMonitor: monitor,
        controller: controller,
        capabilityChecker: CapabilityChecker(
            environment: MockRuntimeEnvironmentProvider(
                operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
                isAppleSilicon: true
            )
        ),
        capabilityProber: MockHelperCapabilityProber(
            summary: fullControlProbeSummary(
                checkedAt: now,
                isChargingEnabled: true
            )
        ),
        helperInstallChecker: MockHelperInstallChecker(
            status: bootstrappedHelperInstallStatus(at: now)
        ),
        policyStore: store,
        dateProvider: FixedRuntimeDateProvider(now: now)
    )

    let stream = await orchestrator.makeUpdateStream()
    let task = Task {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next()
    }

    await orchestrator.start()
    let update = await task.value

    #expect(update?.appState.policy.upperLimit == 88)
    #expect(update?.appState.policy.rechargeThreshold == 70)
    #expect(store.savedPolicies().isEmpty)
}

@Test
func orchestratorKeepsChargingWithinBandAfterAppRestartWhenControllerIsAlreadyCharging() async {
    let now = Date(timeIntervalSince1970: 1_200)
    let monitor = MockRuntimeBatteryMonitor(
        currentSnapshotValue: BatterySnapshot(
            chargePercent: 56,
            isPowerConnected: true,
            isCharging: true,
            observedAt: now,
            source: .system
        )
    )
    let controller = SequencedChargeController(
        statuses: [
            ControllerStatus(
                mode: .fullControl,
                helperConnection: .connected,
                isChargingEnabled: true,
                checkedAt: now
            )
        ],
        selfTestResult: ControllerSelfTestResult(
            outcome: .passed,
            message: "ok",
            checkedAt: now
        )
    )
    let store = MockChargePolicyStore(
        loadedPolicy: ChargePolicy(
            upperLimit: 60,
            rechargeThreshold: 55
        )
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
        capabilityProber: MockHelperCapabilityProber(
            summary: fullControlProbeSummary(
                checkedAt: now,
                isChargingEnabled: true
            )
        ),
        helperInstallChecker: MockHelperInstallChecker(
            status: bootstrappedHelperInstallStatus(at: now)
        ),
        policyStore: store,
        dateProvider: FixedRuntimeDateProvider(now: now)
    )

    let stream = await orchestrator.makeUpdateStream()
    let task = Task {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next()
    }

    await orchestrator.start()
    let update = await task.value

    #expect(update?.appState.chargeState == .charging)
    #expect(update?.chargingCommand == .noChange)
}

@Test
func orchestratorPersistsNormalizedPolicyWhenExpiredOverrideIsRestored() async {
    let now = Date(timeIntervalSince1970: 1_500)
    let monitor = MockRuntimeBatteryMonitor(
        currentSnapshotValue: BatterySnapshot(
            chargePercent: 79,
            isPowerConnected: true,
            isCharging: false,
            observedAt: now,
            source: .system
        )
    )
    let controller = SequencedChargeController(
        statuses: [
            ControllerStatus(
                mode: .fullControl,
                helperConnection: .connected,
                isChargingEnabled: false,
                checkedAt: now
            )
        ],
        selfTestResult: ControllerSelfTestResult(
            outcome: .passed,
            message: "ok",
            checkedAt: now
        )
    )
    let store = MockChargePolicyStore(
        loadedPolicy: ChargePolicy(
            upperLimit: 80,
            rechargeThreshold: 75,
            temporaryOverrideUntil: Date(timeIntervalSince1970: 1_400)
        )
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
        capabilityProber: MockHelperCapabilityProber(
            summary: fullControlProbeSummary(
                checkedAt: now,
                isChargingEnabled: false
            )
        ),
        helperInstallChecker: MockHelperInstallChecker(
            status: bootstrappedHelperInstallStatus(at: now)
        ),
        policyStore: store,
        dateProvider: FixedRuntimeDateProvider(now: now)
    )

    await orchestrator.start()

    let savedPolicies = store.savedPolicies()
    #expect(savedPolicies.count == 1)
    #expect(savedPolicies.first?.temporaryOverrideUntil == nil)
}

@Test
func orchestratorFallsBackToDefaultPolicyWhenStoredPolicyLoadFails() async {
    let now = Date(timeIntervalSince1970: 1_600)
    let monitor = MockRuntimeBatteryMonitor(
        currentSnapshotValue: BatterySnapshot(
            chargePercent: 82,
            isPowerConnected: true,
            isCharging: false,
            observedAt: now,
            source: .system
        )
    )
    let controller = SequencedChargeController(
        statuses: [
            ControllerStatus(
                mode: .fullControl,
                helperConnection: .connected,
                isChargingEnabled: false,
                checkedAt: now
            )
        ],
        selfTestResult: ControllerSelfTestResult(
            outcome: .passed,
            message: "ok",
            checkedAt: now
        )
    )
    let store = MockChargePolicyStore(loadError: MockChargePolicyStoreError.failedToLoad)
    let orchestrator = AppRuntimeOrchestrator(
        batteryMonitor: monitor,
        controller: controller,
        capabilityChecker: CapabilityChecker(
            environment: MockRuntimeEnvironmentProvider(
                operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
                isAppleSilicon: true
            )
        ),
        capabilityProber: MockHelperCapabilityProber(
            summary: fullControlProbeSummary(
                checkedAt: now,
                isChargingEnabled: false
            )
        ),
        helperInstallChecker: MockHelperInstallChecker(
            status: bootstrappedHelperInstallStatus(at: now)
        ),
        policyStore: store,
        dateProvider: FixedRuntimeDateProvider(now: now)
    )

    let stream = await orchestrator.makeUpdateStream()
    let task = Task {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next()
    }

    await orchestrator.start()
    let update = await task.value

    #expect(update?.appState.policy == ChargePolicy())
}

private actor SequencedChargeController: ChargeController {
    enum Command: Sendable, Equatable {
        case setChargingEnabled(Bool)
        case setTemporaryOverride(Date?)
    }

    private var statuses: [ControllerStatus]
    private let selfTestResult: ControllerSelfTestResult
    private var requests = 0
    private var selfTestRequests = 0
    private var recordedCommands: [Command] = []

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

    func setChargingEnabled(_ enabled: Bool) async throws {
        recordedCommands.append(.setChargingEnabled(enabled))
        statuses = statuses.map { status in
            var updated = status
            updated.isChargingEnabled = enabled
            return updated
        }
    }

    func setTemporaryOverride(until: Date?) async throws {
        recordedCommands.append(.setTemporaryOverride(until))
        statuses = statuses.map { status in
            var updated = status
            updated.temporaryOverrideUntil = until
            return updated
        }
    }

    func getControllerStatus() async -> ControllerStatus {
        requests += 1
        if statuses.count > 1 {
            return statuses.removeFirst()
        }
        return statuses.first ?? ControllerStatus(mode: .readOnly, helperConnection: .unavailable)
    }

    func selfTest() async -> ControllerSelfTestResult {
        selfTestRequests += 1
        return selfTestResult
    }

    func statusRequestCount() -> Int {
        requests
    }

    func selfTestRequestCount() -> Int {
        selfTestRequests
    }

    func commands() -> [Command] {
        recordedCommands
    }
}

private struct MockHelperCapabilityProber: HelperCapabilityProbing {
    let summary: HelperCapabilityProbeSummary

    init(summary: HelperCapabilityProbeSummary? = nil) {
        self.summary = summary ?? HelperCapabilityProbeSummary(
            report: CapabilityReport(
                statuses: [
                    CapabilityStatus(key: .appleSilicon, support: .supported, reason: "Apple Silicon 환경입니다."),
                    CapabilityStatus(key: .chargeControl, support: .experimental, reason: "private SMC helper backend를 사용할 수 있습니다.")
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

    func capabilityProbe() async throws -> HelperCapabilityProbeSummary {
        summary
    }
}

private struct MockHelperInstallChecker: HelperInstallChecking {
    let status: HelperInstallStatus

    func currentStatus(now: Date) async -> HelperInstallStatus {
        status
    }

    func currentStatus(now: Date, forceRefresh: Bool) async -> HelperInstallStatus {
        status
    }
}

private func fullControlCapabilityReport(reason: String) -> CapabilityReport {
    CapabilityReport(
        statuses: [
            CapabilityStatus(key: .appleSilicon, support: .supported, reason: "Apple Silicon 환경입니다."),
            CapabilityStatus(key: .macOSVersion, support: .supported, reason: "macOS 26+ 조건을 만족합니다."),
            CapabilityStatus(key: .batteryObservation, support: .supported, reason: "내장 배터리를 읽을 수 있습니다."),
            CapabilityStatus(key: .powerSourceObservation, support: .supported, reason: "전원 연결 상태를 읽을 수 있습니다."),
            CapabilityStatus(key: .sleepWakeResynchronization, support: .supported, reason: "wake 이후 재동기화가 가능합니다."),
            CapabilityStatus(key: .helperInstallation, support: .supported, reason: "helper 설치가 확인되었습니다."),
            CapabilityStatus(key: .helperPrivilege, support: .supported, reason: "helper 권한이 확인되었습니다."),
            CapabilityStatus(key: .chargeControl, support: .experimental, reason: reason)
        ],
        recommendedControllerMode: .fullControl,
        helperInstallStatus: HelperInstallStatus(
            state: .xpcReachable,
            serviceName: CellCapHelperXPC.serviceName,
            helperPath: CellCapHelperXPC.installedBinaryPath,
            plistPath: CellCapHelperXPC.launchDaemonPlistPath,
            helperVersion: CellCapHelperXPC.contractVersion,
            expectedVersion: CellCapHelperXPC.contractVersion,
            reason: "helper XPC 연결이 확인되었습니다.",
            checkedAt: Date(timeIntervalSince1970: 900)
        )
    )
}

private func fullControlProbeSummary(checkedAt: Date, isChargingEnabled: Bool) -> HelperCapabilityProbeSummary {
    HelperCapabilityProbeSummary(
        report: fullControlCapabilityReport(reason: "SMC helper가 준비되었습니다."),
        status: ControllerStatus(
            mode: .fullControl,
            helperConnection: .connected,
            isChargingEnabled: isChargingEnabled,
            temporaryOverrideUntil: nil,
            lastErrorDescription: nil,
            checkedAt: checkedAt
        )
    )
}

private func bootstrappedHelperInstallStatus(at checkedAt: Date) -> HelperInstallStatus {
    HelperInstallStatus(
        state: .bootstrapped,
        serviceName: CellCapHelperXPC.serviceName,
        helperPath: CellCapHelperXPC.installedBinaryPath,
        plistPath: CellCapHelperXPC.launchDaemonPlistPath,
        helperVersion: CellCapHelperXPC.contractVersion,
        expectedVersion: CellCapHelperXPC.contractVersion,
        reason: "launchd에 helper가 등록되어 있습니다.",
        checkedAt: checkedAt
    )
}

private final class MockRuntimeBatteryMonitor: @unchecked Sendable, BatteryMonitoring {
    private let lock = NSLock()
    private var continuations: [AsyncThrowingStream<BatteryMonitorUpdate, Error>.Continuation] = []
    private var currentSnapshotValue: BatterySnapshot?
    private var pendingUpdates: [BatteryMonitorUpdate] = []

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
            self.continuations.append(continuation)
            let pendingUpdates = self.pendingUpdates
            self.pendingUpdates.removeAll()
            lock.unlock()

            for update in pendingUpdates {
                continuation.yield(update)
            }
        }
    }

    func emit(_ update: BatteryMonitorUpdate) {
        lock.lock()
        currentSnapshotValue = update.snapshot
        let continuation = self.continuations.last
        lock.unlock()
        continuation?.yield(update)
    }

    func fail(_ error: Error) {
        lock.lock()
        let continuation = continuations.last
        lock.unlock()
        continuation?.finish(throwing: error)
    }

    func emitOnNextStream(_ update: BatteryMonitorUpdate) {
        lock.lock()
        currentSnapshotValue = update.snapshot
        pendingUpdates.append(update)
        lock.unlock()
    }

    func waitUntilStreamCount(atLeast minimum: Int) async {
        while true {
            if streamCount() >= minimum {
                return
            }

            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func streamCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return continuations.count
    }
}

private struct RuntimeMonitorFailure: Error {}

private actor BlockingResynchronizingChargeController: ChargeController {
    private let now: Date
    private var statusRequests = 0
    private var blockedRequestContinuation: CheckedContinuation<Void, Never>?

    init(now: Date) {
        self.now = now
    }

    func setChargingEnabled(_ enabled: Bool) async throws {}

    func setTemporaryOverride(until: Date?) async throws {}

    func getControllerStatus() async -> ControllerStatus {
        statusRequests += 1
        if statusRequests == 3 {
            await withCheckedContinuation { continuation in
                blockedRequestContinuation = continuation
            }
        }

        return ControllerStatus(
            mode: .fullControl,
            helperConnection: .connected,
            isChargingEnabled: true,
            checkedAt: now
        )
    }

    func selfTest() async -> ControllerSelfTestResult {
        ControllerSelfTestResult(
            outcome: .passed,
            message: "ok",
            checkedAt: now
        )
    }

    func resumeBlockedStatusRequest() {
        blockedRequestContinuation?.resume()
        blockedRequestContinuation = nil
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

private enum MockChargePolicyStoreError: Error {
    case failedToLoad
    case failedToSave
}

private final class MockChargePolicyStore: @unchecked Sendable, ChargePolicyStoring {
    private let lock = NSLock()
    private let loadedPolicy: ChargePolicy?
    private let loadError: MockChargePolicyStoreError?
    private let saveError: MockChargePolicyStoreError?
    private var recordedPolicies: [ChargePolicy] = []

    init(
        loadedPolicy: ChargePolicy? = nil,
        loadError: MockChargePolicyStoreError? = nil,
        saveError: MockChargePolicyStoreError? = nil
    ) {
        self.loadedPolicy = loadedPolicy
        self.loadError = loadError
        self.saveError = saveError
    }

    func load() throws -> ChargePolicy? {
        if let loadError {
            throw loadError
        }

        return loadedPolicy
    }

    func save(_ policy: ChargePolicy) throws {
        if let saveError {
            throw saveError
        }

        lock.lock()
        recordedPolicies.append(policy)
        lock.unlock()
    }

    func clear() throws {
        lock.lock()
        recordedPolicies.removeAll()
        lock.unlock()
    }

    func savedPolicies() -> [ChargePolicy] {
        lock.lock()
        defer { lock.unlock() }
        return recordedPolicies
    }
}
