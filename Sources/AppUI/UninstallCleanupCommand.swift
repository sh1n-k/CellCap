import Core
import Foundation
import ServiceManagement
import Shared

enum UninstallCleanupCommand {
    static let argument = "--cellcap-uninstall-cleanup"
    static let chargePolicyKey = UserDefaultsChargePolicyStore.defaultStorageKey
    static let launchAtLoginPreferenceKey = LaunchAtLoginManager.preferenceKey

    static func runIfRequested(
        arguments: [String] = CommandLine.arguments,
        userDefaults: UserDefaults = .standard,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        launchAtLoginService: any LaunchAtLoginServiceControlling = MainAppLaunchAtLoginService(),
        unregisterHelperDaemon: () -> Void = unregisterBundledHelperDaemon
    ) -> Bool {
        guard arguments.contains(argument) else {
            return false
        }

        cleanup(
            userDefaults: userDefaults,
            bundleIdentifier: bundleIdentifier,
            launchAtLoginService: launchAtLoginService
        )
        // 제거 pkg가 helper job을 이미 내렸으므로, 앱 삭제 전에 백그라운드 항목 등록 기록만 지운다.
        unregisterHelperDaemon()
        return true
    }

    static func cleanup(
        userDefaults: UserDefaults,
        bundleIdentifier: String?,
        launchAtLoginService: any LaunchAtLoginServiceControlling
    ) {
        removeLoginItem(using: launchAtLoginService)
        removeUserDefaults(userDefaults, bundleIdentifier: bundleIdentifier)
    }

    static func unregisterBundledHelperDaemon() {
        try? SMAppService.daemon(plistName: CellCapHelperXPC.launchDaemonPlistName).unregister()
    }

    private static func removeLoginItem(using service: any LaunchAtLoginServiceControlling) {
        switch service.status {
        case .enabled, .requiresApproval:
            try? service.unregister()
        case .notRegistered, .notFound:
            break
        }
    }

    private static func removeUserDefaults(_ userDefaults: UserDefaults, bundleIdentifier: String?) {
        if let bundleIdentifier {
            userDefaults.removePersistentDomain(forName: bundleIdentifier)
        } else {
            userDefaults.removeObject(forKey: chargePolicyKey)
            userDefaults.removeObject(forKey: launchAtLoginPreferenceKey)
        }

        userDefaults.synchronize()
    }
}
