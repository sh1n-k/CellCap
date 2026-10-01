import Foundation
import Shared

/// 기기에 남아 있는 충전 제어 경로에 따라 backend를 고른다.
/// - SMC 충전 키(`CHTE` 또는 `CH0B`+`CH0C`)가 있으면 직접 SMC backend
/// - 키가 없고 macOS 충전 한도 설정이 있으면 충전 한도 backend
/// 판정은 처음 필요할 때 하고, 확정된 결과만 helper 수명 동안 유지한다.
/// SMC 읽기 실패나 두 경로 모두 없는 경우는 확정하지 않아 다음 호출에서 다시 판정한다.
actor ChargeControlBackendSelector: ChargeControlBackend {
    private let bridge: any SMCBridgeReading
    private let chargeLimitStore: any ChargeLimitStoring
    private let directBackend: any ChargeControlBackend
    private let chargeLimitBackend: any ChargeControlBackend
    private var selectedBackend: (any ChargeControlBackend)?

    init(
        bridge: any SMCBridgeReading = SystemSMCBridge(),
        chargeLimitStore: any ChargeLimitStoring = CFPreferencesChargeLimitStore(),
        directBackend: (any ChargeControlBackend)? = nil,
        chargeLimitBackend: (any ChargeControlBackend)? = nil
    ) {
        self.bridge = bridge
        self.chargeLimitStore = chargeLimitStore
        self.directBackend = directBackend ?? DirectSMCChargeControlBackend(bridge: bridge)
        self.chargeLimitBackend = chargeLimitBackend ?? ManagedChargeLimitBackend(store: chargeLimitStore)
    }

    func probe(snapshot: BatterySnapshot?, now: Date) async -> ChargeControlCapability {
        await resolveBackend().probe(snapshot: snapshot, now: now)
    }

    func currentStatus(now: Date) async -> ChargeControlRuntimeStatus {
        await resolveBackend().currentStatus(now: now)
    }

    func setChargingEnabled(_ enabled: Bool, now: Date) async throws -> ChargeControlRuntimeStatus {
        try await resolveBackend().setChargingEnabled(enabled, now: now)
    }

    func setTemporaryOverride(until: Date?, now: Date) async throws -> ChargeControlRuntimeStatus {
        try await resolveBackend().setTemporaryOverride(until: until, now: now)
    }

    func selfTest(snapshot: BatterySnapshot?, now: Date) async -> ControllerSelfTestResult {
        await resolveBackend().selfTest(snapshot: snapshot, now: now)
    }

    private func resolveBackend() -> any ChargeControlBackend {
        if let selectedBackend {
            return selectedBackend
        }

        guard let status = try? bridge.readStatus() else {
            return directBackend
        }
        if status.legacyChargingKeysAvailable || status.tahoeChargingKeyAvailable {
            selectedBackend = directBackend
            return directBackend
        }
        if chargeLimitStore.isAvailable() {
            selectedBackend = chargeLimitBackend
            return chargeLimitBackend
        }
        return directBackend
    }
}
