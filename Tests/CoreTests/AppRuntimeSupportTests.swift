@testable import Core
import Foundation
import Shared
import SystemSupport
import Testing

@Test
func selfTestPolicyRunsOnlyForEligibleTriggers() async {
    let controller = MockChargeController(
        selfTestResult: ControllerSelfTestResult(
            outcome: .passed,
            message: "ok",
            checkedAt: Date(timeIntervalSince1970: 10)
        )
    )
    let policy = SelfTestPolicy(
        controller: controller,
        eventLogger: EventLogger()
    )
    let helperInstallStatus = HelperInstallStatus(
        state: .xpcReachable,
        serviceName: CellCapHelperXPC.serviceName,
        helperPath: CellCapHelperXPC.bundledHelperProgramPath,
        plistPath: CellCapHelperXPC.bundledLaunchDaemonPlistPath,
        expectedVersion: CellCapHelperXPC.contractVersion,
        reason: "ready",
        checkedAt: Date(timeIntervalSince1970: 10)
    )
    let controllerStatus = ControllerStatus(
        mode: .fullControl,
        helperConnection: .connected,
        isChargingEnabled: true,
        checkedAt: Date(timeIntervalSince1970: 10)
    )

    let launchResult = await policy.performIfNeeded(
        trigger: .appLaunch,
        helperInstallStatus: helperInstallStatus,
        controllerStatus: controllerStatus
    )
    let policyChangedResult = await policy.performIfNeeded(
        trigger: .policyChanged,
        helperInstallStatus: helperInstallStatus,
        controllerStatus: controllerStatus
    )

    #expect(launchResult?.outcome == .passed)
    #expect(policyChangedResult == nil)
    let selfTestCount = await controller.selfTestRequestCount()
    #expect(selfTestCount == 1)
}

@Test
func capabilityReportResolverMarksVersionMismatchWhenProbeReturnsDifferentVersion() async {
    let helperInstallStatus = HelperInstallStatus(
        state: .bootstrapped,
        serviceName: CellCapHelperXPC.serviceName,
        helperPath: CellCapHelperXPC.bundledHelperProgramPath,
        plistPath: CellCapHelperXPC.bundledLaunchDaemonPlistPath,
        helperVersion: nil,
        expectedVersion: CellCapHelperXPC.contractVersion,
        reason: "launchd 등록됨",
        checkedAt: Date(timeIntervalSince1970: 20)
    )
    let remoteStatus = HelperInstallStatus(
        state: .xpcReachable,
        serviceName: CellCapHelperXPC.serviceName,
        helperPath: "/tmp/ignored",
        plistPath: "/tmp/ignored.plist",
        helperVersion: "unexpected-version",
        expectedVersion: CellCapHelperXPC.contractVersion,
        reason: "remote ready",
        checkedAt: Date(timeIntervalSince1970: 20)
    )

    let merged = CapabilityReportResolver.mergeHelperInstallStatus(
        local: helperInstallStatus,
        remote: remoteStatus
    )

    #expect(merged.state == .versionMismatch)
    #expect(merged.helperPath == CellCapHelperXPC.bundledHelperProgramPath)
    #expect(merged.reason.contains("unexpected-version"))
}

@Test
func capabilityReportResolverMarksVersionMismatchWhenOldHelperReportsItsOwnVersion() {
    let local = HelperInstallStatus(
        state: .bootstrapped,
        serviceName: CellCapHelperXPC.serviceName,
        helperPath: CellCapHelperXPC.bundledHelperProgramPath,
        plistPath: CellCapHelperXPC.bundledLaunchDaemonPlistPath,
        expectedVersion: CellCapHelperXPC.contractVersion,
        reason: "launchd 등록됨"
    )
    // 이전 빌드 helper는 helperVersion과 expectedVersion을 모두 자기 계약 버전으로 채운다.
    let remote = HelperInstallStatus(
        state: .xpcReachable,
        serviceName: CellCapHelperXPC.serviceName,
        helperPath: "/tmp/ignored",
        plistPath: "/tmp/ignored.plist",
        helperVersion: "old-version",
        expectedVersion: "old-version",
        reason: "remote ready"
    )

    let merged = CapabilityReportResolver.mergeHelperInstallStatus(local: local, remote: remote)

    #expect(merged.state == .versionMismatch)
    #expect(merged.expectedVersion == CellCapHelperXPC.contractVersion)
}

@Test
func runtimeSafetyGateDowngradesUnsupportedCapabilityToMonitoringOnly() {
    let gate = RuntimeSafetyGate()
    let controllerStatus = ControllerStatus(
        mode: .fullControl,
        helperConnection: .connected,
        isChargingEnabled: false,
        checkedAt: Date(timeIntervalSince1970: 30)
    )
    let capabilityReport = CapabilityReport(
        statuses: [
            CapabilityStatus(key: .helperInstallation, support: .supported, reason: "ok"),
            CapabilityStatus(key: .helperPrivilege, support: .supported, reason: "ok"),
            CapabilityStatus(key: .chargeControl, support: .unsupported, reason: "unsupported")
        ],
        recommendedControllerMode: .fullControl
    )

    let result = gate.apply(
        controllerStatus: controllerStatus,
        capabilityReport: capabilityReport,
        selfTestResult: nil,
        now: Date(timeIntervalSince1970: 30)
    )

    #expect(result.controllerStatus.mode == .monitoringOnly)
    #expect(result.capabilityReport.recommendedControllerMode == .monitoringOnly)
}

@Test
func controllerCommandApplierSynchronizesOverrideAndChargingState() async {
    let controller = MockChargeController(
        initialStatus: ControllerStatus(
            mode: .fullControl,
            helperConnection: .connected,
            isChargingEnabled: false,
            temporaryOverrideUntil: Date(timeIntervalSince1970: 80),
            checkedAt: Date(timeIntervalSince1970: 80)
        )
    )
    let applier = ControllerCommandApplier(
        controller: controller,
        eventLogger: EventLogger()
    )
    let evaluation = PolicyEvaluation(
        effectivePolicy: EffectiveChargePolicy(
            upperLimit: 80,
            rechargeThreshold: 75,
            temporaryOverrideUntil: Date(timeIntervalSince1970: 80),
            isTemporaryOverrideActive: true,
            isControlEnabled: true
        ),
        resolution: ChargeStateResolution(
            state: .holdingAtLimit,
            reason: .atUpperLimit,
            selectedBattery: BatterySnapshot(
                chargePercent: 82,
                isPowerConnected: true,
                isCharging: false,
                observedAt: Date(timeIntervalSince1970: 80),
                source: .system
            )
        ),
        transition: ChargeTransition(
            previous: .charging,
            current: .holdingAtLimit,
            reason: .atUpperLimit
        ),
        chargingCommand: .disableCharging
    )
    let capabilityReport = CapabilityReport(
        statuses: [
            CapabilityStatus(key: .helperInstallation, support: .supported, reason: "ok"),
            CapabilityStatus(key: .helperPrivilege, support: .supported, reason: "ok"),
            CapabilityStatus(key: .chargeControl, support: .experimental, reason: "ok")
        ],
        recommendedControllerMode: .fullControl
    )

    let updated = await applier.applyIfNeeded(
        controllerStatus: ControllerStatus(
            mode: .fullControl,
            helperConnection: .connected,
            isChargingEnabled: true,
            temporaryOverrideUntil: nil,
            checkedAt: Date(timeIntervalSince1970: 79)
        ),
        capabilityReport: capabilityReport,
        evaluation: evaluation,
        now: Date(timeIntervalSince1970: 80)
    )

    #expect(updated.isChargingEnabled == false)
    let commands = await controller.recordedCommands()
    #expect(commands == [
        .setTemporaryOverride(Date(timeIntervalSince1970: 80)),
        .setChargingEnabled(false)
    ])
}

@Test
func controllerCommandApplierReleasesControlEvenWhenHelperReportsError() async {
    let controller = MockChargeController()
    let applier = ControllerCommandApplier(controller: controller, eventLogger: EventLogger())

    _ = await applier.applyIfNeeded(
        controllerStatus: ControllerStatus(
            mode: .readOnly,
            helperConnection: .connected,
            isChargingEnabled: false,
            lastErrorDescription: "applied limit mismatch",
            checkedAt: Date(timeIntervalSince1970: 80)
        ),
        capabilityReport: makeReleaseCapabilityReport(installation: .supported),
        evaluation: makeReleaseEvaluation(),
        now: Date(timeIntervalSince1970: 80)
    )

    let commands = await controller.recordedCommands()
    #expect(commands == [.releaseControl])
}

@Test
func controllerCommandApplierSkipsReleaseWhenHelperVersionDoesNotMatch() async {
    let controller = MockChargeController()
    let applier = ControllerCommandApplier(controller: controller, eventLogger: EventLogger())

    _ = await applier.applyIfNeeded(
        controllerStatus: ControllerStatus(
            mode: .readOnly,
            helperConnection: .connected,
            isChargingEnabled: false,
            checkedAt: Date(timeIntervalSince1970: 80)
        ),
        capabilityReport: makeReleaseCapabilityReport(installation: .readOnlyFallback),
        evaluation: makeReleaseEvaluation(),
        now: Date(timeIntervalSince1970: 80)
    )

    let commands = await controller.recordedCommands()
    #expect(commands.isEmpty)
}

@Test
func controllerCommandApplierReleasesOncePerControlOffPeriod() async {
    let controller = MockChargeController()
    let applier = ControllerCommandApplier(controller: controller, eventLogger: EventLogger())
    let status = ControllerStatus(
        mode: .fullControl,
        helperConnection: .connected,
        isChargingEnabled: true,
        checkedAt: Date(timeIntervalSince1970: 80)
    )
    let report = makeReleaseCapabilityReport(installation: .supported)

    _ = await applier.applyIfNeeded(controllerStatus: status, capabilityReport: report, evaluation: makeReleaseEvaluation(), now: Date(timeIntervalSince1970: 80))
    _ = await applier.applyIfNeeded(controllerStatus: status, capabilityReport: report, evaluation: makeReleaseEvaluation(), now: Date(timeIntervalSince1970: 81))
    #expect(await controller.recordedCommands() == [.releaseControl])

    var controlOn = makeReleaseEvaluation()
    controlOn.effectivePolicy.isControlEnabled = true
    controlOn.chargingCommand = .noChange
    _ = await applier.applyIfNeeded(controllerStatus: status, capabilityReport: report, evaluation: controlOn, now: Date(timeIntervalSince1970: 82))
    _ = await applier.applyIfNeeded(controllerStatus: status, capabilityReport: report, evaluation: makeReleaseEvaluation(), now: Date(timeIntervalSince1970: 83))
    #expect(await controller.recordedCommands() == [.releaseControl, .releaseControl])
}

private func makeReleaseCapabilityReport(installation: CapabilitySupport) -> CapabilityReport {
    CapabilityReport(
        statuses: [
            CapabilityStatus(key: .helperInstallation, support: installation, reason: "test"),
            CapabilityStatus(key: .helperPrivilege, support: .supported, reason: "ok"),
            CapabilityStatus(key: .chargeControl, support: .readOnlyFallback, reason: "error")
        ],
        recommendedControllerMode: .readOnly
    )
}

private func makeReleaseEvaluation() -> PolicyEvaluation {
    PolicyEvaluation(
        effectivePolicy: EffectiveChargePolicy(
            upperLimit: 80,
            rechargeThreshold: 75,
            temporaryOverrideUntil: nil,
            isTemporaryOverrideActive: false,
            isControlEnabled: false
        ),
        resolution: ChargeStateResolution(
            state: .errorReadOnly,
            reason: .helperFailure,
            selectedBattery: nil
        ),
        transition: ChargeTransition(previous: .holdingAtLimit, current: .errorReadOnly, reason: .helperFailure),
        chargingCommand: .releaseControl
    )
}
