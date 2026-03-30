import Foundation
import Shared

public protocol ChargePolicyStoring: Sendable {
    func load() throws -> ChargePolicy?
    func save(_ policy: ChargePolicy) throws
    func clear() throws
}

public struct DiscardingChargePolicyStore: ChargePolicyStoring {
    public init() {}

    public func load() throws -> ChargePolicy? {
        nil
    }

    public func save(_ policy: ChargePolicy) throws {}

    public func clear() throws {}
}

public struct UserDefaultsChargePolicyStore: ChargePolicyStoring, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "com.shin.cellcap.charge-policy"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func load() throws -> ChargePolicy? {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return nil
        }

        return try decoder.decode(ChargePolicy.self, from: data)
    }

    public func save(_ policy: ChargePolicy) throws {
        let data = try encoder.encode(policy)
        userDefaults.set(data, forKey: storageKey)
    }

    public func clear() throws {
        userDefaults.removeObject(forKey: storageKey)
    }
}
