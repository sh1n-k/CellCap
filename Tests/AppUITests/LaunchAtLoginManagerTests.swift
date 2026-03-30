@testable import AppUI
import Foundation
import Testing

@Test
func launchAtLoginManagerDefaultsToEnabledOnFirstRun() throws {
    let suiteName = "LaunchAtLoginManagerTests.\(UUID().uuidString)"
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    userDefaults.removePersistentDomain(forName: suiteName)
    defer {
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    let service = MockLaunchAtLoginService(status: .notRegistered)
    let manager = LaunchAtLoginManager(userDefaults: userDefaults, service: service)

    let state = manager.configureDefaultIfNeeded()

    #expect(state.isEnabled)
    #expect(userDefaults.bool(forKey: LaunchAtLoginManager.preferenceKey))
    #expect(service.registerCallCount == 1)
}

@Test
func launchAtLoginManagerRequestsUnregisterWhenDisabled() throws {
    let suiteName = "LaunchAtLoginManagerTests.\(UUID().uuidString)"
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    userDefaults.removePersistentDomain(forName: suiteName)
    defer {
        userDefaults.removePersistentDomain(forName: suiteName)
    }
    userDefaults.set(true, forKey: LaunchAtLoginManager.preferenceKey)

    let service = MockLaunchAtLoginService(status: .enabled)
    let manager = LaunchAtLoginManager(userDefaults: userDefaults, service: service)

    let state = manager.setEnabled(false)

    #expect(state.isEnabled == false)
    #expect(service.unregisterCallCount == 1)
    #expect(userDefaults.bool(forKey: LaunchAtLoginManager.preferenceKey) == false)
}

private final class MockLaunchAtLoginService: LaunchAtLoginServiceControlling {
    var status: LaunchAtLoginServiceStatus
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(status: LaunchAtLoginServiceStatus) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        status = .notRegistered
    }
}
