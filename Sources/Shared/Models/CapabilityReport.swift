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
    case helperInstallation
    case helperPrivilege
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
    public var helperInstallStatus: HelperInstallStatus?

    public init(
        statuses: [CapabilityStatus],
        recommendedControllerMode: ControllerStatus.Mode,
        helperInstallStatus: HelperInstallStatus? = nil
    ) {
        self.statuses = statuses
        self.recommendedControllerMode = recommendedControllerMode
        self.helperInstallStatus = helperInstallStatus
    }

    public func status(for key: CapabilityKey) -> CapabilityStatus? {
        statuses.first { $0.key == key }
    }

    public func replacingStatus(
        for key: CapabilityKey,
        support: CapabilitySupport,
        reason: String
    ) -> CapabilityReport {
        var updatedStatuses = statuses
        let updatedStatus = CapabilityStatus(key: key, support: support, reason: reason)

        if let index = updatedStatuses.firstIndex(where: { $0.key == key }) {
            updatedStatuses[index] = updatedStatus
        } else {
            updatedStatuses.append(updatedStatus)
        }

        return CapabilityReport(
            statuses: updatedStatuses,
            recommendedControllerMode: recommendedControllerMode,
            helperInstallStatus: helperInstallStatus
        )
    }

    public func replacingHelperInstallStatus(_ helperInstallStatus: HelperInstallStatus?) -> CapabilityReport {
        CapabilityReport(
            statuses: statuses,
            recommendedControllerMode: recommendedControllerMode,
            helperInstallStatus: helperInstallStatus
        )
    }

    public func replacingRecommendedControllerMode(_ mode: ControllerStatus.Mode) -> CapabilityReport {
        CapabilityReport(
            statuses: statuses,
            recommendedControllerMode: mode,
            helperInstallStatus: helperInstallStatus
        )
    }
}
