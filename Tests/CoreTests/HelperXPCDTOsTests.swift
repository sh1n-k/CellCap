import Foundation
import Shared
import Testing

struct HelperXPCDTOsTests {
    @Test
    func requestDTOsExplicitlySupportSecureCoding() {
        #expect(HelperSelfTestRequestDTO.supportsSecureCoding)
        #expect(HelperCapabilityProbeRequestDTO.supportsSecureCoding)
        #expect(HelperSetChargingEnabledRequestDTO.supportsSecureCoding)
        #expect(HelperSetTemporaryOverrideRequestDTO.supportsSecureCoding)
    }

    @Test
    func selfTestRequestRoundTripsThroughSecureCoding() throws {
        let requestedAt = Date(timeIntervalSince1970: 1_717_171_717)
        let original = HelperSelfTestRequestDTO(requestedAt: requestedAt)

        let archived = try NSKeyedArchiver.archivedData(withRootObject: original, requiringSecureCoding: true)
        let unarchived = try NSKeyedUnarchiver.unarchivedObject(ofClass: HelperSelfTestRequestDTO.self, from: archived)
        let decoded = try #require(unarchived)

        #expect(decoded.requestedAt == requestedAt)
    }

    @Test
    func capabilityProbeRequestRoundTripsThroughSecureCoding() throws {
        let requestedAt = Date(timeIntervalSince1970: 1_818_181_818)
        let original = HelperCapabilityProbeRequestDTO(requestedAt: requestedAt)

        let archived = try NSKeyedArchiver.archivedData(withRootObject: original, requiringSecureCoding: true)
        let unarchived = try NSKeyedUnarchiver.unarchivedObject(ofClass: HelperCapabilityProbeRequestDTO.self, from: archived)
        let decoded = try #require(unarchived)

        #expect(decoded.requestedAt == requestedAt)
    }

    @Test
    func commandRequestsRoundTripThroughSecureCoding() throws {
        let requestedAt = Date(timeIntervalSince1970: 1_919_191_919)
        let chargingRequest = HelperSetChargingEnabledRequestDTO(enabled: false, requestedAt: requestedAt)
        let overrideUntil = Date(timeIntervalSince1970: 2_020_202_020)
        let overrideRequest = HelperSetTemporaryOverrideRequestDTO(until: overrideUntil, requestedAt: requestedAt)

        let chargingArchived = try NSKeyedArchiver.archivedData(withRootObject: chargingRequest, requiringSecureCoding: true)
        let chargingUnarchived = try NSKeyedUnarchiver.unarchivedObject(ofClass: HelperSetChargingEnabledRequestDTO.self, from: chargingArchived)
        let chargingDecoded = try #require(chargingUnarchived)
        #expect(chargingDecoded.enabled == false)
        #expect(chargingDecoded.requestedAt == requestedAt)

        let overrideArchived = try NSKeyedArchiver.archivedData(withRootObject: overrideRequest, requiringSecureCoding: true)
        let overrideUnarchived = try NSKeyedUnarchiver.unarchivedObject(ofClass: HelperSetTemporaryOverrideRequestDTO.self, from: overrideArchived)
        let overrideDecoded = try #require(overrideUnarchived)
        #expect(overrideDecoded.until == overrideUntil)
        #expect(overrideDecoded.requestedAt == requestedAt)
    }
}
