import Foundation

public struct BatterySnapshot: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable, CaseIterable {
        case system
        case helper
        case cached
    }

    public var chargePercent: Int
    public var isPowerConnected: Bool
    public var isCharging: Bool
    public var isBatteryPresent: Bool
    public var observedAt: Date
    public var source: Source
    /// macOS가 배터리 게이지 보정을 위해 충전 한도를 무시하고 완충 중인지. 확인하지 않았거나 읽지 못하면 nil.
    public var isSystemFullChargeActive: Bool?

    public init(
        chargePercent: Int,
        isPowerConnected: Bool,
        isCharging: Bool,
        isBatteryPresent: Bool = true,
        observedAt: Date = .now,
        source: Source = .system,
        isSystemFullChargeActive: Bool? = nil
    ) {
        self.chargePercent = chargePercent
        self.isPowerConnected = isPowerConnected
        self.isCharging = isCharging
        self.isBatteryPresent = isBatteryPresent
        self.observedAt = observedAt
        self.source = source
        self.isSystemFullChargeActive = isSystemFullChargeActive
    }
}
