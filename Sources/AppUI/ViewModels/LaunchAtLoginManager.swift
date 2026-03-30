import Foundation
import ServiceManagement

struct LaunchAtLoginState: Equatable {
    var isEnabled: Bool
    var statusText: String
    var errorText: String?
}

protocol LaunchAtLoginManaging {
    func configureDefaultIfNeeded() -> LaunchAtLoginState
    func setEnabled(_ enabled: Bool) -> LaunchAtLoginState
}

struct DisabledLaunchAtLoginManager: LaunchAtLoginManaging {
    func configureDefaultIfNeeded() -> LaunchAtLoginState {
        LaunchAtLoginState(
            isEnabled: false,
            statusText: "미리보기에서는 로그인 자동 실행을 등록하지 않습니다.",
            errorText: nil
        )
    }

    func setEnabled(_ enabled: Bool) -> LaunchAtLoginState {
        LaunchAtLoginState(
            isEnabled: enabled,
            statusText: "미리보기에서는 로그인 자동 실행을 변경하지 않습니다.",
            errorText: nil
        )
    }
}

struct LaunchAtLoginManager: LaunchAtLoginManaging {
    static let preferenceKey = "com.shin.cellcap.launch-at-login-enabled"

    private let userDefaults: UserDefaults
    private let service: any LaunchAtLoginServiceControlling
    private let environment: any LaunchAtLoginEnvironmentInspecting
    private let preferenceKey: String

    init(
        userDefaults: UserDefaults = .standard,
        preferenceKey: String = LaunchAtLoginManager.preferenceKey,
        service: any LaunchAtLoginServiceControlling = MainAppLaunchAtLoginService(),
        environment: any LaunchAtLoginEnvironmentInspecting = SystemLaunchAtLoginEnvironment()
    ) {
        self.userDefaults = userDefaults
        self.preferenceKey = preferenceKey
        self.service = service
        self.environment = environment
    }

    func configureDefaultIfNeeded() -> LaunchAtLoginState {
        let isEnabled = ensurePreference()
        return synchronizeRegistration(desiredEnabled: isEnabled)
    }

    func setEnabled(_ enabled: Bool) -> LaunchAtLoginState {
        userDefaults.set(enabled, forKey: preferenceKey)
        return synchronizeRegistration(desiredEnabled: enabled)
    }

    private func ensurePreference() -> Bool {
        if userDefaults.object(forKey: preferenceKey) == nil {
            userDefaults.set(true, forKey: preferenceKey)
            return true
        }

        return userDefaults.bool(forKey: preferenceKey)
    }

    private func synchronizeRegistration(desiredEnabled: Bool) -> LaunchAtLoginState {
        var operationError: String?
        let status = service.status

        if desiredEnabled, let unsupportedReason = environment.unsupportedReason {
            operationError = unsupportedReason
        } else {
            do {
                switch (desiredEnabled, status) {
                case (true, .enabled), (false, .notFound), (false, .notRegistered):
                    break
                case (true, .notFound), (true, .notRegistered), (true, .requiresApproval):
                    try service.register()
                case (false, .enabled), (false, .requiresApproval):
                    try service.unregister()
                }
            } catch {
                operationError = error.localizedDescription
            }
        }

        return buildState(
            desiredEnabled: desiredEnabled,
            actualStatus: service.status,
            operationError: operationError
        )
    }

    private func buildState(
        desiredEnabled: Bool,
        actualStatus: LaunchAtLoginServiceStatus,
        operationError: String?
    ) -> LaunchAtLoginState {
        let statusText: String

        switch (desiredEnabled, actualStatus) {
        case (true, .enabled):
            statusText = "로그인 후 앱을 자동으로 열고 저장된 정책을 복구합니다."
        case (true, .requiresApproval):
            statusText = "자동 실행을 요청했습니다. 시스템 승인까지 완료되면 다음 로그인부터 자동 복구합니다."
        case (true, .notFound):
            statusText = "자동 실행을 요청했지만 현재 실행 환경에서는 로그인 항목이 활성화되지 않았습니다."
        case (true, .notRegistered):
            statusText = "자동 실행을 켰지만 아직 시스템 등록이 확인되지 않았습니다."
        case (false, _):
            statusText = "로그인 자동 실행이 꺼져 있어 다음 로그인 때는 자동 복구하지 않습니다."
        }

        return LaunchAtLoginState(
            isEnabled: desiredEnabled,
            statusText: statusText,
            errorText: operationError
        )
    }
}

enum LaunchAtLoginServiceStatus: Equatable {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound
}

protocol LaunchAtLoginServiceControlling {
    var status: LaunchAtLoginServiceStatus { get }
    func register() throws
    func unregister() throws
}

protocol LaunchAtLoginEnvironmentInspecting {
    var unsupportedReason: String? { get }
}

struct SystemLaunchAtLoginEnvironment: LaunchAtLoginEnvironmentInspecting {
    var unsupportedReason: String? {
        let bundleURL = Bundle.main.bundleURL

        guard bundleURL.pathExtension == "app" else {
            return "앱 번들로 실행 중이 아니어서 로그인 자동 실행을 등록할 수 없습니다."
        }

        let codeSignatureURL = bundleURL.appendingPathComponent("Contents/_CodeSignature/CodeResources")
        guard FileManager.default.fileExists(atPath: codeSignatureURL.path) else {
            return "현재 빌드는 코드 서명이 없어 로그인 자동 실행을 등록할 수 없습니다."
        }

        return nil
    }
}

struct MainAppLaunchAtLoginService: LaunchAtLoginServiceControlling {
    var status: LaunchAtLoginServiceStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .notRegistered
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}
