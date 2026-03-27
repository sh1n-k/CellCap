import Foundation
import Shared

protocol MenuBarPresenting {
    var batteryPercentText: String { get }
    var chargeStateTitle: String { get }
    var summarySentence: String { get }
    var powerStatusText: String { get }
    var helperStatusText: String { get }
    var controllerModeLabel: String { get }
    var helperInstallStateText: String { get }
    var helperInstallReasonText: String? { get }
    var compactHelperSummaryText: String { get }
    var temporaryOverrideSummaryText: String { get }
    var advancedSectionStatusText: String { get }
    var controlNoticeTitle: String { get }
    var temporaryOverrideNoticeTitle: String { get }
    var isReadOnlyPresentation: Bool { get }
    var selectedOverrideDurationLabel: String { get }
    var menuBarSymbolName: String { get }
    var diagnosticsSummaryText: String { get }
    func capabilityLabel(for support: CapabilitySupport) -> String
    func capabilityTitle(for key: CapabilityKey) -> String
}

struct MenuBarPresentation: MenuBarPresenting {
    let appState: AppState
    let capabilityReport: CapabilityReport
    let diagnosticsSummary: DiagnosticsSummary?
    let helperInstallStatus: HelperInstallStatus?
    let controlAvailability: MenuBarViewModel.ControlAvailability
    let temporaryOverrideAvailability: MenuBarViewModel.ControlAvailability
    let shouldAutoExpandAdvancedSection: Bool
    let overrideDurationMinutes: Double
    let now: Date

    var batteryPercentText: String {
        appState.battery.map { "\($0.chargePercent)%" } ?? "배터리 없음"
    }

    var chargeStateTitle: String {
        switch appState.chargeState {
        case .charging:
            return isPowerConnected && isCharging ? "다시 충전 중" : "다시 충전 준비"
        case .holdingAtLimit:
            return isPowerConnected ? "상한 유지 중" : "상한 기준 유지"
        case .waitingForRecharge:
            return "재충전 대기 중"
        case .temporaryOverride:
            return isPowerConnected ? "임시 해제 중" : "임시 해제 예약"
        case .suspended:
            return "제어 중단"
        case .errorReadOnly:
            return "읽기 전용 오류"
        }
    }

    var summarySentence: String {
        switch appState.chargeState {
        case .charging:
            if isPowerConnected && isCharging {
                return "하한 아래로 내려가 충전을 다시 시작했습니다."
            }
            if isPowerConnected {
                return "하한 아래라 충전을 다시 허용했습니다. 곧 충전 상태가 반영됩니다."
            }
            return "하한 아래입니다. 전원을 연결하면 다시 충전합니다."
        case .holdingAtLimit:
            if isPowerConnected {
                return "상한에 도달해 충전을 멈추고 유지하고 있습니다."
            }
            return "상한 기준이 적용 중입니다. 전원을 연결해도 바로 충전하지 않습니다."
        case .waitingForRecharge:
            if isPowerConnected {
                return "하한 아래로 내려갈 때까지 충전을 멈추고 대기합니다."
            }
            return "아직 재충전 구간이 아닙니다. 더 내려가면 전원 연결 시 다시 충전합니다."
        case .temporaryOverride:
            if isPowerConnected && isCharging {
                return "상한을 잠시 해제해 100%까지 충전할 수 있습니다."
            }
            if isPowerConnected {
                return "상한 해제가 적용 중입니다. 필요 시 100%까지 충전합니다."
            }
            return "상한 해제가 적용 중입니다. 전원을 연결하면 100% 충전을 허용합니다."
        case .suspended:
            return "충전 제어를 멈추고 배터리 상태만 확인하고 있습니다."
        case .errorReadOnly:
            return appState.controllerStatus.lastErrorDescription
                ?? "helper 상태를 확인할 수 없어 충전 제어 없이 표시만 유지합니다."
        }
    }

    var powerStatusText: String {
        guard let battery = appState.battery else { return "배터리 정보 없음" }
        return battery.isPowerConnected ? "전원 연결됨" : "배터리 사용 중"
    }

    var helperStatusText: String {
        if let helperInstallStatus {
            switch helperInstallStatus.state {
            case .notInstalled:
                return "helper 미설치"
            case .installedButNotBootstrapped:
                return "helper 미기동"
            case .bootstrapped:
                return "helper 등록됨"
            case .xpcReachable:
                break
            case .permissionMismatch:
                return "helper 권한 불일치"
            case .versionMismatch:
                return "helper 버전 불일치"
            }
        }

        switch appState.controllerStatus.helperConnection {
        case .connected:
            return "helper 연결 정상"
        case .disconnected:
            return "helper 연결 끊김"
        case .unavailable:
            return "helper 미구현"
        }
    }

    var controllerModeLabel: String {
        switch appState.controllerStatus.mode {
        case .fullControl:
            return "Full Control"
        case .readOnly:
            return "Read-only"
        case .monitoringOnly:
            return "Monitoring-only"
        }
    }

    var helperInstallStateText: String {
        guard let helperInstallStatus else {
            return "설치 상태 미확인"
        }

        switch helperInstallStatus.state {
        case .notInstalled:
            return "미설치"
        case .installedButNotBootstrapped:
            return "설치됨, 미기동"
        case .bootstrapped:
            return "launchd 등록"
        case .xpcReachable:
            return "XPC 연결 확인"
        case .permissionMismatch:
            return "권한 불일치"
        case .versionMismatch:
            return "버전 불일치"
        }
    }

    var helperInstallReasonText: String? {
        helperInstallStatus?.reason
            ?? capabilityReport.status(for: .helperInstallation)?.reason
            ?? capabilityReport.status(for: .helperPrivilege)?.reason
    }

    var compactHelperSummaryText: String {
        "\(helperStatusText) · \(helperInstallStateText)"
    }

    var temporaryOverrideSummaryText: String {
        if isTemporaryOverrideActive {
            return summarySentence
        }

        if let reason = temporaryOverrideAvailability.reason {
            return reason
        }

        return "선택한 \(selectedOverrideDurationLabel) 동안 상한을 해제한 뒤 기존 정책으로 복귀합니다."
    }

    var advancedSectionStatusText: String {
        shouldAutoExpandAdvancedSection ? "확인 필요" : "정상"
    }

    var controlNoticeTitle: String {
        switch appState.controllerStatus.mode {
        case .fullControl:
            return "정책 변경 가능"
        case .readOnly:
            return "지금은 읽기 전용 상태입니다"
        case .monitoringOnly:
            return "지금은 관측 전용 상태입니다"
        }
    }

    var temporaryOverrideNoticeTitle: String {
        switch appState.controllerStatus.mode {
        case .fullControl:
            return "임시 해제 가능"
        case .readOnly:
            return "지금은 임시 해제를 시작할 수 없습니다"
        case .monitoringOnly:
            return "지금은 임시 해제를 사용할 수 없습니다"
        }
    }

    var isReadOnlyPresentation: Bool {
        !controlAvailability.isEnabled || appState.controllerStatus.mode != .fullControl
    }

    var selectedOverrideDurationLabel: String {
        switch Int(overrideDurationMinutes.rounded()) {
        case 30:
            return "30분"
        case 60:
            return "1시간"
        case 120:
            return "2시간"
        case 240:
            return "4시간"
        default:
            return "\(Int(overrideDurationMinutes.rounded()))분"
        }
    }

    var menuBarSymbolName: String {
        switch appState.chargeState {
        case .holdingAtLimit:
            return "battery.100.bolt"
        case .charging, .temporaryOverride:
            return "bolt.batteryblock"
        case .waitingForRecharge:
            return "battery.75"
        case .suspended:
            return "pause.circle"
        case .errorReadOnly:
            return "exclamationmark.triangle.fill"
        }
    }

    var diagnosticsSummaryText: String {
        guard let diagnosticsSummary else {
            return "진단 요약이 아직 준비되지 않았습니다."
        }

        var parts: [String] = []
        if let state = diagnosticsSummary.currentChargeState?.rawValue {
            parts.append("상태 \(state)")
        }
        if let mode = diagnosticsSummary.currentControllerMode?.rawValue {
            parts.append("모드 \(mode)")
        }
        if let fallback = diagnosticsSummary.lastReadOnlyFallbackReason {
            parts.append("fallback \(fallback)")
        }
        if let helperInstallState = diagnosticsSummary.helperInstallState?.rawValue {
            parts.append("helper \(helperInstallState)")
        }
        return parts.isEmpty ? "진단 이벤트가 아직 없습니다." : parts.joined(separator: " / ")
    }

    private var battery: BatterySnapshot? {
        appState.battery
    }

    private var isPowerConnected: Bool {
        battery?.isPowerConnected == true
    }

    private var isCharging: Bool {
        battery?.isCharging == true
    }

    func capabilityLabel(for support: CapabilitySupport) -> String {
        switch support {
        case .supported:
            return "지원"
        case .unsupported:
            return "미지원"
        case .experimental:
            return "실험적"
        case .readOnlyFallback:
            return "읽기 전용"
        }
    }

    func capabilityTitle(for key: CapabilityKey) -> String {
        switch key {
        case .appleSilicon:
            return "Apple Silicon"
        case .macOSVersion:
            return "macOS 26+"
        case .batteryObservation:
            return "배터리 읽기"
        case .powerSourceObservation:
            return "전원 연결 감지"
        case .sleepWakeResynchronization:
            return "sleep/wake 재동기화"
        case .helperInstallation:
            return "Helper 설치"
        case .helperPrivilege:
            return "Helper 권한"
        case .chargeControl:
            return "충전 제어"
        }
    }

    private var isTemporaryOverrideActive: Bool {
        appState.policy.isTemporaryOverrideActive(at: now)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
