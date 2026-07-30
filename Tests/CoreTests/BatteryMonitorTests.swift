import Foundation
import Core
import Shared
import SystemSupport
import Testing

@Test
func batterySnapshotTranslatorClampsChargePercent() {
    let translator = BatterySnapshotTranslator()
    let high = translator.translate(
        PowerSourceReading(
            chargePercent: 130,
            isPowerConnected: true,
            isCharging: false,
            isBatteryPresent: true
        ),
        observedAt: Date(timeIntervalSince1970: 100)
    )
    let low = translator.translate(
        PowerSourceReading(
            chargePercent: -5,
            isPowerConnected: false,
            isCharging: false,
            isBatteryPresent: true
        ),
        observedAt: Date(timeIntervalSince1970: 100)
    )

    #expect(high.chargePercent == 100)
    #expect(high.isPowerConnected)
    #expect(low.chargePercent == 0)
    #expect(!low.isPowerConnected)
}

@Test
func batteryMonitorRefreshUsesInjectedSnapshotProvider() throws {
    let snapshot = BatterySnapshot(
        chargePercent: 66,
        isPowerConnected: true,
        isCharging: false,
        observedAt: Date(timeIntervalSince1970: 123),
        source: .system
    )
    let monitor = BatteryMonitor(
        snapshotProvider: MockBatterySnapshotProvider(snapshot: snapshot),
        eventSource: NoOpBatteryMonitorEventSource(),
        dateProvider: FixedDateProvider(now: Date(timeIntervalSince1970: 123))
    )

    let update = try monitor.refresh(
        trigger: .manualRefresh,
        now: Date(timeIntervalSince1970: 123)
    )

    #expect(update.trigger == .manualRefresh)
    #expect(update.snapshot == snapshot)
}

@Test
func batteryMonitorEmitsInitialSnapshotAndWakeEvent() async throws {
    let snapshotProvider = SequenceBatterySnapshotProvider(
        snapshots: [
            BatterySnapshot(
                chargePercent: 55,
                isPowerConnected: false,
                isCharging: false,
                observedAt: Date(timeIntervalSince1970: 100),
                source: .system
            ),
            BatterySnapshot(
                chargePercent: 56,
                isPowerConnected: true,
                isCharging: true,
                observedAt: Date(timeIntervalSince1970: 200),
                source: .system
            )
        ]
    )
    let eventSource = MockBatteryMonitorEventSource()
    let monitor = BatteryMonitor(
        snapshotProvider: snapshotProvider,
        eventSource: eventSource,
        dateProvider: SequenceDateProvider(
            dates: [
                Date(timeIntervalSince1970: 100),
                Date(timeIntervalSince1970: 200)
            ]
        )
    )

    var iterator = monitor.makeUpdateStream().makeAsyncIterator()
    let initialUpdate = try await iterator.next()
    eventSource.emit(.didWake)
    let wakeUpdate = try await iterator.next()

    #expect(initialUpdate?.trigger == .monitorStarted)
    #expect(initialUpdate?.snapshot?.chargePercent == 55)
    #expect(wakeUpdate?.trigger == .didWake)
    #expect(wakeUpdate?.snapshot?.isPowerConnected == true)
}

@Test
func compositeBatteryMonitorEventSourceFansOutEventsAndCancelsChildren() {
    let first = MockBatteryMonitorEventSource()
    let second = MockBatteryMonitorEventSource()
    let composite = CompositeBatteryMonitorEventSource(sources: [first, second])
    let received = TriggerRecorder()

    let observation = composite.start { trigger in
        received.append(trigger)
    }

    first.emit(.powerSourceChanged)
    second.emit(.didWake)
    #expect(received.values() == [.powerSourceChanged, .didWake])
    #expect(first.isActive)
    #expect(second.isActive)

    observation.cancel()
    #expect(!first.isActive)
    #expect(!second.isActive)

    first.emit(.willSleep)
    #expect(received.values() == [.powerSourceChanged, .didWake])
}

private struct MockBatterySnapshotProvider: BatterySnapshotProviding {
    let snapshot: BatterySnapshot?

    func currentSnapshot(now: Date) throws -> BatterySnapshot? {
        snapshot
    }
}

private final class SequenceBatterySnapshotProvider: @unchecked Sendable, BatterySnapshotProviding {
    private let lock = NSLock()
    private var snapshots: [BatterySnapshot?]

    init(snapshots: [BatterySnapshot?]) {
        self.snapshots = snapshots
    }

    func currentSnapshot(now: Date) throws -> BatterySnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return snapshots.isEmpty ? nil : snapshots.removeFirst()
    }
}

private final class MockBatteryMonitorEventSource: @unchecked Sendable, BatteryMonitorEventSource {
    private let lock = NSLock()
    private var handler: (@Sendable (BatteryMonitorTrigger) -> Void)?

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return handler != nil
    }

    func start(_ handler: @escaping @Sendable (BatteryMonitorTrigger) -> Void) -> BatteryMonitorObservation {
        lock.lock()
        self.handler = handler
        lock.unlock()

        return BatteryMonitorObservation { [weak self] in
            self?.lock.lock()
            self?.handler = nil
            self?.lock.unlock()
        }
    }

    func emit(_ trigger: BatteryMonitorTrigger) {
        lock.lock()
        let handler = self.handler
        lock.unlock()
        handler?(trigger)
    }
}

private final class TriggerRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [BatteryMonitorTrigger] = []

    func append(_ trigger: BatteryMonitorTrigger) {
        lock.lock()
        stored.append(trigger)
        lock.unlock()
    }

    func values() -> [BatteryMonitorTrigger] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

