import Foundation
import Shared

public actor MockChargeController: ChargeController {
    public enum Command: Equatable, Sendable {
        case setChargingEnabled(Bool)
        case setTemporaryOverride(Date?)
    }

    private var status: ControllerStatus
    private var selfTestResult: ControllerSelfTestResult
    private var commands: [Command]

    public init(
        initialStatus: ControllerStatus = ControllerStatus(
            mode: .readOnly,
            helperConnection: .unavailable,
            isChargingEnabled: nil,
            temporaryOverrideUntil: nil,
            lastErrorDescription: "Mock controller not configured."
        ),
        selfTestResult: ControllerSelfTestResult = ControllerSelfTestResult(
            outcome: .degraded,
            message: "Mock self-test placeholder."
        ),
        commands: [Command] = []
    ) {
        self.status = initialStatus
        self.selfTestResult = selfTestResult
        self.commands = commands
    }

    public func setChargingEnabled(_ enabled: Bool) async throws {
        commands.append(.setChargingEnabled(enabled))
        status.isChargingEnabled = enabled
        status.lastErrorDescription = nil
        status.checkedAt = .now
    }

    public func setTemporaryOverride(until: Date?) async throws {
        commands.append(.setTemporaryOverride(until))
        status.temporaryOverrideUntil = until
        status.lastErrorDescription = nil
        status.checkedAt = .now
    }

    public func getControllerStatus() async -> ControllerStatus {
        status
    }

    public func selfTest() async -> ControllerSelfTestResult {
        selfTestResult
    }

    public func recordedCommands() -> [Command] {
        commands
    }

    public func updateStatus(_ newStatus: ControllerStatus) {
        status = newStatus
    }

    public func updateSelfTestResult(_ newResult: ControllerSelfTestResult) {
        selfTestResult = newResult
    }
}
