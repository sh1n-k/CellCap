import Foundation

public enum CapabilitySupport: String, Codable, Sendable, CaseIterable {
    case supported
    case unsupported
    case experimental
    case readOnlyFallback
}

public enum CapabilityKey: String, Codable, Sendable, CaseIterable {
    case appleSilicon
    case macOSVersion
    case batteryObservation
    case powerSourceObservation
    case sleepWakeResynchronization
    case chargeControl
}

public struct CapabilityStatus: Codable, Sendable, Equatable {
    public var key: CapabilityKey
    public var support: CapabilitySupport
    public var reason: String

    public init(key: CapabilityKey, support: CapabilitySupport, reason: String) {
        self.key = key
        self.support = support
        self.reason = reason
    }
}

public struct CapabilityReport: Codable, Sendable, Equatable {
    public var statuses: [CapabilityStatus]
    public var recommendedControllerMode: ControllerStatus.Mode

    public init(
        statuses: [CapabilityStatus],
        recommendedControllerMode: ControllerStatus.Mode
    ) {
        self.statuses = statuses
        self.recommendedControllerMode = recommendedControllerMode
    }

    public func status(for key: CapabilityKey) -> CapabilityStatus? {
        statuses.first { $0.key == key }
    }
}
