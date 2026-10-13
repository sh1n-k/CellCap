import Core
import Foundation
import notify
import Shared
import SystemSupport
import Testing

// 실제 키(`com.apple.system.powersources.chargingtofulloverride`)는 다른 시스템 프로세스도 구독하므로 건드리지 않는다.
// 테스트마다 고유한 사용자 네임스페이스 키를 주입해 notify 등록·상태 읽기·전달 경로를 실제 notifyd로 검증한다.

@Test
func systemFullChargeNotificationNameMatchesObservedPowerdKey() {
    #expect(SystemFullChargeNotification.name == "com.apple.system.powersources.chargingtofulloverride")
}

@Test
func notifyFullChargeStateReaderReadsPostedState() {
    let poster = TestFullChargePoster()
    let reader = NotifySystemFullChargeStateReader(name: poster.name)

    #expect(reader.isFullChargeRequested() == false)

    poster.post(active: true)
    #expect(reader.isFullChargeRequested() == true)

    poster.post(active: false)
    #expect(reader.isFullChargeRequested() == false)
}

@Test
func systemFullChargeObserverDeliversUntilStopped() async {
    let poster = TestFullChargePoster()
    let observer = SystemFullChargeNotificationObserver(
        name: poster.name,
        queue: DispatchQueue(label: "CellCapTests.fullChargeObserver")
    )
    let counter = DeliveryCounter()

    #expect(observer.start { counter.increment() })

    poster.post(active: true)
    #expect(await counter.waitUntil(atLeast: 1))

    observer.stop()
    let deliveredBeforeStop = counter.value()
    poster.post(active: false)
    try? await Task.sleep(for: .milliseconds(300))
    #expect(counter.value() == deliveredBeforeStop)
}

@Test
func systemBatterySnapshotProviderSkipsFullChargeStateWithoutReader() throws {
    let provider = SystemBatterySnapshotProvider(readingProvider: FixedPowerSourceReadingProvider())

    let snapshot = try provider.currentSnapshot(now: Date(timeIntervalSince1970: 100))

    #expect(snapshot?.isSystemFullChargeActive == nil)
}

@Test
func systemBatterySnapshotProviderReportsUnreadableFullChargeStateAsUnknown() throws {
    let provider = SystemBatterySnapshotProvider(
        readingProvider: FixedPowerSourceReadingProvider(),
        fullChargeStateReader: UnreadableFullChargeStateReader()
    )

    let snapshot = try provider.currentSnapshot(now: Date(timeIntervalSince1970: 100))

    #expect(snapshot?.isSystemFullChargeActive == nil)
    #expect(snapshot?.chargePercent == 41)
}

@Test
func batteryMonitorDeliversSystemFullChargeChangesFromDarwinNotification() async {
    let poster = TestFullChargePoster()
    let monitor = BatteryMonitor(
        snapshotProvider: SystemBatterySnapshotProvider(
            readingProvider: FixedPowerSourceReadingProvider(),
            fullChargeStateReader: NotifySystemFullChargeStateReader(name: poster.name)
        ),
        eventSource: SystemFullChargeEventSource(
            notificationName: poster.name,
            queue: DispatchQueue(label: "CellCapTests.fullChargeEventSource")
        ),
        dateProvider: FixedDateProvider(now: Date(timeIntervalSince1970: 100))
    )
    let recorder = MonitorUpdateRecorder()
    let task = Task {
        for try await update in monitor.makeUpdateStream(emitInitialSnapshot: true) {
            recorder.append(update)
        }
    }
    defer { task.cancel() }

    #expect(await recorder.waitUntil(count: 1))
    #expect(recorder.updates()[0].trigger == .monitorStarted)
    #expect(recorder.updates()[0].snapshot?.isSystemFullChargeActive == false)

    poster.post(active: true)
    #expect(await recorder.waitUntil(count: 2))
    #expect(recorder.updates()[1].trigger == .systemFullChargeChanged)
    #expect(recorder.updates()[1].snapshot?.isSystemFullChargeActive == true)

    poster.post(active: false)
    #expect(await recorder.waitUntil(count: 3))
    #expect(recorder.updates()[2].trigger == .systemFullChargeChanged)
    #expect(recorder.updates()[2].snapshot?.isSystemFullChargeActive == false)
}

/// 테스트 전용 키에 상태를 쓰고 post한다. 토큰을 유지해야 notifyd가 상태를 보관한다.
private final class TestFullChargePoster {
    let name = "com.shin.cellcap.tests.fullcharge.\(UUID().uuidString)"
    private var token: Int32 = 0

    init() {
        let status = notify_register_check(name, &token)
        precondition(status == UInt32(NOTIFY_STATUS_OK), "notify_register_check failed: \(status)")
    }

    deinit {
        notify_cancel(token)
    }

    func post(active: Bool) {
        notify_set_state(token, active ? 1 : 0)
        notify_post(name)
    }
}

private struct FixedPowerSourceReadingProvider: PowerSourceReadingProviding {
    func readPowerSource(now: Date) throws -> PowerSourceReading? {
        PowerSourceReading(chargePercent: 41, isPowerConnected: true, isCharging: false, isBatteryPresent: true)
    }
}

private struct UnreadableFullChargeStateReader: SystemFullChargeStateReading {
    func isFullChargeRequested() -> Bool? {
        nil
    }
}

private final class DeliveryCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    func value() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func waitUntil(atLeast minimum: Int, timeout: Duration = .seconds(5)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if value() >= minimum {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return value() >= minimum
    }
}

private final class MonitorUpdateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [BatteryMonitorUpdate] = []

    func append(_ update: BatteryMonitorUpdate) {
        lock.lock()
        stored.append(update)
        lock.unlock()
    }

    func updates() -> [BatteryMonitorUpdate] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func waitUntil(count: Int, timeout: Duration = .seconds(5)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if updates().count >= count {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return updates().count >= count
    }
}
