import Foundation
import ServiceManagement
import Shared

public enum HelperDaemonRegistrationStatus: Sendable, Equatable {
    case enabled
    case requiresApproval
    case notRegistered
    case notFound
}

/// 앱 번들에 내장된 helper LaunchDaemon의 SMAppService 등록 경계. 테스트에서는 mock으로 바꾼다.
public protocol HelperDaemonServicing: Sendable {
    var bundleURL: URL { get }
    func registrationStatus() -> HelperDaemonRegistrationStatus
    func register() throws
    func unregister() async throws
    func openApprovalSettings()
}

public struct SMAppServiceHelperDaemon: HelperDaemonServicing {
    public let bundleURL: URL

    public init(bundleURL: URL = Bundle.main.bundleURL) {
        self.bundleURL = bundleURL
    }

    private var service: SMAppService {
        .daemon(plistName: CellCapHelperXPC.launchDaemonPlistName)
    }

    public func registrationStatus() -> HelperDaemonRegistrationStatus {
        switch service.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            return .notRegistered
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }

    public func register() throws {
        try service.register()
    }

    public func unregister() async throws {
        try await service.unregister()
    }

    public func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

public enum HelperServiceActionResult: Sendable, Equatable {
    case completed(String)
    case requiresApproval(String)
    /// 제거 전에 충전 제한을 풀지 못했다. 사용자가 확인하면 force로 다시 제거한다.
    case releaseFailed(String)
    case failed(String)

    public var message: String {
        switch self {
        case .completed(let message), .requiresApproval(let message), .releaseFailed(let message), .failed(let message):
            return message
        }
    }
}

public protocol HelperServiceManaging: Sendable {
    func install() async -> HelperServiceActionResult
    func remove(force: Bool) async -> HelperServiceActionResult
    func openApprovalSettings()
}

public struct HelperServiceManager: HelperServiceManaging {
    private let daemon: any HelperDaemonServicing
    private let controller: any ChargeController
    private let fileSystem: any FileSystemInspecting

    public init(
        controller: any ChargeController,
        daemon: any HelperDaemonServicing = SMAppServiceHelperDaemon(),
        fileSystem: any FileSystemInspecting = DefaultFileSystemInspector()
    ) {
        self.controller = controller
        self.daemon = daemon
        self.fileSystem = fileSystem
    }

    public func install() async -> HelperServiceActionResult {
        // 이전 방식 helper 기록이나 서명이 바뀐 helper 등록이 남아 있으면 새 등록이 그 기록에 묶인다.
        // 등록을 한 번 해제해 기록을 지운 뒤 다시 등록한다.
        if daemon.registrationStatus() == .enabled {
            do {
                try await daemon.unregister()
            } catch {
                return .failed("기존 helper 등록을 정리하지 못했습니다: \(error.localizedDescription)")
            }
        }

        do {
            try daemon.register()
        } catch {
            // 승인이 필요한 경우에도 register()는 오류를 던진다.
            if daemon.registrationStatus() == .requiresApproval {
                return .requiresApproval(Self.approvalMessage)
            }
            return .failed("helper 등록에 실패했습니다: \(error.localizedDescription)")
        }

        if daemon.registrationStatus() == .requiresApproval {
            return .requiresApproval(Self.approvalMessage)
        }
        return .completed("helper를 설치했습니다.")
    }

    public func remove(force: Bool) async -> HelperServiceActionResult {
        // helper를 내리면 root 권한이 없어 충전 한도를 되돌릴 수 없으므로 먼저 해제한다.
        // helper가 실행될 수 없는 상태(승인 대기·미등록)면 해제할 주체가 없으므로 그대로 제거한다.
        if !force, daemon.registrationStatus() == .enabled {
            do {
                try await controller.releaseControl()
            } catch {
                return .releaseFailed(
                    "충전 제한을 먼저 풀지 못했습니다(\(error.localizedDescription)). 그대로 제거하면 충전 한도가 CellCap이 마지막으로 정한 값에 남을 수 있습니다."
                )
            }
        }

        do {
            try await daemon.unregister()
        } catch {
            return .failed("helper 제거에 실패했습니다: \(error.localizedDescription)")
        }

        if fileSystem.fileExists(atPath: CellCapHelperXPC.chargeLimitBaselinePath) {
            return .completed(
                "helper를 제거했지만 충전 한도가 원래 값으로 복원되지 않았습니다. 다시 설치한 뒤 제어를 끄면 복원됩니다."
            )
        }
        return .completed("helper를 제거했습니다.")
    }

    public func openApprovalSettings() {
        daemon.openApprovalSettings()
    }

    private static let approvalMessage = CellCapHelperXPC.backgroundApprovalGuidance
}
