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

    public init(
        chargePercent: Int,
        isPowerConnected: Bool,
        isCharging: Bool,
        isBatteryPresent: Bool = true,
        observedAt: Date = .now,
        source: Source = .system
    ) {
        self.chargePercent = chargePercent
        self.isPowerConnected = isPowerConnected
        self.isCharging = isCharging
        self.isBatteryPresent = isBatteryPresent
        self.observedAt = observedAt
        self.source = source
    }
}
