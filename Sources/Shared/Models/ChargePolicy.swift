import Foundation

public struct ChargePolicy: Codable, Sendable, Equatable {
    public static let defaultUpperLimit = 80
    public static let minimumUpperLimit = 50
    public static let maximumUpperLimit = 100

    public var upperLimit: Int
    public var rechargeThreshold: Int
    public var temporaryOverrideUntil: Date?
    public var isControlEnabled: Bool

    public init(
        upperLimit: Int = ChargePolicy.defaultUpperLimit,
        rechargeThreshold: Int? = nil,
        temporaryOverrideUntil: Date? = nil,
        isControlEnabled: Bool = true
    ) {
        self.upperLimit = upperLimit
        self.rechargeThreshold = rechargeThreshold ?? max(0, upperLimit - 5)
        self.temporaryOverrideUntil = temporaryOverrideUntil
        self.isControlEnabled = isControlEnabled
    }

    public var isWithinSupportedRange: Bool {
        (Self.minimumUpperLimit...Self.maximumUpperLimit).contains(upperLimit)
            && (0...upperLimit).contains(rechargeThreshold)
    }

    public func isTemporaryOverrideActive(at date: Date) -> Bool {
        guard let temporaryOverrideUntil else { return false }
        return temporaryOverrideUntil > date
    }
}
