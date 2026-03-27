import Foundation

public struct DiagnosticsSummary: Codable, Sendable, Equatable {
    public var generatedAt: Date
    public var eventCount: Int
    public var currentChargeState: ChargeState?
    public var currentControllerMode: ControllerStatus.Mode?
    public var currentPolicyUpperLimit: Int?
    public var currentRechargeThreshold: Int?
    public var lastTransitionReason: String?
    public var lastCapabilityProbeMessage: String?
    public var lastCapabilityProbeAt: Date?
    public var lastSelfTestMessage: String?
    public var lastSelfTestAt: Date?
    public var lastReadOnlyFallbackReason: String?
    public var recentErrorMessages: [String]

    public init(
        generatedAt: Date = .now,
        eventCount: Int,
        currentChargeState: ChargeState?,
        currentControllerMode: ControllerStatus.Mode?,
        currentPolicyUpperLimit: Int?,
        currentRechargeThreshold: Int?,
        lastTransitionReason: String?,
        lastCapabilityProbeMessage: String?,
        lastCapabilityProbeAt: Date?,
        lastSelfTestMessage: String?,
        lastSelfTestAt: Date?,
        lastReadOnlyFallbackReason: String?,
        recentErrorMessages: [String]
    ) {
        self.generatedAt = generatedAt
        self.eventCount = eventCount
        self.currentChargeState = currentChargeState
        self.currentControllerMode = currentControllerMode
        self.currentPolicyUpperLimit = currentPolicyUpperLimit
        self.currentRechargeThreshold = currentRechargeThreshold
        self.lastTransitionReason = lastTransitionReason
        self.lastCapabilityProbeMessage = lastCapabilityProbeMessage
        self.lastCapabilityProbeAt = lastCapabilityProbeAt
        self.lastSelfTestMessage = lastSelfTestMessage
        self.lastSelfTestAt = lastSelfTestAt
        self.lastReadOnlyFallbackReason = lastReadOnlyFallbackReason
        self.recentErrorMessages = recentErrorMessages
    }
}
