@testable import Core
import Foundation
import Shared
import Testing

@Test
func xpcChargeControllerReturnsReadOnlyFallbackWhenTransportFails() async {
    let transport = MockHelperServiceTransport(
        statusResult: .failure(HelperTransportError.connectionFailure("timeout")),
        selfTestResult: .failure(HelperTransportError.connectionFailure("timeout"))
    )
    let controller = XPCChargeController(transport: transport)

    let status = await controller.getControllerStatus()
    let selfTest = await controller.selfTest()

    #expect(status.mode == .readOnly)
    #expect(status.helperConnection == .disconnected)
    #expect(status.lastErrorDescription == "XPC 연결 실패: timeout")
    #expect(selfTest.outcome == .failed)
}

@Test
func xpcChargeControllerDelegatesCapabilityProbeSummary() async throws {
    let report = CapabilityReport(
        statuses: [
            CapabilityStatus(key: .appleSilicon, support: .supported, reason: "ok"),
            CapabilityStatus(key: .chargeControl, support: .experimental, reason: "private helper backend available")
        ],
        recommendedControllerMode: .readOnly
    )
    let status = ControllerStatus(
        mode: .readOnly,
        helperConnection: .connected,
        lastErrorDescription: nil
    )
    let transport = MockHelperServiceTransport(
        capabilityProbeResult: .success(
            HelperCapabilityProbeSummary(report: report, status: status)
        )
    )
    let controller = XPCChargeController(transport: transport)

    let summary = try await controller.capabilityProbe()

    #expect(summary.report == report)
    #expect(summary.status == status)
}

@Test
func oneShotResultGateTimesOutWithoutReply() async {
    let counter = LockedCounter()

    do {
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            _ = OneShotResultGate(
                continuation: continuation,
                timeout: .milliseconds(20),
                timeoutError: HelperTransportError.connectionFailure("XPC request timed out.")
            ) {
                counter.increment()
            }
        }
        Issue.record("timeout failure expected")
    } catch {
        #expect(error as? HelperTransportError == .connectionFailure("XPC request timed out."))
    }

    #expect(counter.value() == 1)
}

@Test
func oneShotResultGateCompletesOnTaskCancellation() async {
    let counter = LockedCounter()
    let cancellationBox = CancellationHandlerBox()
    let readyBox = ContinuationBox<Void>()

    let task = Task<Int, Error> {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
                let gate = OneShotResultGate(
                    continuation: continuation,
                    timeout: .seconds(1),
                    timeoutError: HelperTransportError.connectionFailure("XPC request timed out.")
                ) {
                    cancellationBox.clear()
                    counter.increment()
                }
                cancellationBox.set {
                    gate.complete(
                        with: .failure(
                            HelperTransportError.connectionFailure("XPC request cancelled.")
                        )
                    )
                }
                Task {
                    await readyBox.resume(returning: ())
                }
            }
        } onCancel: {
            cancellationBox.run()
        }
    }

    await readyBox.value()
    task.cancel()

    do {
        _ = try await task.value
        Issue.record("cancellation failure expected")
    } catch {
        #expect(error as? HelperTransportError == .connectionFailure("XPC request cancelled."))
    }

    #expect(counter.value() == 1)
}

@Test
func oneShotResultGateIgnoresInvalidationAfterReply() async throws {
    let counter = LockedCounter()

    let value = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
        let gate = OneShotResultGate<Int>(continuation: continuation) {
            counter.increment()
        }
        gate.complete(with: .success(1))
        gate.complete(
            with: .failure(HelperTransportError.connectionFailure("late failure")),
        )
    }

    #expect(value == 1)
    #expect(counter.value() == 1)
}

@Test
func oneShotResultGateIgnoresReplyAfterError() async {
    let counter = LockedCounter()

    do {
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            let gate = OneShotResultGate<Int>(continuation: continuation) {
                counter.increment()
            }
            gate.complete(with: .failure(HelperTransportError.connectionFailure("early failure")))
            gate.complete(with: .success(1))
        }
        Issue.record("failure expected")
    } catch {
        #expect(error as? HelperTransportError == .connectionFailure("early failure"))
    }

    #expect(counter.value() == 1)
}

private struct MockHelperServiceTransport: HelperServiceTransporting {
    var statusResult: Result<ControllerStatus, Error> = .success(
        ControllerStatus(mode: .readOnly, helperConnection: .connected)
    )
    var selfTestResult: Result<HelperSelfTestSummary, Error> = .success(
        HelperSelfTestSummary(
            result: ControllerSelfTestResult(outcome: .degraded, message: "stub"),
            status: nil
        )
    )
    var capabilityProbeResult: Result<HelperCapabilityProbeSummary, Error> = .success(
        HelperCapabilityProbeSummary(
            report: CapabilityReport(
                statuses: [
                    CapabilityStatus(key: .appleSilicon, support: .supported, reason: "ok"),
                    CapabilityStatus(key: .chargeControl, support: .experimental, reason: "private helper backend available")
                ],
                recommendedControllerMode: .readOnly
            ),
            status: ControllerStatus(mode: .readOnly, helperConnection: .connected)
        )
    )

    func fetchControllerStatus() async throws -> ControllerStatus {
        try statusResult.get()
    }

    func selfTest() async throws -> HelperSelfTestSummary {
        try selfTestResult.get()
    }

    func capabilityProbe() async throws -> HelperCapabilityProbeSummary {
        try capabilityProbeResult.get()
    }

    func setChargingEnabled(_ enabled: Bool) async throws -> ControllerStatus {
        try statusResult.get()
    }

    func setTemporaryOverride(until: Date?) async throws -> ControllerStatus {
        try statusResult.get()
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var currentValue = 0

    func increment() {
        lock.lock()
        currentValue += 1
        lock.unlock()
    }

    func value() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return currentValue
    }
}

private actor ContinuationBox<T: Sendable> {
    private var continuation: CheckedContinuation<T, Never>?
    private var storedValue: T?

    func value() async -> T {
        if let storedValue {
            self.storedValue = nil
            return storedValue
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(returning value: T) {
        let continuation = self.continuation
        self.continuation = nil
        if continuation == nil {
            storedValue = value
        }
        continuation?.resume(returning: value)
    }
}
