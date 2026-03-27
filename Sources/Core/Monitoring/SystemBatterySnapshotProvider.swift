import Foundation
import IOKit.ps
import Shared

public struct PowerSourceReading: Sendable, Equatable {
    public var chargePercent: Int
    public var isPowerConnected: Bool
    public var isCharging: Bool
    public var isBatteryPresent: Bool

    public init(
        chargePercent: Int,
        isPowerConnected: Bool,
        isCharging: Bool,
        isBatteryPresent: Bool
    ) {
        self.chargePercent = chargePercent
        self.isPowerConnected = isPowerConnected
        self.isCharging = isCharging
        self.isBatteryPresent = isBatteryPresent
    }
}

public enum PowerSourceReadingProviderError: Error, Equatable {
    case unavailableSnapshot
    case invalidPowerSourceDescription
}

public protocol PowerSourceReadingProviding: Sendable {
    func readPowerSource(now: Date) throws -> PowerSourceReading?
}

public protocol BatterySnapshotTranslating: Sendable {
    func translate(
        _ reading: PowerSourceReading,
        observedAt: Date,
        source: BatterySnapshot.Source
    ) -> BatterySnapshot
}

public struct BatterySnapshotTranslator: BatterySnapshotTranslating {
    public init() {}

    public func translate(
        _ reading: PowerSourceReading,
        observedAt: Date,
        source: BatterySnapshot.Source = .system
    ) -> BatterySnapshot {
        BatterySnapshot(
            chargePercent: min(100, max(0, reading.chargePercent)),
            isPowerConnected: reading.isPowerConnected,
            isCharging: reading.isCharging,
            isBatteryPresent: reading.isBatteryPresent,
            observedAt: observedAt,
            source: source
        )
    }
}

public struct SystemBatterySnapshotProvider: BatterySnapshotProviding {
    private let readingProvider: any PowerSourceReadingProviding
    private let translator: any BatterySnapshotTranslating

    public init(
        readingProvider: any PowerSourceReadingProviding = IOKitPowerSourceReadingProvider(),
        translator: any BatterySnapshotTranslating = BatterySnapshotTranslator()
    ) {
        self.readingProvider = readingProvider
        self.translator = translator
    }

    public func currentSnapshot(now: Date) throws -> BatterySnapshot? {
        guard let reading = try readingProvider.readPowerSource(now: now) else {
            return nil
        }

        return translator.translate(reading, observedAt: now, source: .system)
    }
}

public struct IOKitPowerSourceReadingProvider: PowerSourceReadingProviding {
    public init() {}

    public func readPowerSource(now: Date) throws -> PowerSourceReading? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            throw PowerSourceReadingProviderError.unavailableSnapshot
        }

        let powerSources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as NSArray
        let providingSourceType = IOPSGetProvidingPowerSourceType(snapshot).takeUnretainedValue() as String

        for powerSource in powerSources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, powerSource as CFTypeRef)?
                .takeUnretainedValue() as? [String: Any] else {
                continue
            }

            guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else {
                continue
            }

            let chargePercent = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            let isBatteryPresent = description[kIOPSIsPresentKey] as? Bool ?? true
            let state = description[kIOPSPowerSourceStateKey] as? String
            let isPowerConnected = state == kIOPSACPowerValue || providingSourceType != kIOPSBatteryPowerValue

            return PowerSourceReading(
                chargePercent: chargePercent,
                isPowerConnected: isPowerConnected,
                isCharging: isCharging,
                isBatteryPresent: isBatteryPresent
            )
        }

        return nil
    }
}
