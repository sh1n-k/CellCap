import AppKit
import Foundation
import IOKit.ps
import Shared

public enum BatteryMonitorTrigger: String, Sendable, Equatable, CaseIterable {
    case monitorStarted
    case manualRefresh
    case powerSourceChanged
    case willSleep
    case didWake
}

public struct BatteryMonitorUpdate: Sendable, Equatable {
    public var trigger: BatteryMonitorTrigger
    public var snapshot: BatterySnapshot?
    public var observedAt: Date

    public init(
        trigger: BatteryMonitorTrigger,
        snapshot: BatterySnapshot?,
        observedAt: Date
    ) {
        self.trigger = trigger
        self.snapshot = snapshot
        self.observedAt = observedAt
    }
}

public protocol DateProviding: Sendable {
    var now: Date { get }
}

public struct SystemDateProvider: DateProviding {
    public init() {}

    public var now: Date { .now }
}

public protocol BatterySnapshotProviding: Sendable {
    func currentSnapshot(now: Date) throws -> BatterySnapshot?
}

public protocol BatteryMonitoring: Sendable {
    func currentSnapshot(now: Date) throws -> BatterySnapshot?
    func refresh(trigger: BatteryMonitorTrigger, now: Date) throws -> BatteryMonitorUpdate
    func makeUpdateStream(emitInitialSnapshot: Bool) -> AsyncThrowingStream<BatteryMonitorUpdate, Error>
}

public protocol BatteryMonitorEventSource: Sendable {
    func start(_ handler: @escaping @Sendable (BatteryMonitorTrigger) -> Void) -> BatteryMonitorObservation
}

public final class BatteryMonitorObservation: @unchecked Sendable {
    private let lock = NSLock()
    private let onCancel: () -> Void
    private var cancelled = false

    public init(onCancel: @escaping () -> Void = {}) {
        self.onCancel = onCancel
    }

    public func cancel() {
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            return
        }
        cancelled = true
        lock.unlock()
        onCancel()
    }

    deinit {
        cancel()
    }
}

public struct NoOpBatteryMonitorEventSource: BatteryMonitorEventSource {
    public init() {}

    public func start(_ handler: @escaping @Sendable (BatteryMonitorTrigger) -> Void) -> BatteryMonitorObservation {
        BatteryMonitorObservation()
    }
}

public struct CompositeBatteryMonitorEventSource: BatteryMonitorEventSource {
    private let sources: [any BatteryMonitorEventSource]

    public init(sources: [any BatteryMonitorEventSource]) {
        self.sources = sources
    }

    public func start(_ handler: @escaping @Sendable (BatteryMonitorTrigger) -> Void) -> BatteryMonitorObservation {
        let observations = sources.map { $0.start(handler) }
        return BatteryMonitorObservation {
            observations.forEach { $0.cancel() }
        }
    }
}

public struct BatteryMonitor: BatteryMonitoring {
    private let snapshotProvider: any BatterySnapshotProviding
    private let eventSource: any BatteryMonitorEventSource
    private let dateProvider: any DateProviding

    public init(
        snapshotProvider: any BatterySnapshotProviding,
        eventSource: any BatteryMonitorEventSource = NoOpBatteryMonitorEventSource(),
        dateProvider: any DateProviding = SystemDateProvider()
    ) {
        self.snapshotProvider = snapshotProvider
        self.eventSource = eventSource
        self.dateProvider = dateProvider
    }

    public func currentSnapshot(now: Date) throws -> BatterySnapshot? {
        try snapshotProvider.currentSnapshot(now: now)
    }

    public func refresh(
        trigger: BatteryMonitorTrigger,
        now: Date
    ) throws -> BatteryMonitorUpdate {
        BatteryMonitorUpdate(
            trigger: trigger,
            snapshot: try snapshotProvider.currentSnapshot(now: now),
            observedAt: now
        )
    }

    public func makeUpdateStream(
        emitInitialSnapshot: Bool = true
    ) -> AsyncThrowingStream<BatteryMonitorUpdate, Error> {
        AsyncThrowingStream { continuation in
            if emitInitialSnapshot {
                do {
                    continuation.yield(
                        try refresh(trigger: .monitorStarted, now: dateProvider.now)
                    )
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
            }

            let observation = eventSource.start { trigger in
                do {
                    continuation.yield(
                        try refresh(trigger: trigger, now: dateProvider.now)
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                observation.cancel()
            }
        }
    }
}

public final class PowerSourceChangeEventSource: @unchecked Sendable, BatteryMonitorEventSource {
    public init() {}

    public func start(_ handler: @escaping @Sendable (BatteryMonitorTrigger) -> Void) -> BatteryMonitorObservation {
        let callbackBox = CallbackBox(handler: handler)
        let retainedBox = Unmanaged.passRetained(callbackBox)

        guard let runLoopSourceRef = IOPSNotificationCreateRunLoopSource(
            { context in
                guard let context else { return }
                let box = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
                box.handler(.powerSourceChanged)
            },
            retainedBox.toOpaque()
        )?.takeRetainedValue() else {
            retainedBox.release()
            return BatteryMonitorObservation()
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSourceRef, .defaultMode)

        return BatteryMonitorObservation {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSourceRef, .defaultMode)
            retainedBox.release()
        }
    }
}

public final class WorkspaceSleepWakeEventSource: @unchecked Sendable, BatteryMonitorEventSource {
    private let workspace: NSWorkspace

    public init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    public func start(_ handler: @escaping @Sendable (BatteryMonitorTrigger) -> Void) -> BatteryMonitorObservation {
        let notificationCenter = workspace.notificationCenter
        let willSleepToken = notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: nil
        ) { _ in
            handler(.willSleep)
        }
        let didWakeToken = notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { _ in
            handler(.didWake)
        }

        return BatteryMonitorObservation {
            notificationCenter.removeObserver(willSleepToken)
            notificationCenter.removeObserver(didWakeToken)
        }
    }
}

public struct SystemBatteryMonitorEventSource: BatteryMonitorEventSource {
    private let composite: CompositeBatteryMonitorEventSource

    public init() {
        self.composite = CompositeBatteryMonitorEventSource(
            sources: [
                PowerSourceChangeEventSource(),
                WorkspaceSleepWakeEventSource()
            ]
        )
    }

    public func start(_ handler: @escaping @Sendable (BatteryMonitorTrigger) -> Void) -> BatteryMonitorObservation {
        composite.start(handler)
    }
}

private final class CallbackBox {
    let handler: @Sendable (BatteryMonitorTrigger) -> Void

    init(handler: @escaping @Sendable (BatteryMonitorTrigger) -> Void) {
        self.handler = handler
    }
}
