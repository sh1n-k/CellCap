import Foundation
import Shared

public protocol HelperCapabilityProbing: Sendable {
    func capabilityProbe() async throws -> HelperCapabilityProbeSummary
}

public actor XPCChargeController: ChargeController, HelperCapabilityProbing {
    private let transport: any HelperServiceTransporting

    public init(transport: any HelperServiceTransporting = NSXPCHelperServiceTransport()) {
        self.transport = transport
    }

    public func setChargingEnabled(_ enabled: Bool) async throws {
        _ = try await transport.setChargingEnabled(enabled)
    }

    public func setTemporaryOverride(until: Date?) async throws {
        _ = try await transport.setTemporaryOverride(until: until)
    }

    public func getControllerStatus() async -> ControllerStatus {
        do {
            return try await transport.fetchControllerStatus()
        } catch let error as HelperTransportError {
            return ControllerStatus(
                mode: error.suggestedFallbackMode,
                helperConnection: .disconnected,
                isChargingEnabled: nil,
                temporaryOverrideUntil: nil,
                lastErrorDescription: error.failureReason ?? error.message,
                checkedAt: .now
            )
        } catch {
            return ControllerStatus(
                mode: .readOnly,
                helperConnection: .disconnected,
                isChargingEnabled: nil,
                temporaryOverrideUntil: nil,
                lastErrorDescription: error.localizedDescription,
                checkedAt: .now
            )
        }
    }

    public func selfTest() async -> ControllerSelfTestResult {
        do {
            return try await transport.selfTest().result
        } catch let error as HelperTransportError {
            return ControllerSelfTestResult(
                outcome: .failed,
                message: error.failureReason ?? error.message,
                checkedAt: .now
            )
        } catch {
            return ControllerSelfTestResult(
                outcome: .failed,
                message: error.localizedDescription,
                checkedAt: .now
            )
        }
    }

    public func capabilityProbe() async throws -> HelperCapabilityProbeSummary {
        try await transport.capabilityProbe()
    }
}
