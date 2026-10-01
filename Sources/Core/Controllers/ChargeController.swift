import Foundation
import Shared

public protocol ChargeController: Sendable {
    func setChargingEnabled(_ enabled: Bool) async throws
    func setTemporaryOverride(until: Date?) async throws
    /// 제어 OFF 시 helper가 건 충전 제한을 풀고 시스템 충전 한도를 원래 값으로 되돌린다.
    func releaseControl() async throws
    func getControllerStatus() async -> ControllerStatus
    func selfTest() async -> ControllerSelfTestResult
}
