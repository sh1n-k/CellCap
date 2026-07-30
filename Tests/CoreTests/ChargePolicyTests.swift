import Foundation
import Shared
import Testing

@Test
func defaultRechargeThresholdTracksUpperLimit() {
    let policy = ChargePolicy(upperLimit: 80)
    #expect(policy.rechargeThreshold == 75)
    #expect(policy.isWithinSupportedRange)
}

@Test
func temporaryOverrideDetectsFutureDeadline() {
    let future = Date(timeIntervalSince1970: 2_000)
    let policy = ChargePolicy(
        upperLimit: 85,
        rechargeThreshold: 80,
        temporaryOverrideUntil: future
    )

    #expect(policy.isTemporaryOverrideActive(at: Date(timeIntervalSince1970: 1_500)))
    #expect(!policy.isTemporaryOverrideActive(at: Date(timeIntervalSince1970: 2_500)))
}

@Test
func policyOutsideSupportedRangeIsRejectedByValidationHelper() {
    let tooLow = ChargePolicy(upperLimit: 40, rechargeThreshold: 30)
    let thresholdAboveLimit = ChargePolicy(upperLimit: 80, rechargeThreshold: 90)

    #expect(!tooLow.isWithinSupportedRange)
    #expect(!thresholdAboveLimit.isWithinSupportedRange)
}
