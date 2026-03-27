import Foundation

public enum DiagnosticLogLevel: String, Codable, Sendable, CaseIterable {
    case info
    case notice
    case warning
    case error
}

public enum DiagnosticEventCategory: String, Codable, Sendable, CaseIterable {
    case policyChanged
    case stateTransition
    case helperCommunication
    case capabilityProbe
    case selfTest
    case runtime
    case export
}

public struct DiagnosticEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var timestamp: Date
    public var level: DiagnosticLogLevel
    public var category: DiagnosticEventCategory
    public var message: String
    public var details: [String: String]
    public var userFacingSummary: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        level: DiagnosticLogLevel,
        category: DiagnosticEventCategory,
        message: String,
        details: [String: String] = [:],
        userFacingSummary: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.details = details
        self.userFacingSummary = userFacingSummary
    }
}
