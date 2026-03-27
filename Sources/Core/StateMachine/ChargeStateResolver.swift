import Foundation
import Shared

public struct ChargeStateResolution: Sendable, Equatable {
    public var state: ChargeState
    public var reason: ChargeTransitionReason
    public var selectedBattery: BatterySnapshot?

    public init(
        state: ChargeState,
        reason: ChargeTransitionReason,
        selectedBattery: BatterySnapshot?
    ) {
        self.state = state
        self.reason = reason
        self.selectedBattery = selectedBattery
    }
}

public struct ChargeStateResolver: Sendable {
    public typealias SnapshotSelectionHook = @Sendable ([BatterySnapshot]) -> BatterySnapshot?

    private let selectSnapshot: SnapshotSelectionHook

    public init(
        selectSnapshot: @escaping SnapshotSelectionHook = Self.selectPreferredSnapshot(from:)
    ) {
        self.selectSnapshot = selectSnapshot
    }

    public func resolve(
        context: ChargeStateContext,
        effectivePolicy: EffectiveChargePolicy
    ) -> ChargeStateResolution {
        let selectedBattery = selectSnapshot(context.snapshotCandidates)

        guard let battery = selectedBattery, battery.isBatteryPresent else {
            return ChargeStateResolution(
                state: .suspended,
                reason: .missingBattery,
                selectedBattery: selectedBattery
            )
        }

        if context.controllerStatus.helperConnection != .connected || context.controllerStatus.lastErrorDescription != nil {
            return ChargeStateResolution(
                state: .errorReadOnly,
                reason: .helperFailure,
                selectedBattery: battery
            )
        }

        if context.controllerStatus.mode != .fullControl || !effectivePolicy.isControlEnabled {
            return ChargeStateResolution(
                state: .suspended,
                reason: .controlSuspended,
                selectedBattery: battery
            )
        }

        if effectivePolicy.isTemporaryOverrideActive
            || (context.controllerStatus.temporaryOverrideUntil.map { $0 > context.now } ?? false) {
            return ChargeStateResolution(
                state: .temporaryOverride,
                reason: .temporaryOverride,
                selectedBattery: battery
            )
        }

        if battery.chargePercent >= effectivePolicy.upperLimit {
            return ChargeStateResolution(
                state: .holdingAtLimit,
                reason: .atUpperLimit,
                selectedBattery: battery
            )
        }

        if battery.chargePercent <= effectivePolicy.rechargeThreshold {
            return ChargeStateResolution(
                state: .charging,
                reason: .belowRechargeThreshold,
                selectedBattery: battery
            )
        }

        return ChargeStateResolution(
            state: .waitingForRecharge,
            reason: .waitingWithinPolicyBand,
            selectedBattery: battery
        )
    }

    public static func selectPreferredSnapshot(from snapshots: [BatterySnapshot]) -> BatterySnapshot? {
        snapshots.max { lhs, rhs in
            let lhsRank = sourceRank(lhs.source)
            let rhsRank = sourceRank(rhs.source)

            if lhsRank == rhsRank {
                return lhs.observedAt < rhs.observedAt
            }

            return lhsRank < rhsRank
        }
    }

    private static func sourceRank(_ source: BatterySnapshot.Source) -> Int {
        switch source {
        case .system:
            return 3
        case .helper:
            return 2
        case .cached:
            return 1
        }
    }
}
