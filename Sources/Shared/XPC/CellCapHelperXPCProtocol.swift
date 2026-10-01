import Foundation

@objc public protocol CellCapHelperXPCProtocol {
    func fetchControllerStatus(
        _ request: HelperRequestDTO,
        withReply reply: @escaping (HelperControllerStatusResponseDTO) -> Void
    )

    func selfTest(
        _ request: HelperSelfTestRequestDTO,
        withReply reply: @escaping (HelperSelfTestResponseDTO) -> Void
    )

    func capabilityProbe(
        _ request: HelperCapabilityProbeRequestDTO,
        withReply reply: @escaping (HelperCapabilityProbeResponseDTO) -> Void
    )

    func setChargingEnabled(
        _ request: HelperSetChargingEnabledRequestDTO,
        withReply reply: @escaping (HelperCommandResponseDTO) -> Void
    )

    func setTemporaryOverride(
        _ request: HelperSetTemporaryOverrideRequestDTO,
        withReply reply: @escaping (HelperCommandResponseDTO) -> Void
    )

    /// 사용자가 제어를 끄면 helper가 건 충전 제한을 풀고, 시스템 충전 한도를 CellCap 개입 전 값으로 되돌린다.
    /// 최근 명령 실패로 read-only 상태여도 실행된다.
    func releaseControl(
        _ request: HelperRequestDTO,
        withReply reply: @escaping (HelperCommandResponseDTO) -> Void
    )
}

public enum CellCapHelperXPC {
    public static let serviceName = "com.shin.cellcap.helper"
    /// helper가 XPC 연결을 허용하는 앱의 서명 식별자. release_common.sh의 APP_BUNDLE_IDENTIFIER와 같은 값을 유지한다.
    public static let clientBundleIdentifier = "com.shin.cellcap.app"
    public static let contractVersion = "dev-smapp-v1"
    /// SMAppService.daemon(plistName:)으로 등록하는 앱 번들 내장 LaunchDaemon plist 이름과 번들 기준 경로.
    public static let launchDaemonPlistName = "com.shin.cellcap.helper.plist"
    public static let bundledLaunchDaemonPlistPath = "Contents/Library/LaunchDaemons/com.shin.cellcap.helper.plist"
    public static let bundledHelperProgramPath = "Contents/MacOS/CellCapHelper"
    /// 시스템 설정의 백그라운드 허용 목록에서는 helper가 CellCap 항목 아래로 표시된다.
    public static let backgroundApprovalGuidance =
        "시스템 설정 > 일반 > 로그인 항목 및 확장 프로그램 > 백그라운드에서 허용에서 CellCap을 켜세요. 이미 켜져 있으면 껐다가 다시 켜세요."
    /// sudo 스크립트나 pkg로 설치하던 이전 방식의 경로. 남아 있으면 앱 내장 helper 등록과 충돌하므로 감지에만 쓴다.
    public static let legacyInstalledBinaryPath = "/Library/PrivilegedHelperTools/com.shin.cellcap.helper"
    public static let legacyLaunchDaemonPlistPath = "/Library/LaunchDaemons/com.shin.cellcap.helper.plist"
    /// helper가 macOS 충전 한도를 처음 바꾸기 전의 사용자 값을 보관하는 파일. uninstall 스크립트가 이 값으로 복원한다.
    public static let chargeLimitBaselinePath = "/Library/Application Support/CellCap/charge-limit-baseline.plist"

    public static func makeRemoteInterface() -> NSXPCInterface {
        NSXPCInterface(with: CellCapHelperXPCProtocol.self)
    }
}
