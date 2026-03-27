import Foundation

public enum HelperInstallState: String, Codable, Sendable, CaseIterable {
    case notInstalled
    case installedButNotBootstrapped
    case bootstrapped
    case xpcReachable
    case permissionMismatch
    case versionMismatch
}

public struct HelperInstallStatus: Codable, Sendable, Equatable {
    public var state: HelperInstallState
    public var serviceName: String
    public var helperPath: String
    public var plistPath: String
    public var helperVersion: String?
    public var expectedVersion: String?
    public var reason: String
    public var checkedAt: Date

    public init(
        state: HelperInstallState,
        serviceName: String,
        helperPath: String,
        plistPath: String,
        helperVersion: String? = nil,
        expectedVersion: String? = nil,
        reason: String,
        checkedAt: Date = .now
    ) {
        self.state = state
        self.serviceName = serviceName
        self.helperPath = helperPath
        self.plistPath = plistPath
        self.helperVersion = helperVersion
        self.expectedVersion = expectedVersion
        self.reason = reason
        self.checkedAt = checkedAt
    }

    public var installationSupport: CapabilitySupport {
        switch state {
        case .notInstalled, .installedButNotBootstrapped, .permissionMismatch, .versionMismatch:
            return .readOnlyFallback
        case .bootstrapped, .xpcReachable:
            return .supported
        }
    }

    public var privilegeSupport: CapabilitySupport {
        switch state {
        case .permissionMismatch:
            return .readOnlyFallback
        case .xpcReachable:
            return .supported
        case .notInstalled, .installedButNotBootstrapped, .bootstrapped, .versionMismatch:
            return .readOnlyFallback
        }
    }

    public var privilegeReason: String {
        switch state {
        case .permissionMismatch:
            return reason
        case .xpcReachable:
            return "helper가 root 권한으로 동작 중입니다."
        case .bootstrapped:
            return "helper가 등록되었지만 XPC로 확인되기 전입니다."
        case .notInstalled, .installedButNotBootstrapped, .versionMismatch:
            return reason
        }
    }
}
