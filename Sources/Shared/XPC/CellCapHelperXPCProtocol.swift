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
}

public enum CellCapHelperXPC {
    public static let serviceName = "com.shin.cellcap.helper"
    public static let contractVersion = "dev-mcl-v2"
    public static let installedBinaryPath = "/Library/PrivilegedHelperTools/com.shin.cellcap.helper"
    public static let launchDaemonPlistPath = "/Library/LaunchDaemons/com.shin.cellcap.helper.plist"
    /// helper가 macOS 충전 한도를 처음 바꾸기 전의 사용자 값을 보관하는 파일. uninstall 스크립트가 이 값으로 복원한다.
    public static let chargeLimitBaselinePath = "/Library/Application Support/CellCap/charge-limit-baseline.plist"

    public static func makeRemoteInterface() -> NSXPCInterface {
        NSXPCInterface(with: CellCapHelperXPCProtocol.self)
    }
}
