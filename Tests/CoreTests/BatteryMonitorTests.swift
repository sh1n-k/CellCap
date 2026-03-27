import Foundation
import Core
import Shared
import Testing

@Test
func batterySnapshotTranslatorClampsChargePercent() {
    let translator = BatterySnapshotTranslator()
    let snapshot = translator.translate(
        PowerSourceReading(
            chargePercent: 130,
            isPowerConnected: true,
            isCharging: false,
            isBatteryPresent: true
        ),
        observedAt: Date(timeIntervalSince1970: 100)
    )

    #expect(snapshot.chargePercent == 100)
    #expect(snapshot.isPowerConnected)
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
func systemBatteryMonitorEventSourceCombinesPowerAndSleepWakeHooks() {
    let composite = CompositeBatteryMonitorEventSource(
        sources: [
            MockBatteryMonitorEventSource(),
            MockBatteryMonitorEventSource()
        ]
    )

    let observation = composite.start { _ in }
    observation.cancel()
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

private struct FixedDateProvider: DateProviding {
    let now: Date
}

private final class SequenceDateProvider: @unchecked Sendable, DateProviding {
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
