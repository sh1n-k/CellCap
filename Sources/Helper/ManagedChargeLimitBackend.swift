import Foundation
import Shared
import SystemSupport

/// SMC 충전 키가 제거된 펌웨어에서 macOS 충전 한도(manual charge limit)로 충전을 제어한다.
///
/// - 충전 중지: 한도를 현재 SoC로 맞춘다. 펌웨어는 한도 이상에서 충전을 멈추고, SoC와 같으면 방전하지 않는다.
/// - 충전 허용: 한도를 100으로 둔다.
/// - 충전 중지 상태에서 SoC가 한도 아래로 내려가면 한도를 현재 SoC로 낮춘다(래칫). 그래야 재연결 시
///   이전 한도까지 재충전되지 않고 Core의 재충전 기준(하한)이 지켜진다.
actor ManagedChargeLimitBackend: ChargeControlBackend {
    static let releasedLimit = 100
    static let minimumHoldLimit = 20
    static let appliedLimitGracePeriod: TimeInterval = 120
    static let maximumPendingApplyDuration: TimeInterval = 30 * 60

    private let store: any ChargeLimitStoring
    private let baselineStore: any ChargeLimitBaselineStoring
    private let snapshotProvider: any BatterySnapshotProviding
    private let environment: any SystemEnvironmentProviding
    private let privilegeProvider: any HelperPrivilegeProviding

    /// helper가 마지막으로 적용한 의도. CellCap이 관리한 적이 없으면 nil이며 Core가 다음 동기화에서 명령한다.
    private var chargingEnabledIntent: Bool?
    private var didRestoreManagedState = false
    private var expectedLimit: Int?
    private var temporaryOverrideUntil: Date?
    private var stickyFailure: String?
    private var appliedMismatchSince: Date?
    private var lastWrite: (at: Date, chargePercent: Int?)?

    init(
        store: any ChargeLimitStoring = CFPreferencesChargeLimitStore(),
        baselineStore: any ChargeLimitBaselineStoring = FileChargeLimitBaselineStore(),
        snapshotProvider: any BatterySnapshotProviding = SystemBatterySnapshotProvider(),
        environment: any SystemEnvironmentProviding = ProcessInfoEnvironmentProvider(),
        privilegeProvider: any HelperPrivilegeProviding = ProcessPrivilegeProvider()
    ) {
        self.store = store
        self.baselineStore = baselineStore
        self.snapshotProvider = snapshotProvider
        self.environment = environment
        self.privilegeProvider = privilegeProvider
    }

    func probe(snapshot: BatterySnapshot?, now: Date) async -> ChargeControlCapability {
        restoreManagedStateIfNeeded(now: now)
        normalizeOverride(now: now)
        let helperBaseStatus = makeHelperBaseStatus(now: now)

        guard environment.isAppleSilicon() else {
            return unsupported("Apple Silicon 전용 충전 제어 경로입니다.", helperBaseStatus: helperBaseStatus)
        }
        guard environment.operatingSystemVersion.majorVersion >= 26 else {
            return unsupported("macOS 26 이상에서만 저수준 충전 제어를 시도합니다.", helperBaseStatus: helperBaseStatus)
        }
        guard snapshot?.isBatteryPresent != false else {
            return unsupported("내장 배터리가 없는 환경에서는 충전 제어를 수행할 수 없습니다.", helperBaseStatus: helperBaseStatus)
        }
        guard store.isAvailable() else {
            return unsupported("이 기기에서 macOS 충전 한도 설정을 찾지 못했습니다.", helperBaseStatus: helperBaseStatus)
        }

        guard privilegeProvider.hasWritePrivilege() else {
            let reason = "macOS 충전 한도 변경에는 root 권한 helper가 필요합니다."
            var installStatus = helperBaseStatus
            installStatus.state = .permissionMismatch
            installStatus.reason = reason
            return ChargeControlCapability(
                recommendedMode: .readOnly,
                support: .readOnlyFallback,
                reason: reason,
                helperPrivilegeSupport: .readOnlyFallback,
                helperPrivilegeReason: reason,
                helperInstallStatus: installStatus,
                isChargingEnabled: chargingEnabledIntent,
                temporaryOverrideUntil: temporaryOverrideUntil,
                lastErrorDescription: stickyFailure
            )
        }

        if let stickyFailure {
            return ChargeControlCapability(
                recommendedMode: .readOnly,
                support: .readOnlyFallback,
                reason: stickyFailure,
                helperPrivilegeSupport: .supported,
                helperPrivilegeReason: "helper는 root 권한으로 실행 중이지만 최근 명령 실패로 read-only 상태입니다.",
                helperInstallStatus: helperBaseStatus,
                isChargingEnabled: chargingEnabledIntent,
                temporaryOverrideUntil: temporaryOverrideUntil,
                lastErrorDescription: stickyFailure
            )
        }

        return ChargeControlCapability(
            recommendedMode: .fullControl,
            support: .experimental,
            reason: "비문서화된 macOS 충전 한도 설정 경로로 충전을 제어합니다.",
            helperPrivilegeSupport: .supported,
            helperPrivilegeReason: "helper가 root 권한으로 실행 중입니다.",
            helperInstallStatus: helperBaseStatus,
            isChargingEnabled: chargingEnabledIntent,
            temporaryOverrideUntil: temporaryOverrideUntil,
            lastErrorDescription: appliedMismatchError(now: now)
        )
    }

    func currentStatus(now: Date) async -> ChargeControlRuntimeStatus {
        restoreManagedStateIfNeeded(now: now)
        normalizeOverride(now: now)
        let capability = await probe(snapshot: nil, now: now)
        if capability.recommendedMode == .fullControl {
            ratchetHoldLimitIfNeeded(now: now)
        }
        updateAppliedMismatch(now: now)

        return ChargeControlRuntimeStatus(
            recommendedMode: capability.recommendedMode,
            isChargingEnabled: chargingEnabledIntent,
            temporaryOverrideUntil: temporaryOverrideUntil,
            lastErrorDescription: capability.recommendedMode == .fullControl
                ? appliedMismatchError(now: now)
                : capability.lastErrorDescription,
            checkedAt: now
        )
    }

    func setChargingEnabled(_ enabled: Bool, now: Date) async throws -> ChargeControlRuntimeStatus {
        let capability = await probe(snapshot: nil, now: now)
        switch capability.recommendedMode {
        case .fullControl:
            break
        case .readOnly:
            throw ChargeControlBackendError.approvalRequired(capability.reason)
        case .monitoringOnly:
            throw ChargeControlBackendError.unsupportedEnvironment(capability.reason)
        }

        let limit: Int
        if enabled {
            limit = Self.releasedLimit
        } else {
            guard let chargePercent = currentChargePercent(now: now) else {
                throw ChargeControlBackendError.backendFailure("현재 배터리 잔량을 읽지 못해 충전 한도를 정할 수 없습니다.")
            }
            limit = Self.holdLimit(for: chargePercent)
        }

        try applyLimit(limit, now: now, marksFailureSticky: true)
        chargingEnabledIntent = enabled

        return ChargeControlRuntimeStatus(
            recommendedMode: .fullControl,
            isChargingEnabled: enabled,
            temporaryOverrideUntil: temporaryOverrideUntil,
            lastErrorDescription: nil,
            checkedAt: now
        )
    }

    func setTemporaryOverride(until: Date?, now: Date) async throws -> ChargeControlRuntimeStatus {
        if let until, until <= now {
            temporaryOverrideUntil = nil
            throw ChargeControlBackendError.commandRejected("temporary override 종료 시각이 이미 지났습니다.")
        }

        let capability = await probe(snapshot: nil, now: now)
        switch capability.recommendedMode {
        case .fullControl:
            temporaryOverrideUntil = until
            stickyFailure = nil
            return ChargeControlRuntimeStatus(
                recommendedMode: .fullControl,
                isChargingEnabled: chargingEnabledIntent,
                temporaryOverrideUntil: temporaryOverrideUntil,
                lastErrorDescription: nil,
                checkedAt: now
            )
        case .readOnly:
            throw ChargeControlBackendError.approvalRequired(capability.reason)
        case .monitoringOnly:
            throw ChargeControlBackendError.unsupportedEnvironment(capability.reason)
        }
    }

    func selfTest(snapshot: BatterySnapshot?, now: Date) async -> ControllerSelfTestResult {
        let capability = await probe(snapshot: snapshot, now: now)
        switch capability.recommendedMode {
        case .fullControl:
            return ControllerSelfTestResult(
                outcome: .passed,
                message: "macOS 충전 한도 설정 경로와 helper 권한을 확인했습니다.",
                checkedAt: now
            )
        case .readOnly:
            return ControllerSelfTestResult(outcome: .degraded, message: capability.reason, checkedAt: now)
        case .monitoringOnly:
            return ControllerSelfTestResult(outcome: .failed, message: capability.reason, checkedAt: now)
        }
    }

    func releaseControl(now: Date) async throws -> ChargeControlRuntimeStatus {
        restoreManagedStateIfNeeded(now: now)
        normalizeOverride(now: now)
        // 해제는 최근 실패로 인한 read-only(stickyFailure)와 무관하게 실행한다.
        guard environment.isAppleSilicon(), store.isAvailable() else {
            throw ChargeControlBackendError.unsupportedEnvironment("이 기기에서 macOS 충전 한도 설정을 찾지 못했습니다.")
        }
        guard privilegeProvider.hasWritePrivilege() else {
            throw ChargeControlBackendError.approvalRequired("macOS 충전 한도 변경에는 root 권한 helper가 필요합니다.")
        }

        // CellCap이 한도를 바꾼 적이 없으면(baseline 없음) 사용자 설정을 건드리지 않는다.
        let baseline = baselineStore.loadBaseline()
        if let baseline {
            try store.writeLimit(baseline)
        }

        // 복원 쓰기가 끝나면 baseline 정리 실패와 무관하게 관리를 멈춰, 래칫이 복원값을 다시 덮지 않게 한다.
        chargingEnabledIntent = true
        expectedLimit = nil
        appliedMismatchSince = nil
        lastWrite = nil
        stickyFailure = nil
        temporaryOverrideUntil = nil

        if baseline != nil {
            try baselineStore.clearBaseline()
        }

        return ChargeControlRuntimeStatus(
            recommendedMode: .fullControl,
            isChargingEnabled: true,
            temporaryOverrideUntil: nil,
            lastErrorDescription: nil,
            checkedAt: now
        )
    }

    func handlePowerSourceChange(now: Date) async {
        restoreManagedStateIfNeeded(now: now)
        normalizeOverride(now: now)
        guard stickyFailure == nil,
              privilegeProvider.hasWritePrivilege(),
              store.isAvailable() else {
            return
        }
        ratchetHoldLimitIfNeeded(now: now)
        updateAppliedMismatch(now: now)
    }

    static func holdLimit(for chargePercent: Int) -> Int {
        min(releasedLimit, max(minimumHoldLimit, chargePercent))
    }

    private func applyLimit(_ limit: Int, now: Date, marksFailureSticky: Bool) throws {
        do {
            if baselineStore.loadBaseline() == nil {
                // 처음 개입하기 전의 사용자 값을 남긴다. 값이 없으면 한도 없음(100)으로 본다.
                try baselineStore.saveBaseline(store.readLimit() ?? Self.releasedLimit)
            }
            try store.writeLimit(limit)
        } catch {
            if marksFailureSticky {
                stickyFailure = error.localizedDescription
            }
            throw error
        }

        let written = store.readLimit()
        guard written == limit else {
            let failure = ChargeControlBackendError.backendFailure(
                "macOS 충전 한도 저장값 검증에 실패했습니다. expected=\(limit) actual=\(written.map(String.init) ?? "nil")"
            )
            if marksFailureSticky {
                stickyFailure = failure.localizedDescription
            }
            throw failure
        }

        stickyFailure = nil
        expectedLimit = limit
        appliedMismatchSince = nil
        lastWrite = (now, currentChargePercent(now: now))
    }

    private func ratchetHoldLimitIfNeeded(now: Date) {
        guard chargingEnabledIntent == false,
              temporaryOverrideUntil == nil,
              let expectedLimit,
              let chargePercent = currentChargePercent(now: now) else {
            return
        }

        let lowered = Self.holdLimit(for: chargePercent)
        guard lowered < expectedLimit else {
            return
        }
        // 래칫 실패는 다음 동기화에서 다시 시도하면 되므로 read-only로 강등하지 않는다.
        try? applyLimit(lowered, now: now, marksFailureSticky: false)
    }

    /// powerd 적용값은 prefs보다 늦게 갱신되므로 grace 기간이 지나도 다를 때만 오류로 본다.
    /// 한도를 100으로 해제한 뒤 다시 걸면 PowerUIAgent가 다음 배터리 % 변화 때 적용한다(실측 약 110초, 4.5 A 충전 중).
    /// 그래서 기록 당시 SoC가 그대로인 동안은 적용 대기로 보고 grace를 시작하지 않는다.
    private func updateAppliedMismatch(now: Date) {
        // 배터리 사용 중에는 powerd가 충전 한도 정책을 내려 두므로 비교하지 않는다(실측: 분리 중 battlimit 비어 있음).
        guard let expectedLimit, currentSnapshot(now: now)?.isPowerConnected != false else {
            appliedMismatchSince = nil
            return
        }

        let matches: Bool
        switch store.readAppliedLimit() {
        case .unknown:
            matches = true
        case .none:
            matches = expectedLimit == Self.releasedLimit
        case .limited(let applied):
            matches = applied == expectedLimit
        }

        if matches || isAwaitingBatteryLevelChange(now: now) {
            appliedMismatchSince = nil
        } else if appliedMismatchSince == nil {
            appliedMismatchSince = now
        }
    }

    private func isAwaitingBatteryLevelChange(now: Date) -> Bool {
        guard let lastWrite,
              let writtenAtPercent = lastWrite.chargePercent,
              now.timeIntervalSince(lastWrite.at) < Self.maximumPendingApplyDuration else {
            return false
        }
        return currentChargePercent(now: now) == writtenAtPercent
    }

    private func appliedMismatchError(now: Date) -> String? {
        guard let appliedMismatchSince,
              now.timeIntervalSince(appliedMismatchSince) >= Self.appliedLimitGracePeriod else {
            return nil
        }
        return "macOS가 CellCap 충전 한도(\(expectedLimit.map(String.init) ?? "?")%)를 적용하지 않았습니다."
    }

    private func currentChargePercent(now: Date) -> Int? {
        currentSnapshot(now: now)?.chargePercent
    }

    private func currentSnapshot(now: Date) -> BatterySnapshot? {
        guard let snapshot = try? snapshotProvider.currentSnapshot(now: now),
              snapshot.isBatteryPresent else {
            return nil
        }
        return snapshot
    }

    /// helper 재시작 후 이전 관리 상태를 되살린다. baseline이 남아 있으면 CellCap이 한도를 관리 중이었다는 뜻이다.
    /// baseline이 없으면 사용자 설정이므로 의도를 nil로 두고 Core의 다음 명령을 기다린다.
    private func restoreManagedStateIfNeeded(now: Date) {
        guard !didRestoreManagedState else {
            return
        }
        didRestoreManagedState = true

        guard chargingEnabledIntent == nil,
              baselineStore.loadBaseline() != nil,
              let limit = store.readLimit() else {
            return
        }
        expectedLimit = limit
        chargingEnabledIntent = limit >= Self.releasedLimit
        // 재시작 직전에 쓴 값이 아직 적용 대기 중일 수 있으므로 방금 쓴 것으로 간주해 grace 판정을 시작한다.
        lastWrite = (now, currentChargePercent(now: now))
    }

    private func normalizeOverride(now: Date) {
        if let temporaryOverrideUntil, temporaryOverrideUntil <= now {
            self.temporaryOverrideUntil = nil
        }
    }

    private func makeHelperBaseStatus(now: Date) -> HelperInstallStatus {
        HelperInstallStatus(
            state: .xpcReachable,
            serviceName: CellCapHelperXPC.serviceName,
            helperPath: CellCapHelperXPC.bundledHelperProgramPath,
            plistPath: CellCapHelperXPC.bundledLaunchDaemonPlistPath,
            helperVersion: CellCapHelperXPC.contractVersion,
            expectedVersion: CellCapHelperXPC.contractVersion,
            reason: "helper XPC에 도달했습니다.",
            checkedAt: now
        )
    }

    private func unsupported(_ reason: String, helperBaseStatus: HelperInstallStatus) -> ChargeControlCapability {
        ChargeControlCapability(
            recommendedMode: .monitoringOnly,
            support: .unsupported,
            reason: reason,
            helperPrivilegeSupport: .readOnlyFallback,
            helperPrivilegeReason: "이 환경에서는 helper 권한 확인이 의미가 없습니다.",
            helperInstallStatus: helperBaseStatus,
            isChargingEnabled: nil,
            temporaryOverrideUntil: nil,
            lastErrorDescription: nil
        )
    }
}
