@testable import Helper
import Foundation
import Shared
import SystemSupport
import Testing

@Test
func chargeLimitBackendHoldsAtCurrentChargeWhenChargingIsDisabled() async throws {
    let store = MockChargeLimitStore(limit: 80)
    let baseline = MockChargeLimitBaselineStore()
    let backend = makeChargeLimitBackend(store: store, baseline: baseline, chargePercent: 77)

    let status = try await backend.setChargingEnabled(false, now: Date(timeIntervalSince1970: 100))

    #expect(status.isChargingEnabled == false)
    #expect(store.limit == 77)
    #expect(baseline.baseline == 80)
}

@Test
func chargeLimitBackendReleasesLimitWhenChargingIsEnabled() async throws {
    let store = MockChargeLimitStore(limit: 70)
    let backend = makeChargeLimitBackend(store: store, chargePercent: 70)

    let status = try await backend.setChargingEnabled(true, now: Date(timeIntervalSince1970: 100))

    #expect(status.isChargingEnabled == true)
    #expect(store.limit == ManagedChargeLimitBackend.releasedLimit)
}

@Test
func chargeLimitBackendKeepsFirstBaselineAcrossCommands() async throws {
    let store = MockChargeLimitStore(limit: 85)
    let baseline = MockChargeLimitBaselineStore()
    let backend = makeChargeLimitBackend(store: store, baseline: baseline, chargePercent: 60)

    _ = try await backend.setChargingEnabled(false, now: Date(timeIntervalSince1970: 100))
    _ = try await backend.setChargingEnabled(true, now: Date(timeIntervalSince1970: 101))

    #expect(baseline.baseline == 85)
}

@Test
func chargeLimitBackendClampsHoldLimitToMinimum() {
    #expect(ManagedChargeLimitBackend.holdLimit(for: 5) == ManagedChargeLimitBackend.minimumHoldLimit)
    #expect(ManagedChargeLimitBackend.holdLimit(for: 64) == 64)
    #expect(ManagedChargeLimitBackend.holdLimit(for: 100) == 100)
}

@Test
func chargeLimitBackendRatchetsHoldLimitDownWhenChargeDrops() async throws {
    let store = MockChargeLimitStore(limit: 80)
    let snapshots = MockChargePercentProvider(chargePercent: 75)
    let backend = makeChargeLimitBackend(store: store, snapshots: snapshots)

    _ = try await backend.setChargingEnabled(false, now: Date(timeIntervalSince1970: 100))
    snapshots.chargePercent = 68
    let status = await backend.currentStatus(now: Date(timeIntervalSince1970: 200))

    #expect(store.limit == 68)
    #expect(status.isChargingEnabled == false)
    #expect(status.lastErrorDescription == nil)
}

@Test
func chargeLimitBackendDoesNotRaiseHoldLimitWhenChargeIncreases() async throws {
    let store = MockChargeLimitStore(limit: 80)
    let snapshots = MockChargePercentProvider(chargePercent: 70)
    let backend = makeChargeLimitBackend(store: store, snapshots: snapshots)

    _ = try await backend.setChargingEnabled(false, now: Date(timeIntervalSince1970: 100))
    snapshots.chargePercent = 72
    _ = await backend.currentStatus(now: Date(timeIntervalSince1970: 200))

    #expect(store.limit == 70)
}

@Test
func chargeLimitBackendDoesNotRatchetWhileChargingIsAllowedOrOverridden() async throws {
    let store = MockChargeLimitStore(limit: 80)
    let snapshots = MockChargePercentProvider(chargePercent: 70)
    let backend = makeChargeLimitBackend(store: store, snapshots: snapshots)

    _ = try await backend.setChargingEnabled(false, now: Date(timeIntervalSince1970: 100))
    _ = try await backend.setTemporaryOverride(until: Date(timeIntervalSince1970: 1_000), now: Date(timeIntervalSince1970: 101))
    snapshots.chargePercent = 60
    _ = await backend.currentStatus(now: Date(timeIntervalSince1970: 200))
    #expect(store.limit == 70)

    _ = try await backend.setChargingEnabled(true, now: Date(timeIntervalSince1970: 300))
    snapshots.chargePercent = 50
    _ = await backend.currentStatus(now: Date(timeIntervalSince1970: 400))
    #expect(store.limit == ManagedChargeLimitBackend.releasedLimit)
}

@Test
func chargeLimitBackendReportsUnknownIntentAfterRestart() async {
    let store = MockChargeLimitStore(limit: 70)
    let backend = makeChargeLimitBackend(store: store, chargePercent: 70)

    let status = await backend.currentStatus(now: Date(timeIntervalSince1970: 100))

    #expect(status.recommendedMode == .fullControl)
    #expect(status.isChargingEnabled == nil)
    #expect(store.limit == 70)
}

@Test
func chargeLimitBackendRestoresManagedStateAfterRestart() async {
    let store = MockChargeLimitStore(limit: 72)
    let baseline = MockChargeLimitBaselineStore()
    baseline.baseline = 80
    let snapshots = MockChargePercentProvider(chargePercent: 72)
    let backend = makeChargeLimitBackend(store: store, baseline: baseline, snapshots: snapshots)

    let status = await backend.currentStatus(now: Date(timeIntervalSince1970: 100))
    #expect(status.isChargingEnabled == false)

    snapshots.chargePercent = 70
    await backend.handlePowerSourceChange(now: Date(timeIntervalSince1970: 200))
    #expect(store.limit == 70)

    let released = MockChargeLimitStore(limit: 100)
    let releasedBackend = makeChargeLimitBackend(store: released, baseline: baseline, chargePercent: 72)
    #expect(await releasedBackend.currentStatus(now: Date(timeIntervalSince1970: 100)).isChargingEnabled == true)
}

@Test
func chargeLimitBackendKeepsPendingApplyAfterRestart() async {
    let store = MockChargeLimitStore(limit: 72)
    store.applied = .limited(100)
    let baseline = MockChargeLimitBaselineStore()
    baseline.baseline = 80
    let backend = makeChargeLimitBackend(store: store, baseline: baseline, chargePercent: 72)

    _ = await backend.currentStatus(now: Date(timeIntervalSince1970: 100))
    let status = await backend.currentStatus(now: Date(timeIntervalSince1970: 400))

    #expect(status.isChargingEnabled == false)
    #expect(status.lastErrorDescription == nil)
}

@Test
func chargeLimitBackendBecomesReadOnlyWhenStoredLimitDoesNotMatch() async {
    let store = MockChargeLimitStore(limit: 80)
    store.ignoresWrites = true
    let backend = makeChargeLimitBackend(store: store, chargePercent: 70)

    await #expect(throws: ChargeControlBackendError.self) {
        try await backend.setChargingEnabled(false, now: Date(timeIntervalSince1970: 100))
    }
    let capability = await backend.probe(snapshot: nil, now: Date(timeIntervalSince1970: 101))

    #expect(capability.recommendedMode == .readOnly)
    #expect(capability.lastErrorDescription != nil)
}

@Test
func chargeLimitBackendReportsAppliedMismatchOnlyAfterGracePeriod() async throws {
    let store = MockChargeLimitStore(limit: 80)
    store.applied = .limited(80)
    let snapshots = MockChargePercentProvider(chargePercent: 70)
    let backend = makeChargeLimitBackend(store: store, snapshots: snapshots)

    _ = try await backend.setChargingEnabled(false, now: Date(timeIntervalSince1970: 100))
    snapshots.chargePercent = 71
    let early = await backend.currentStatus(now: Date(timeIntervalSince1970: 110))
    let late = await backend.currentStatus(now: Date(timeIntervalSince1970: 110 + ManagedChargeLimitBackend.appliedLimitGracePeriod))

    #expect(early.lastErrorDescription == nil)
    #expect(late.lastErrorDescription != nil)

    store.applied = .limited(70)
    let recovered = await backend.currentStatus(now: Date(timeIntervalSince1970: 500))
    #expect(recovered.lastErrorDescription == nil)
}

@Test
func chargeLimitBackendWaitsForBatteryLevelChangeBeforeReportingMismatch() async throws {
    let store = MockChargeLimitStore(limit: 100)
    store.applied = .limited(100)
    let snapshots = MockChargePercentProvider(chargePercent: 80)
    let backend = makeChargeLimitBackend(store: store, snapshots: snapshots)

    _ = try await backend.setChargingEnabled(false, now: Date(timeIntervalSince1970: 100))
    _ = await backend.currentStatus(now: Date(timeIntervalSince1970: 110))
    let pending = await backend.currentStatus(now: Date(timeIntervalSince1970: 600))
    #expect(pending.lastErrorDescription == nil)

    let expired = await backend.currentStatus(
        now: Date(timeIntervalSince1970: 100 + ManagedChargeLimitBackend.maximumPendingApplyDuration)
    )
    let expiredLate = await backend.currentStatus(
        now: Date(timeIntervalSince1970: 100 + ManagedChargeLimitBackend.maximumPendingApplyDuration + ManagedChargeLimitBackend.appliedLimitGracePeriod)
    )
    #expect(expired.lastErrorDescription == nil)
    #expect(expiredLate.lastErrorDescription != nil)
}

@Test
func chargeLimitBackendIgnoresAppliedLimitWhileOnBattery() async throws {
    let store = MockChargeLimitStore(limit: 80)
    store.applied = .none
    let snapshots = MockChargePercentProvider(chargePercent: 20)
    let backend = makeChargeLimitBackend(store: store, snapshots: snapshots)

    _ = try await backend.setChargingEnabled(false, now: Date(timeIntervalSince1970: 100))
    snapshots.isPowerConnected = false
    snapshots.chargePercent = 15
    _ = await backend.currentStatus(now: Date(timeIntervalSince1970: 200))
    let status = await backend.currentStatus(now: Date(timeIntervalSince1970: 2_000))

    #expect(store.limit == ManagedChargeLimitBackend.minimumHoldLimit)
    #expect(status.lastErrorDescription == nil)
}

@Test
func chargeLimitBackendTreatsMissingPolicyAsReleased() async throws {
    let store = MockChargeLimitStore(limit: 80)
    store.applied = .none
    let backend = makeChargeLimitBackend(store: store, chargePercent: 70)

    _ = try await backend.setChargingEnabled(true, now: Date(timeIntervalSince1970: 100))
    _ = await backend.currentStatus(now: Date(timeIntervalSince1970: 110))
    let status = await backend.currentStatus(now: Date(timeIntervalSince1970: 1_000))

    #expect(status.lastErrorDescription == nil)
}

@Test
func chargeLimitBackendIsReadOnlyWithoutRootPrivilege() async {
    let backend = makeChargeLimitBackend(
        store: MockChargeLimitStore(limit: 80),
        chargePercent: 70,
        hasWritePrivilege: false
    )

    let capability = await backend.probe(snapshot: nil, now: Date(timeIntervalSince1970: 100))

    #expect(capability.recommendedMode == .readOnly)
    #expect(capability.helperInstallStatus.state == .permissionMismatch)
}

@Test
func chargeLimitBackendIsUnsupportedWithoutChargeLimitSettings() async {
    let store = MockChargeLimitStore(limit: nil)
    store.available = false
    let backend = makeChargeLimitBackend(store: store, chargePercent: 70)

    let capability = await backend.probe(snapshot: nil, now: Date(timeIntervalSince1970: 100))

    #expect(capability.recommendedMode == .monitoringOnly)
    #expect(capability.helperInstallStatus.helperVersion == CellCapHelperXPC.contractVersion)
}

@Test
func chargeLimitBackendReleaseRestoresBaselineAndStopsManaging() async throws {
    let store = MockChargeLimitStore(limit: 80)
    let baseline = MockChargeLimitBaselineStore()
    let snapshots = MockChargePercentProvider(chargePercent: 70)
    let backend = makeChargeLimitBackend(store: store, baseline: baseline, snapshots: snapshots)

    _ = try await backend.setChargingEnabled(false, now: Date(timeIntervalSince1970: 100))
    #expect(store.limit == 70)

    let released = try await backend.releaseControl(now: Date(timeIntervalSince1970: 200))
    #expect(released.isChargingEnabled == true)
    #expect(store.limit == 80)
    #expect(baseline.baseline == nil)

    // 해제 후에는 SoC가 내려가도 한도를 건드리지 않고, 적용값 불일치도 보지 않는다.
    store.applied = .limited(50)
    snapshots.chargePercent = 60
    let status = await backend.currentStatus(now: Date(timeIntervalSince1970: 1_000))
    await backend.handlePowerSourceChange(now: Date(timeIntervalSince1970: 1_001))
    #expect(store.limit == 80)
    #expect(status.lastErrorDescription == nil)

    // 다시 제어하면 그 시점 값을 새 baseline으로 보관한다.
    _ = try await backend.setChargingEnabled(false, now: Date(timeIntervalSince1970: 1_100))
    #expect(baseline.baseline == 80)
    #expect(store.limit == 60)
}

@Test
func chargeLimitBackendReleaseDoesNotTouchUserLimitWhenNeverManaged() async throws {
    let store = MockChargeLimitStore(limit: 85)
    let baseline = MockChargeLimitBaselineStore()
    let backend = makeChargeLimitBackend(store: store, baseline: baseline, chargePercent: 70)

    let released = try await backend.releaseControl(now: Date(timeIntervalSince1970: 100))

    #expect(released.isChargingEnabled == true)
    #expect(store.limit == 85)
    #expect(store.writeCount == 0)
    #expect(baseline.baseline == nil)
}

@Test
func chargeLimitBackendReleaseRecoversFromStickyFailure() async throws {
    let store = MockChargeLimitStore(limit: 80)
    store.ignoresWrites = true
    let baseline = MockChargeLimitBaselineStore()
    let backend = makeChargeLimitBackend(store: store, baseline: baseline, chargePercent: 70)

    await #expect(throws: ChargeControlBackendError.self) {
        try await backend.setChargingEnabled(false, now: Date(timeIntervalSince1970: 100))
    }
    #expect(await backend.probe(snapshot: nil, now: Date(timeIntervalSince1970: 101)).recommendedMode == .readOnly)

    store.ignoresWrites = false
    _ = try await backend.releaseControl(now: Date(timeIntervalSince1970: 102))
    let capability = await backend.probe(snapshot: nil, now: Date(timeIntervalSince1970: 103))

    #expect(capability.recommendedMode == .fullControl)
    #expect(capability.lastErrorDescription == nil)
    #expect(store.limit == 80)
}

@Test
func chargeLimitBackendRatchetsOnPowerSourceChangeWithoutAppPolling() async throws {
    let store = MockChargeLimitStore(limit: 80)
    let snapshots = MockChargePercentProvider(chargePercent: 75)
    let backend = makeChargeLimitBackend(store: store, snapshots: snapshots)

    _ = try await backend.setChargingEnabled(false, now: Date(timeIntervalSince1970: 100))
    snapshots.chargePercent = 71
    await backend.handlePowerSourceChange(now: Date(timeIntervalSince1970: 200))

    #expect(store.limit == 71)
}

@Test
func chargeLimitBackendIgnoresPowerSourceChangeWhileReadOnly() async throws {
    let store = MockChargeLimitStore(limit: 80)
    let snapshots = MockChargePercentProvider(chargePercent: 75)
    let backend = makeChargeLimitBackend(store: store, snapshots: snapshots, hasWritePrivilege: false)

    snapshots.chargePercent = 60
    await backend.handlePowerSourceChange(now: Date(timeIntervalSince1970: 200))

    #expect(store.limit == 80)
    #expect(store.writeCount == 0)
}

@Test
func backendSelectorForwardsPowerSourceChangeToSelectedBackend() async throws {
    let store = MockChargeLimitStore(limit: 80)
    let snapshots = MockChargePercentProvider(chargePercent: 75)
    let chargeLimitBackend = makeChargeLimitBackend(store: store, snapshots: snapshots)
    let selector = ChargeControlBackendSelector(
        bridge: MockSMCBridge(status: .chargingKeysRemoved),
        chargeLimitStore: store,
        directBackend: RecordingBackend(name: "direct"),
        chargeLimitBackend: chargeLimitBackend
    )

    _ = try await selector.setChargingEnabled(false, now: Date(timeIntervalSince1970: 100))
    snapshots.chargePercent = 70
    await selector.handlePowerSourceChange(now: Date(timeIntervalSince1970: 200))

    #expect(store.limit == 70)
}

@Test
func backendSelectorUsesDirectSMCWhenChargingKeysExist() async {
    let direct = RecordingBackend(name: "direct")
    let chargeLimit = RecordingBackend(name: "chargeLimit")
    let selector = ChargeControlBackendSelector(
        bridge: MockSMCBridge(status: .capableChargingDisabled),
        chargeLimitStore: MockChargeLimitStore(limit: 80),
        directBackend: direct,
        chargeLimitBackend: chargeLimit
    )

    let result = await selector.selfTest(snapshot: nil, now: Date(timeIntervalSince1970: 100))

    #expect(result.message == "direct")
}

@Test
func backendSelectorUsesChargeLimitWhenChargingKeysAreGone() async {
    let selector = ChargeControlBackendSelector(
        bridge: MockSMCBridge(status: .chargingKeysRemoved),
        chargeLimitStore: MockChargeLimitStore(limit: 80),
        directBackend: RecordingBackend(name: "direct"),
        chargeLimitBackend: RecordingBackend(name: "chargeLimit")
    )

    let result = await selector.selfTest(snapshot: nil, now: Date(timeIntervalSince1970: 100))

    #expect(result.message == "chargeLimit")
}

@Test
func backendSelectorRetriesSelectionWhenNoControlPathIsFound() async {
    let store = MockChargeLimitStore(limit: nil)
    store.available = false
    let selector = ChargeControlBackendSelector(
        bridge: MockSMCBridge(status: .chargingKeysRemoved),
        chargeLimitStore: store,
        directBackend: RecordingBackend(name: "direct"),
        chargeLimitBackend: RecordingBackend(name: "chargeLimit")
    )

    let first = await selector.selfTest(snapshot: nil, now: Date(timeIntervalSince1970: 100))
    store.available = true
    let second = await selector.selfTest(snapshot: nil, now: Date(timeIntervalSince1970: 101))

    #expect(first.message == "direct")
    #expect(second.message == "chargeLimit")
}

private func makeChargeLimitBackend(
    store: MockChargeLimitStore,
    baseline: MockChargeLimitBaselineStore = MockChargeLimitBaselineStore(),
    chargePercent: Int,
    hasWritePrivilege: Bool = true
) -> ManagedChargeLimitBackend {
    makeChargeLimitBackend(
        store: store,
        baseline: baseline,
        snapshots: MockChargePercentProvider(chargePercent: chargePercent),
        hasWritePrivilege: hasWritePrivilege
    )
}

private func makeChargeLimitBackend(
    store: MockChargeLimitStore,
    baseline: MockChargeLimitBaselineStore = MockChargeLimitBaselineStore(),
    snapshots: MockChargePercentProvider,
    hasWritePrivilege: Bool = true
) -> ManagedChargeLimitBackend {
    ManagedChargeLimitBackend(
        store: store,
        baselineStore: baseline,
        snapshotProvider: snapshots,
        environment: MockSystemEnvironmentProvider(
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 7, patchVersion: 1),
            isAppleSilicon: true
        ),
        privilegeProvider: MockPrivilegeProvider(hasWritePrivilege: hasWritePrivilege)
    )
}

private final class MockChargeLimitStore: @unchecked Sendable, ChargeLimitStoring {
    var limit: Int?
    var available = true
    var ignoresWrites = false
    var applied: AppliedChargeLimit = .unknown
    var writeCount = 0

    init(limit: Int?) {
        self.limit = limit
    }

    func isAvailable() -> Bool { available }

    func readLimit() -> Int? { limit }

    func writeLimit(_ limit: Int) throws {
        writeCount += 1
        guard !ignoresWrites else { return }
        self.limit = limit
    }

    func readAppliedLimit() -> AppliedChargeLimit { applied }
}

private final class MockChargeLimitBaselineStore: @unchecked Sendable, ChargeLimitBaselineStoring {
    var baseline: Int?

    func loadBaseline() -> Int? { baseline }

    func saveBaseline(_ limit: Int) throws {
        baseline = limit
    }

    func clearBaseline() throws {
        baseline = nil
    }
}

private final class MockChargePercentProvider: @unchecked Sendable, BatterySnapshotProviding {
    var chargePercent: Int
    var isPowerConnected = true

    init(chargePercent: Int) {
        self.chargePercent = chargePercent
    }

    func currentSnapshot(now: Date) throws -> BatterySnapshot? {
        BatterySnapshot(chargePercent: chargePercent, isPowerConnected: isPowerConnected, isCharging: false, isBatteryPresent: true)
    }
}

private actor RecordingBackend: ChargeControlBackend {
    let name: String

    init(name: String) {
        self.name = name
    }

    func probe(snapshot: BatterySnapshot?, now: Date) async -> ChargeControlCapability {
        ChargeControlCapability(
            recommendedMode: .monitoringOnly,
            support: .unsupported,
            reason: name,
            helperPrivilegeSupport: .readOnlyFallback,
            helperPrivilegeReason: name,
            helperInstallStatus: HelperInstallStatus(
                state: .xpcReachable,
                serviceName: CellCapHelperXPC.serviceName,
                helperPath: CellCapHelperXPC.installedBinaryPath,
                plistPath: CellCapHelperXPC.launchDaemonPlistPath,
                reason: name
            ),
            isChargingEnabled: nil,
            temporaryOverrideUntil: nil,
            lastErrorDescription: nil
        )
    }

    func currentStatus(now: Date) async -> ChargeControlRuntimeStatus {
        ChargeControlRuntimeStatus(recommendedMode: .monitoringOnly, isChargingEnabled: nil, temporaryOverrideUntil: nil, lastErrorDescription: nil, checkedAt: now)
    }

    func setChargingEnabled(_ enabled: Bool, now: Date) async throws -> ChargeControlRuntimeStatus {
        await currentStatus(now: now)
    }

    func setTemporaryOverride(until: Date?, now: Date) async throws -> ChargeControlRuntimeStatus {
        await currentStatus(now: now)
    }

    func releaseControl(now: Date) async throws -> ChargeControlRuntimeStatus {
        await currentStatus(now: now)
    }

    func selfTest(snapshot: BatterySnapshot?, now: Date) async -> ControllerSelfTestResult {
        ControllerSelfTestResult(outcome: .failed, message: name, checkedAt: now)
    }
}

private extension SMCBridgeStatus {
    static let chargingKeysRemoved = SMCBridgeStatus(
        serviceAvailable: true,
        legacyChargingKeysAvailable: false,
        tahoeChargingKeyAvailable: false,
        adapterKeyAvailable: true,
        batteryChargeKeyAvailable: true,
        acPowerKeyAvailable: true,
        chargingEnabledKnown: false,
        chargingEnabled: false,
        externalPowerKnown: true,
        externalPowerConnected: true,
        batteryChargePercent: 80
    )
}
