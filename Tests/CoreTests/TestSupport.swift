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

/// SMAppService 대신 쓰는 helper 등록 mock. register/unregister 뒤 상태를 지정한 값으로 바꾼다.
final class MockHelperDaemon: HelperDaemonServicing, @unchecked Sendable {
    enum Call: Equatable {
        case register
        case unregister
        case openApprovalSettings
    }

    let bundleURL: URL
    private let lock = NSLock()
    private var status: HelperDaemonRegistrationStatus
    private var calls: [Call] = []
    private let statusAfterRegister: HelperDaemonRegistrationStatus
    private let registerError: (any Error)?

    init(
        bundleURL: URL = URL(fileURLWithPath: "/Applications/CellCap.app"),
        status: HelperDaemonRegistrationStatus,
        statusAfterRegister: HelperDaemonRegistrationStatus = .enabled,
        registerError: (any Error)? = nil
    ) {
        self.bundleURL = bundleURL
        self.status = status
        self.statusAfterRegister = statusAfterRegister
        self.registerError = registerError
    }

    func registrationStatus() -> HelperDaemonRegistrationStatus {
        lock.withLock { status }
    }

    func register() throws {
        try lock.withLock {
            calls.append(.register)
            status = statusAfterRegister
            if let registerError { throw registerError }
        }
    }

    func unregister() async throws {
        lock.withLock {
            calls.append(.unregister)
            status = .notRegistered
        }
    }

    func openApprovalSettings() {
        lock.withLock { calls.append(.openApprovalSettings) }
    }

    func recordedCalls() -> [Call] {
        lock.withLock { calls }
    }
}

actor MockChargeController: ChargeController {
    enum Command: Equatable, Sendable {
        case setChargingEnabled(Bool)
        case setTemporaryOverride(Date?)
        case releaseControl
    }

    private var status: ControllerStatus
    private let selfTestResult: ControllerSelfTestResult
    private var commands: [Command] = []
    private var selfTestRequests = 0

    init(
        initialStatus: ControllerStatus = ControllerStatus(
            mode: .readOnly,
            helperConnection: .unavailable,
            isChargingEnabled: nil,
            temporaryOverrideUntil: nil,
            lastErrorDescription: "Mock controller not configured."
        ),
        selfTestResult: ControllerSelfTestResult = ControllerSelfTestResult(
            outcome: .degraded,
            message: "Mock self-test placeholder."
        )
    ) {
        self.status = initialStatus
        self.selfTestResult = selfTestResult
    }

    func setChargingEnabled(_ enabled: Bool) async throws {
        commands.append(.setChargingEnabled(enabled))
        status.isChargingEnabled = enabled
        status.lastErrorDescription = nil
    }

    func setTemporaryOverride(until: Date?) async throws {
        commands.append(.setTemporaryOverride(until))
        status.temporaryOverrideUntil = until
        status.lastErrorDescription = nil
    }

    func releaseControl() async throws {
        commands.append(.releaseControl)
        status.isChargingEnabled = true
        status.lastErrorDescription = nil
    }

    func getControllerStatus() async -> ControllerStatus {
        status
    }

    func selfTest() async -> ControllerSelfTestResult {
        selfTestRequests += 1
        return selfTestResult
    }

    func recordedCommands() -> [Command] {
        commands
    }

    func selfTestRequestCount() -> Int {
        selfTestRequests
    }
}

struct MockFileSystem: FileSystemInspecting {
    let existingFiles: Set<String>

    init(existingFiles: [String]) {
        self.existingFiles = Set(existingFiles)
    }

    func fileExists(atPath path: String) -> Bool {
        existingFiles.contains(path)
    }

    func isExecutableFile(atPath path: String) -> Bool {
        existingFiles.contains(path)
    }
}
