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
    public static let contractVersion = "dev-smc-v1"
    public static let installedBinaryPath = "/Library/PrivilegedHelperTools/com.shin.cellcap.helper"
    public static let launchDaemonPlistPath = "/Library/LaunchDaemons/com.shin.cellcap.helper.plist"

    public static func makeRemoteInterface() -> NSXPCInterface {
        NSXPCInterface(with: CellCapHelperXPCProtocol.self)
    }
}
