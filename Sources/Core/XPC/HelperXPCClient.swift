import Foundation
import Shared

public struct HelperSelfTestSummary: Sendable, Equatable {
    public var result: ControllerSelfTestResult
    public var controllerStatus: ControllerStatus

    public init(result: ControllerSelfTestResult, controllerStatus: ControllerStatus) {
        self.result = result
        self.controllerStatus = controllerStatus
    }
}

public struct HelperCapabilityProbeSummary: Sendable, Equatable {
    public var report: CapabilityReport
    public var controllerStatus: ControllerStatus

    public init(report: CapabilityReport, controllerStatus: ControllerStatus) {
        self.report = report
        self.controllerStatus = controllerStatus
    }
}

public struct HelperTransportError: Error, Sendable, Equatable {
    public var domain: String
    public var code: String
    public var message: String
    public var suggestedFallbackMode: ControllerStatus.Mode
    public var failureReason: String?

    public init(
        domain: String,
        code: String,
        message: String,
        suggestedFallbackMode: ControllerStatus.Mode,
        failureReason: String? = nil
    ) {
        self.domain = domain
        self.code = code
        self.message = message
        self.suggestedFallbackMode = suggestedFallbackMode
        self.failureReason = failureReason
    }

    static func connectionFailure(_ message: String) -> HelperTransportError {
        HelperTransportError(
            domain: "CellCap.XPC",
            code: "connection_failure",
            message: message,
            suggestedFallbackMode: .readOnly
        )
    }

    static func fromDTO(_ dto: HelperXPCErrorDTO) -> HelperTransportError {
        HelperTransportError(
            domain: dto.domain,
            code: dto.code,
            message: dto.message,
            suggestedFallbackMode: ControllerStatus.Mode(rawValue: dto.suggestedFallbackModeRawValue) ?? .readOnly,
            failureReason: dto.failureReason
        )
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

    public init(serviceName: String = CellCapHelperXPC.serviceName) {
        self.serviceName = serviceName
    }

    public func fetchControllerStatus() async throws -> ControllerStatus {
        try await withConnection { proxy, finish in
            let request = HelperRequestDTO()
            proxy.fetchControllerStatus(request) { response in
                if let error = response.error {
                    finish(.failure(HelperTransportError.fromDTO(error)))
                    return
                }

                finish(.success(response.controllerStatus.toDomain()))
            }
        }
    }

    public func selfTest() async throws -> HelperSelfTestSummary {
        try await withConnection { proxy, finish in
            let request = HelperSelfTestRequestDTO()
            proxy.selfTest(request) { response in
                if let error = response.error {
                    finish(.failure(HelperTransportError.fromDTO(error)))
                    return
                }

                finish(
                    .success(
                        HelperSelfTestSummary(
                            result: response.result.toDomain(),
                            controllerStatus: response.controllerStatus.toDomain()
                        )
                    )
                )
            }
        }
    }

    public func capabilityProbe() async throws -> HelperCapabilityProbeSummary {
        try await withConnection { proxy, finish in
            let request = HelperCapabilityProbeRequestDTO()
            proxy.capabilityProbe(request) { response in
                if let error = response.error {
                    finish(.failure(HelperTransportError.fromDTO(error)))
                    return
                }

                finish(
                    .success(
                        HelperCapabilityProbeSummary(
                            report: response.capabilityReport.toDomain(),
                            controllerStatus: response.controllerStatus.toDomain()
                        )
                    )
                )
            }
        }
    }

    public func setChargingEnabled(_ enabled: Bool) async throws -> ControllerStatus {
        try await withConnection { proxy, finish in
            let request = HelperSetChargingEnabledRequestDTO(enabled: enabled)
            proxy.setChargingEnabled(request) { response in
                if let error = response.error {
                    finish(.failure(HelperTransportError.fromDTO(error)))
                    return
                }

                finish(.success(response.controllerStatus.toDomain()))
            }
        }
    }

    public func setTemporaryOverride(until: Date?) async throws -> ControllerStatus {
        try await withConnection { proxy, finish in
            let request = HelperSetTemporaryOverrideRequestDTO(until: until)
            proxy.setTemporaryOverride(request) { response in
                if let error = response.error {
                    finish(.failure(HelperTransportError.fromDTO(error)))
                    return
                }

                finish(.success(response.controllerStatus.toDomain()))
            }
        }
    }

    private func withConnection<T: Sendable>(
        _ body: @escaping (CellCapHelperXPCProtocol, @escaping (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ContinuationGate(continuation: continuation)
            let connection = NSXPCConnection(machServiceName: serviceName, options: [])
            connection.remoteObjectInterface = CellCapHelperXPC.makeRemoteInterface()
            connection.invalidationHandler = {
                gate.resume(with: .failure(HelperTransportError.connectionFailure("XPC 연결이 무효화되었습니다.")))
            }
            connection.interruptionHandler = {
                gate.resume(with: .failure(HelperTransportError.connectionFailure("XPC 연결이 중단되었습니다.")))
            }
            connection.resume()

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                connection.invalidate()
                gate.resume(with: .failure(
                    HelperTransportError(
                        domain: "CellCap.XPC",
                        code: "proxy_error",
                        message: "remoteObjectProxy 호출이 실패했습니다.",
                        suggestedFallbackMode: .readOnly,
                        failureReason: error.localizedDescription
                    )
                ))
            }) as? CellCapHelperXPCProtocol else {
                connection.invalidate()
                gate.resume(with: .failure(HelperTransportError.connectionFailure("XPC 프록시를 생성하지 못했습니다.")))
                return
            }

            body(proxy) { result in
                connection.invalidate()
                gate.resume(with: result)
            }
        }
    }
}

private final class ContinuationGate<T: Sendable> {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<T, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(with: result)
    }
}
