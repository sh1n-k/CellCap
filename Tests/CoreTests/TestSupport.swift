import Core
import Foundation
@testable import Helper
import Shared
import SystemSupport

/// Shared test doubles for CoreTests. Intentionally non-private so files in this target can reuse them.
struct MockSystemEnvironmentProvider: SystemEnvironmentProviding {
    let operatingSystemVersion: OperatingSystemVersion
    let isAppleSiliconValue: Bool

    init(operatingSystemVersion: OperatingSystemVersion, isAppleSilicon: Bool) {
        self.operatingSystemVersion = operatingSystemVersion
        self.isAppleSiliconValue = isAppleSilicon
    }

    func isAppleSilicon() -> Bool {
        isAppleSiliconValue
    }
}

struct FixedDateProvider: DateProviding {
    let now: Date
}

final class SequenceDateProvider: @unchecked Sendable, DateProviding {
    private let lock = NSLock()
    private var dates: [Date]

    init(dates: [Date]) {
        self.dates = dates
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return dates.isEmpty ? .distantPast : dates.removeFirst()
    }
}

final class MockSMCBridge: @unchecked Sendable, SMCBridgeReading {
    var status: SMCBridgeStatus
    var postWriteStatus: SMCBridgeStatus?

    init(status: SMCBridgeStatus, postWriteStatus: SMCBridgeStatus? = nil) {
        self.status = status
        self.postWriteStatus = postWriteStatus
    }

    func readStatus() throws -> SMCBridgeStatus {
        postWriteStatus ?? status
    }

    func setChargingEnabled(_ enabled: Bool) throws {
        status.chargingEnabledKnown = true
        status.chargingEnabled = enabled
    }
}

struct MockPrivilegeProvider: HelperPrivilegeProviding {
    let hasWritePrivilegeValue: Bool

    init(hasWritePrivilege: Bool) {
        self.hasWritePrivilegeValue = hasWritePrivilege
    }

    func hasWritePrivilege() -> Bool {
        hasWritePrivilegeValue
    }
}

extension SMCBridgeStatus {
    static let capableChargingDisabled = SMCBridgeStatus(
        serviceAvailable: true,
        legacyChargingKeysAvailable: true,
        tahoeChargingKeyAvailable: false,
        adapterKeyAvailable: true,
        batteryChargeKeyAvailable: true,
        acPowerKeyAvailable: true,
        chargingEnabledKnown: true,
        chargingEnabled: false,
        externalPowerKnown: true,
        externalPowerConnected: true,
        batteryChargePercent: 82
    )
}
