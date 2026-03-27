import Core
import Foundation
import Shared
import Testing

@Test
func capabilityCheckerReturnsReadOnlyForSupportedMonitoringEnvironment() {
    let checker = CapabilityChecker(
        environment: MockSystemEnvironmentProvider(
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
            isAppleSilicon: true
        )
    )

    let report = checker.evaluate(
        snapshot: BatterySnapshot(
            chargePercent: 70,
            isPowerConnected: true,
            isCharging: false,
            isBatteryPresent: true
        )
    )

    #expect(report.recommendedControllerMode == .readOnly)
    #expect(report.status(for: .batteryObservation)?.support == .supported)
    #expect(report.status(for: .chargeControl)?.support == .experimental)
}

@Test
func capabilityCheckerFallsBackToMonitoringOnlyWithoutBattery() {
    let checker = CapabilityChecker(
        environment: MockSystemEnvironmentProvider(
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0),
            isAppleSilicon: true
        )
    )

    let report = checker.evaluate(snapshot: nil)

    #expect(report.recommendedControllerMode == .monitoringOnly)
    #expect(report.status(for: .batteryObservation)?.support == .unsupported)
    #expect(report.status(for: .powerSourceObservation)?.support == .readOnlyFallback)
}

@Test
func capabilityCheckerRejectsUnsupportedArchitecture() {
    let checker = CapabilityChecker(
        environment: MockSystemEnvironmentProvider(
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
            isAppleSilicon: false
        )
    )

    let report = checker.evaluate(
        snapshot: BatterySnapshot(
            chargePercent: 60,
            isPowerConnected: true,
            isCharging: false,
            isBatteryPresent: true
        )
    )

    #expect(report.status(for: .appleSilicon)?.support == .unsupported)
    #expect(report.recommendedControllerMode == .monitoringOnly)
}

@Test
func capabilityCheckerRejectsUnsupportedOSVersion() {
    let checker = CapabilityChecker(
        environment: MockSystemEnvironmentProvider(
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 6, patchVersion: 0),
            isAppleSilicon: true
        )
    )

    let report = checker.evaluate(
        snapshot: BatterySnapshot(
            chargePercent: 60,
            isPowerConnected: true,
            isCharging: false,
            isBatteryPresent: true
        )
    )

    #expect(report.status(for: .macOSVersion)?.support == .unsupported)
    #expect(report.status(for: .chargeControl)?.support == .readOnlyFallback)
    #expect(report.recommendedControllerMode == .monitoringOnly)
}

private struct MockSystemEnvironmentProvider: SystemEnvironmentProviding {
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
