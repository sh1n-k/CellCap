import Darwin
import Foundation
import Shared

public protocol SystemEnvironmentProviding: Sendable {
    var operatingSystemVersion: OperatingSystemVersion { get }
    func isAppleSilicon() -> Bool
}

public struct ProcessInfoEnvironmentProvider: SystemEnvironmentProviding {
    public init() {}

    public var operatingSystemVersion: OperatingSystemVersion {
        ProcessInfo.processInfo.operatingSystemVersion
    }

    public func isAppleSilicon() -> Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return result == 0 && value == 1
    }
}

public protocol CapabilityChecking: Sendable {
    func evaluate(snapshot: BatterySnapshot?) -> CapabilityReport
}

public struct CapabilityChecker: CapabilityChecking {
    private let environment: any SystemEnvironmentProviding

    public init(environment: any SystemEnvironmentProviding = ProcessInfoEnvironmentProvider()) {
        self.environment = environment
    }

    public func evaluate(snapshot: BatterySnapshot?) -> CapabilityReport {
        let isAppleSilicon = environment.isAppleSilicon()
        let osVersion = environment.operatingSystemVersion
        let isSupportedOS = osVersion.majorVersion >= 26
        let hasBattery = snapshot?.isBatteryPresent == true
        let canAttemptPrivateControl = isAppleSilicon && isSupportedOS && hasBattery

        let statuses = [
            CapabilityStatus(
                key: .appleSilicon,
                support: isAppleSilicon ? .supported : .unsupported,
                reason: isAppleSilicon
                    ? "Apple Silicon 환경입니다."
                    : "이 앱은 Apple Silicon 전용으로 설계되었습니다."
            ),
            CapabilityStatus(
                key: .macOSVersion,
                support: isSupportedOS ? .supported : .unsupported,
                reason: isSupportedOS
                    ? "macOS 26+ 조건을 만족합니다."
                    : "macOS 26 이상에서만 전체 기능을 목표로 합니다."
            ),
            CapabilityStatus(
                key: .batteryObservation,
                support: hasBattery ? .supported : .unsupported,
                reason: hasBattery
                    ? "내장 배터리 상태를 읽을 수 있습니다."
                    : "내장 배터리를 찾지 못해 배터리 관측을 수행할 수 없습니다."
            ),
            CapabilityStatus(
                key: .powerSourceObservation,
                support: hasBattery ? .supported : .readOnlyFallback,
                reason: hasBattery
                    ? "전원 연결 여부를 공개 전원 소스 API로 관측할 수 있습니다."
                    : "배터리 미탑재 장비에서는 전원 소스 판정이 제한되어 monitoring-only로 남깁니다."
            ),
            CapabilityStatus(
                key: .sleepWakeResynchronization,
                support: (isAppleSilicon && isSupportedOS) ? .supported : .experimental,
                reason: (isAppleSilicon && isSupportedOS)
                    ? "sleep/wake 알림 기반 재동기화 훅을 사용할 수 있습니다."
                    : "환경은 비권장이지만 sleep/wake 알림 자체는 시도할 수 있습니다."
            ),
            CapabilityStatus(
                key: .helperInstallation,
                support: canAttemptPrivateControl ? .readOnlyFallback : .unsupported,
                reason: canAttemptPrivateControl
                    ? "helper 설치 상태는 앱 런타임이 launchd와 파일시스템에서 확인합니다."
                    : "이 환경에서는 helper 설치 여부와 관계없이 충전 제어를 시도하지 않습니다."
            ),
            CapabilityStatus(
                key: .helperPrivilege,
                support: canAttemptPrivateControl ? .readOnlyFallback : .unsupported,
                reason: canAttemptPrivateControl
                    ? "helper root 권한 상태는 capability probe와 self-test에서 확인합니다."
                    : "이 환경에서는 helper 권한을 요구하지 않습니다."
            ),
            CapabilityStatus(
                key: .chargeControl,
                support: canAttemptPrivateControl ? .experimental : .unsupported,
                reason: canAttemptPrivateControl
                    ? "비문서화된 SMC 기반 helper가 준비되면 충전 제어를 시도할 수 있습니다. 권한 미승인 또는 backend 실패 시 read-only로 내려갑니다."
                    : "현재 환경에서는 충전 제어를 시도하지 않고 monitoring-only fallback만 제공합니다."
            )
        ]

        return CapabilityReport(
            statuses: statuses,
            recommendedControllerMode: canAttemptPrivateControl ? .readOnly : .monitoringOnly
        )
    }
}
