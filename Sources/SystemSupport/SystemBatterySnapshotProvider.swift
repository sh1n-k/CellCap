import Foundation
import IOKit.ps
import Shared

public protocol BatterySnapshotProviding: Sendable {
    func currentSnapshot(now: Date) throws -> BatterySnapshot?
}

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
    private let fullChargeStateReader: (any SystemFullChargeStateReading)?

    /// `fullChargeStateReader`가 nil이면 보정 완충 상태를 확인하지 않는다(helper).
    public init(
        readingProvider: any PowerSourceReadingProviding = IOKitPowerSourceReadingProvider(),
        translator: any BatterySnapshotTranslating = BatterySnapshotTranslator(),
        fullChargeStateReader: (any SystemFullChargeStateReading)? = nil
    ) {
        self.readingProvider = readingProvider
        self.translator = translator
        self.fullChargeStateReader = fullChargeStateReader
    }

    public func currentSnapshot(now: Date) throws -> BatterySnapshot? {
        guard let reading = try readingProvider.readPowerSource(now: now) else {
            return nil
        }

        var snapshot = translator.translate(reading, observedAt: now, source: .system)
        snapshot.isSystemFullChargeActive = fullChargeStateReader?.isFullChargeRequested()
        return snapshot
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
