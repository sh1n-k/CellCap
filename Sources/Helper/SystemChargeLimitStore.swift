import notify
import Foundation
import Shared

/// powerd에 실제로 적용된 macOS 충전 한도(manual charge limit) 상태.
enum AppliedChargeLimit: Sendable, Equatable {
    case limited(Int)
    case none
    case unknown
}

/// macOS 충전 한도 설정(PowerUIAgent prefs)과 powerd 적용 상태를 읽고 쓴다.
protocol ChargeLimitStoring: Sendable {
    func isAvailable() -> Bool
    func readLimit() -> Int?
    func writeLimit(_ limit: Int) throws
    func readAppliedLimit() -> AppliedChargeLimit
}

/// helper가 처음 개입하기 전의 사용자 충전 한도를 보관한다.
protocol ChargeLimitBaselineStoring: Sendable {
    func loadBaseline() -> Int?
    func saveBaseline(_ limit: Int) throws
    func clearBaseline() throws
}

/// PowerUIAgent는 root 사용자 도메인의 `mclLimitValue`를 `defaultschanged` 알림 때 다시 읽어
/// 범위 검사 없이 powerd에 전달한다. 공개 API(`setMCLLimit:`)는 80–100%만 허용하므로 이 경로를 쓴다.
/// `MCLFeatureState`는 알림으로 다시 읽히지 않고, 쓰면 이후 한도 변경이 무시되는 현상이 관측되어 건드리지 않는다.
struct CFPreferencesChargeLimitStore: ChargeLimitStoring {
    private static let domain = "com.apple.smartcharging.topoffprotection"
    private static let limitKey = "mclLimitValue"
    private static let featureStateKey = "MCLFeatureState"
    private static let changeNotification = "com.apple.smartcharging.defaultschanged"
    private static let powerdChargingPolicyPath = "/Library/Preferences/com.apple.powerd.charging.plist"
    private static let manualChargeLimitReason = "manualChargeLimit"

    func isAvailable() -> Bool {
        if readLimit() != nil || copyValue(Self.featureStateKey) != nil {
            return true
        }
        return FileManager.default.fileExists(atPath: Self.powerdChargingPolicyPath)
    }

    func readLimit() -> Int? {
        (copyValue(Self.limitKey) as? NSNumber)?.intValue
    }

    func writeLimit(_ limit: Int) throws {
        CFPreferencesSetValue(
            Self.limitKey as CFString,
            NSNumber(value: limit),
            Self.domain as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        guard CFPreferencesSynchronize(Self.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw ChargeControlBackendError.backendFailure("macOS 충전 한도 설정을 저장하지 못했습니다.")
        }
        let result = notify_post(Self.changeNotification)
        guard result == UInt32(NOTIFY_STATUS_OK) else {
            throw ChargeControlBackendError.backendFailure("macOS 충전 한도 변경 알림을 보내지 못했습니다. status=\(result)")
        }
    }

    func readAppliedLimit() -> AppliedChargeLimit {
        guard let fileData = FileManager.default.contents(atPath: Self.powerdChargingPolicyPath),
              let root = try? PropertyListSerialization.propertyList(from: fileData, format: nil) as? [String: Any],
              let archived = root["policies"] as? Data,
              let policies = PowerdChargePolicyRecord.decodePolicies(from: archived) else {
            return .unknown
        }

        let active = policies.filter { !$0.terminated && $0.reason == Self.manualChargeLimitReason }
        guard let limit = active.map(\.socLimit).min() else {
            return .none
        }
        return .limited(limit)
    }

    private func copyValue(_ key: String) -> CFPropertyList? {
        CFPreferencesCopyValue(key as CFString, Self.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}

/// powerd가 `com.apple.powerd.charging.plist`에 NSKeyedArchiver로 보관하는 `ChargeCtrlPolicy`의 필요한 필드만 읽는다.
@objc(CellCapPowerdChargePolicyRecord)
private final class PowerdChargePolicyRecord: NSObject, NSSecureCoding {
    static let supportsSecureCoding = true

    let socLimit: Int
    let terminated: Bool
    let reason: String?

    init?(coder: NSCoder) {
        // 필드가 없으면 0으로 읽혀 거짓 불일치가 되므로 해석을 포기한다(.unknown).
        guard coder.containsValue(forKey: "soclimit") else {
            return nil
        }
        socLimit = coder.decodeInteger(forKey: "soclimit")
        terminated = coder.decodeBool(forKey: "terminated")
        reason = coder.decodeObject(of: NSString.self, forKey: "reason") as String?
    }

    func encode(with coder: NSCoder) {}

    static func decodePolicies(from data: Data) -> [PowerdChargePolicyRecord]? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else {
            return nil
        }
        unarchiver.setClass(PowerdChargePolicyRecord.self, forClassName: "ChargeCtrlPolicy")
        defer { unarchiver.finishDecoding() }
        let decoded = unarchiver.decodeObject(
            of: [NSArray.self, PowerdChargePolicyRecord.self],
            forKey: NSKeyedArchiveRootObjectKey
        )
        return decoded as? [PowerdChargePolicyRecord]
    }
}

struct FileChargeLimitBaselineStore: ChargeLimitBaselineStoring {
    private static let limitKey = "mclLimitValue"

    let path: String

    init(path: String = CellCapHelperXPC.chargeLimitBaselinePath) {
        self.path = path
    }

    func loadBaseline() -> Int? {
        guard let data = FileManager.default.contents(atPath: path),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return (root[Self.limitKey] as? NSNumber)?.intValue
    }

    func saveBaseline(_ limit: Int) throws {
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try PropertyListSerialization.data(
                fromPropertyList: [Self.limitKey: limit],
                format: .xml,
                options: 0
            )
            try data.write(to: url, options: .atomic)
        } catch {
            throw ChargeControlBackendError.backendFailure("원래 충전 한도를 보관하지 못했습니다: \(error.localizedDescription)")
        }
    }

    func clearBaseline() throws {
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
            throw ChargeControlBackendError.backendFailure("보관한 원래 충전 한도를 정리하지 못했습니다: \(error.localizedDescription)")
        }
    }
}
