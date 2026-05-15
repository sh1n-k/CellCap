import Foundation

enum UninstallCleanupCommand {
    static let argument = "--cellcap-uninstall-cleanup"
    static let chargePolicyKey = "com.shin.cellcap.charge-policy"
    static let launchAtLoginPreferenceKey = LaunchAtLoginManager.preferenceKey

    static func runIfRequested(
        arguments: [String] = CommandLine.arguments,
        userDefaults: UserDefaults = .standard,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        launchAtLoginService: any LaunchAtLoginServiceControlling = MainAppLaunchAtLoginService()
    ) -> Bool {
        guard arguments.contains(argument) else {
            return false
        }

        cleanup(
            userDefaults: userDefaults,
            bundleIdentifier: bundleIdentifier,
            launchAtLoginService: launchAtLoginService
        )
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
