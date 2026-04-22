import Foundation
import Shared

public struct HelperSelfTestSummary: Sendable, Equatable {
    public var result: ControllerSelfTestResult
    public var status: ControllerStatus?

    public init(result: ControllerSelfTestResult, status: ControllerStatus?) {
        self.result = result
        self.status = status
    }
}

public struct HelperCapabilityProbeSummary: Sendable, Equatable {
    public var report: CapabilityReport
    public var status: ControllerStatus

    public init(report: CapabilityReport, status: ControllerStatus) {
        self.report = report
        self.status = status
    }
}

public enum HelperTransportError: Error, Sendable, LocalizedError, Equatable {
    case connectionFailure(String)
    case helperReported(code: String, message: String, isRetryable: Bool)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailure(let message):
            "XPC 연결 실패: \(message)"
        case .helperReported(_, let message, _):
            message
        case .invalidResponse(let message):
            "XPC 응답 해석 실패: \(message)"
        }
    }

    static func fromDTO(_ dto: HelperXPCErrorDTO) -> HelperTransportError {
        .helperReported(code: dto.code, message: dto.message, isRetryable: dto.isRetryable)
    }
}

public protocol HelperServiceTransporting: Sendable {
    func fetchControllerStatus() async throws -> ControllerStatus
    func selfTest() async throws -> HelperSelfTestSummary
    func capabilityProbe() async throws -> HelperCapabilityProbeSummary
    func setChargingEnabled(_ enabled: Bool) async throws -> ControllerStatus
    func setTemporaryOverride(until: Date?) async throws -> ControllerStatus
}

public actor NSXPCHelperServiceTransport: HelperServiceTransporting {
    private let serviceName: String
    private let requestTimeout: Duration

    public init(
        serviceName: String = CellCapHelperXPC.serviceName,
        requestTimeout: Duration = .seconds(5)
    ) {
        self.serviceName = serviceName
        self.requestTimeout = requestTimeout
    }

    public func fetchControllerStatus() async throws -> ControllerStatus {
        try await withConnection { remote, finish in
            remote.fetchControllerStatus(HelperRequestDTO()) { response in
                if let error = response.error {
                    finish(.failure(HelperTransportError.fromDTO(error)))
                    return
                }

                finish(.success(response.status.makeModel()))
            }
        }
    }

    public func selfTest() async throws -> HelperSelfTestSummary {
        try await withConnection { remote, finish in
            remote.selfTest(HelperSelfTestRequestDTO()) { response in
                if let error = response.error {
                    finish(.failure(HelperTransportError.fromDTO(error)))
                    return
                }

                finish(
                    .success(
                        HelperSelfTestSummary(
                            result: response.result.makeModel(),
                            status: response.status?.makeModel()
                        )
                    )
                )
            }
        }
    }

    public func capabilityProbe() async throws -> HelperCapabilityProbeSummary {
        try await withConnection { remote, finish in
            remote.capabilityProbe(HelperCapabilityProbeRequestDTO()) { response in
                if let error = response.error {
                    finish(.failure(HelperTransportError.fromDTO(error)))
                    return
                }

                finish(
                    .success(
                        HelperCapabilityProbeSummary(
                            report: response.report.makeModel(),
                            status: response.status.makeModel()
                        )
                    )
                )
            }
        }
    }

    public func setChargingEnabled(_ enabled: Bool) async throws -> ControllerStatus {
        try await withConnection { remote, finish in
            remote.setChargingEnabled(HelperSetChargingEnabledRequestDTO(enabled: enabled)) { response in
                if let error = response.error {
                    finish(.failure(HelperTransportError.fromDTO(error)))
                    return
                }

                finish(.success(response.status.makeModel()))
            }
        }
    }

    public func setTemporaryOverride(until: Date?) async throws -> ControllerStatus {
        try await withConnection { remote, finish in
            remote.setTemporaryOverride(HelperSetTemporaryOverrideRequestDTO(until: until)) { response in
                if let error = response.error {
                    finish(.failure(HelperTransportError.fromDTO(error)))
                    return
                }

                finish(.success(response.status.makeModel()))
            }
        }
    }

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(machServiceName: serviceName, options: .privileged)
        connection.remoteObjectInterface = CellCapHelperXPC.makeRemoteInterface()
        return connection
    }

    private func withConnection<T: Sendable>(
        _ body: @escaping (
            CellCapHelperXPCProtocol,
            @escaping (Result<T, Error>) -> Void
        ) -> Void
    ) async throws -> T {
        let connection = makeConnection()
        let cancellationBox = CancellationHandlerBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let completionGate = OneShotResultGate<T>(
                    continuation: continuation,
                    timeout: requestTimeout,
                    timeoutError: HelperTransportError.connectionFailure("XPC request timed out.")
                ) {
                    cancellationBox.clear()
                    connection.interruptionHandler = nil
                    connection.invalidationHandler = nil
                    connection.invalidate()
                }
                cancellationBox.set {
                    completionGate.complete(
                        with: .failure(
                            HelperTransportError.connectionFailure("XPC request cancelled.")
                        )
                    )
                }

                if Task.isCancelled {
                    cancellationBox.run()
                    return
                }

                connection.interruptionHandler = {
                    completionGate.complete(
                        with: .failure(
                            HelperTransportError.connectionFailure("XPC connection interrupted.")
                        )
                    )
                }
                connection.invalidationHandler = {
                    completionGate.complete(
                        with: .failure(
                            HelperTransportError.connectionFailure("XPC connection invalidated.")
                        )
                    )
                }
                let proxyObject = connection.remoteObjectProxyWithErrorHandler { error in
                    completionGate.complete(
                        with: .failure(
                            HelperTransportError.connectionFailure(error.localizedDescription)
                        )
                    )
                }

                guard let proxy = proxyObject as? CellCapHelperXPCProtocol else {
                    completionGate.complete(
                        with: .failure(
                            HelperTransportError.invalidResponse("Remote proxy cast failed.")
                        )
                    )
                    return
                }

                connection.resume()

                body(proxy) { result in
                    completionGate.complete(with: result)
                }
            }
        } onCancel: {
            cancellationBox.run()
        }
    }
}

final class OneShotResultGate<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: CheckedContinuation<T, Error>
    private let onComplete: () -> Void
    private var timeoutTask: Task<Void, Never>?
    private var completed = false

    init(
        continuation: CheckedContinuation<T, Error>,
        timeout: Duration? = nil,
        timeoutError: (any Error)? = nil,
        onComplete: @escaping () -> Void = {}
    ) {
        self.continuation = continuation
        self.onComplete = onComplete
        self.timeoutTask = nil
        if let timeout, let timeoutError {
            timeoutTask = Task { [self] in
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return
                }
                complete(with: .failure(timeoutError))
            }
        } else {
            self.timeoutTask = nil
        }
    }

    func complete(with result: Result<T, Error>) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let timeoutTask = timeoutTask
        lock.unlock()

        timeoutTask?.cancel()
        onComplete()
        continuation.resume(with: result)
    }
}

final class CancellationHandlerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (() -> Void)?

    func set(_ handler: @escaping () -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func clear() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    func run() {
        lock.lock()
        let handler = self.handler
        lock.unlock()
        handler?()
    }
}
