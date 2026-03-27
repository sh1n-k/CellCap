@testable import Core
import Foundation
import Shared
import Testing

@Test
func selfTestPolicyRunsOnlyForEligibleTriggers() async {
    let controller = SupportTestChargeController(
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
        helperPath: CellCapHelperXPC.installedBinaryPath,
        plistPath: CellCapHelperXPC.launchDaemonPlistPath,
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
        helperPath: CellCapHelperXPC.installedBinaryPath,
        plistPath: CellCapHelperXPC.launchDaemonPlistPath,
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
    #expect(merged.helperPath == CellCapHelperXPC.installedBinaryPath)
    #expect(merged.reason.contains("unexpected-version"))
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
    let controller = SupportTestChargeController(
        statusToReturn: ControllerStatus(
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
    let commands = await controller.commands()
    #expect(commands == [
        .setTemporaryOverride(Date(timeIntervalSince1970: 80)),
        .setChargingEnabled(false)
    ])
}

private actor SupportTestChargeController: ChargeController {
    enum Command: Equatable {
        case setChargingEnabled(Bool)
        case setTemporaryOverride(Date?)
    }

    private let statusToReturn: ControllerStatus
    private let selfTestResultValue: ControllerSelfTestResult
    private var recordedCommands: [Command] = []
    private var selfTestRequests = 0

    init(
        statusToReturn: ControllerStatus = ControllerStatus(
            mode: .fullControl,
            helperConnection: .connected,
            isChargingEnabled: true,
            checkedAt: Date(timeIntervalSince1970: 1)
        ),
        selfTestResult: ControllerSelfTestResult = ControllerSelfTestResult(
            outcome: .passed,
            message: "ok",
            checkedAt: Date(timeIntervalSince1970: 1)
        )
    ) {
        self.statusToReturn = statusToReturn
        self.selfTestResultValue = selfTestResult
    }

    func setChargingEnabled(_ enabled: Bool) async throws {
        recordedCommands.append(.setChargingEnabled(enabled))
    }

    func setTemporaryOverride(until: Date?) async throws {
        recordedCommands.append(.setTemporaryOverride(until))
    }

    func getControllerStatus() async -> ControllerStatus {
        statusToReturn
    }

    func selfTest() async -> ControllerSelfTestResult {
        selfTestRequests += 1
        return selfTestResultValue
    }

    func commands() -> [Command] {
        recordedCommands
    }

    func selfTestRequestCount() -> Int {
        selfTestRequests
    }
}
