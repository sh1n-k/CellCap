import Core
import Foundation
import Shared
import Testing

@Test
func userDefaultsChargePolicyStoreSavesAndLoadsPolicy() throws {
    let suiteName = "ChargePolicyStoreTests.\(UUID().uuidString)"
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    userDefaults.removePersistentDomain(forName: suiteName)
    defer {
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    let store = UserDefaultsChargePolicyStore(userDefaults: userDefaults)
    let policy = ChargePolicy(
        upperLimit: 84,
        rechargeThreshold: 71,
        temporaryOverrideUntil: Date(timeIntervalSince1970: 2_000),
        isControlEnabled: false
    )

    try store.save(policy)

    let restored = try store.load()
    #expect(restored == policy)

    try store.clear()
    #expect(try store.load() == nil)
}
