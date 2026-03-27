import Foundation

public struct ControllerStatus: Codable, Sendable, Equatable {
    public enum Mode: String, Codable, Sendable, CaseIterable {
        case fullControl
        case readOnly
        case monitoringOnly
    }

    public enum HelperConnection: String, Codable, Sendable, CaseIterable {
        case connected
        case disconnected
        case unavailable
    }

    public var mode: Mode
    public var helperConnection: HelperConnection
    public var isChargingEnabled: Bool?
    public var temporaryOverrideUntil: Date?
    public var lastErrorDescription: String?
    public var checkedAt: Date

    public init(
        mode: Mode,
        helperConnection: HelperConnection,
        isChargingEnabled: Bool? = nil,
        temporaryOverrideUntil: Date? = nil,
        lastErrorDescription: String? = nil,
        checkedAt: Date = .now
    ) {
        self.mode = mode
        self.helperConnection = helperConnection
        self.isChargingEnabled = isChargingEnabled
        self.temporaryOverrideUntil = temporaryOverrideUntil
        self.lastErrorDescription = lastErrorDescription
        self.checkedAt = checkedAt
    }

    public var isOperational: Bool {
        helperConnection == .connected && lastErrorDescription == nil
    }
}

public struct ControllerSelfTestResult: Codable, Sendable, Equatable {
    public enum Outcome: String, Codable, Sendable, CaseIterable {
        case passed
        case degraded
        case failed
    }

    public var outcome: Outcome
    public var message: String
    public var checkedAt: Date

    public init(outcome: Outcome, message: String, checkedAt: Date = .now) {
        self.outcome = outcome
        self.message = message
        self.checkedAt = checkedAt
    }
}
