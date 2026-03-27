import Foundation
import Shared

public protocol ChargeController: Sendable {
    func setChargingEnabled(_ enabled: Bool) async throws
    func setTemporaryOverride(until: Date?) async throws
    func getControllerStatus() async -> ControllerStatus
    func selfTest() async -> ControllerSelfTestResult
}
