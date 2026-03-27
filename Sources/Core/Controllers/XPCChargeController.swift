import Foundation
import Shared

public protocol HelperCapabilityProbing: Sendable {
    func capabilityProbe() async throws -> HelperCapabilityProbeSummary
}

public actor XPCChargeController: ChargeController, HelperCapabilityProbing {
    private let transport: HelperServiceTransporting
    private let eventLogger: any EventLogging

    public init(
        transport: HelperServiceTransporting = NSXPCHelperServiceTransport(),
        eventLogger: any EventLogging = EventLogger()
    ) {
        self.transport = transport
        self.eventLogger = eventLogger
    }

    public func setChargingEnabled(_ enabled: Bool) async throws {
        do {
            let status = try await transport.setChargingEnabled(enabled)
            await eventLogger.record(
                level: .notice,
                category: .helperCommunication,
                message: "Helper에 충전 on/off 요청을 보냈습니다.",
                details: [
                    "command": "setChargingEnabled",
                    "enabled": String(enabled),
                    "mode": status.mode.rawValue,
                    "helperConnection": status.helperConnection.rawValue
                ],
                userFacingSummary: nil
            )
        } catch {
            await eventLogger.record(
                level: .error,
                category: .helperCommunication,
                message: "Helper 충전 on/off 요청이 실패했습니다: \(error.localizedDescription)",
                details: [
                    "command": "setChargingEnabled",
                    "enabled": String(enabled)
                ],
                userFacingSummary: "helper 제어 요청이 실패해 읽기 전용 상태를 유지합니다."
            )
            throw error
        }
    }

    public func setTemporaryOverride(until: Date?) async throws {
        do {
            let status = try await transport.setTemporaryOverride(until: until)
            await eventLogger.record(
                level: .notice,
                category: .helperCommunication,
                message: "Helper에 temporary override 요청을 보냈습니다.",
                details: [
                    "command": "setTemporaryOverride",
                    "until": until?.ISO8601Format() ?? "nil",
                    "mode": status.mode.rawValue
                ],
                userFacingSummary: nil
            )
        } catch {
            await eventLogger.record(
                level: .error,
                category: .helperCommunication,
                message: "Helper temporary override 요청이 실패했습니다: \(error.localizedDescription)",
                details: [
                    "command": "setTemporaryOverride",
                    "until": until?.ISO8601Format() ?? "nil"
                ],
                userFacingSummary: "helper override 요청이 실패해 읽기 전용 상태를 유지합니다."
            )
            throw error
        }
    }

    public func getControllerStatus() async -> ControllerStatus {
        do {
            let status = try await transport.fetchControllerStatus()
            await eventLogger.record(
                level: .info,
                category: .helperCommunication,
                message: "Helper 상태를 조회했습니다.",
                details: [
                    "mode": status.mode.rawValue,
                    "helperConnection": status.helperConnection.rawValue
                ],
                userFacingSummary: nil
            )
            return status
        } catch {
            await eventLogger.record(
                level: .error,
                category: .helperCommunication,
                message: "Helper 상태 조회가 실패했습니다: \(error.localizedDescription)",
                details: [
                    "command": "fetchControllerStatus"
                ],
                userFacingSummary: "helper 연결 실패로 read-only fallback을 적용합니다."
            )
            return ControllerStatus(
                mode: .readOnly,
                helperConnection: .disconnected,
                isChargingEnabled: nil,
                temporaryOverrideUntil: nil,
                lastErrorDescription: error.localizedDescription,
                checkedAt: .now
            )
        }
    }

    public func selfTest() async -> ControllerSelfTestResult {
        do {
            let summary = try await transport.selfTest()
            let result = summary.result
            await eventLogger.record(
                level: result.outcome == .failed ? .error : (result.outcome == .degraded ? .warning : .notice),
                category: .selfTest,
                message: result.message,
                details: [
                    "outcome": result.outcome.rawValue,
                    "mode": summary.status?.mode.rawValue ?? "unknown"
                ],
                userFacingSummary: result.outcome == .failed ? "helper self-test 실패로 read-only 상태를 유지합니다." : nil
            )
            return result
        } catch {
            await eventLogger.record(
                level: .error,
                category: .selfTest,
                message: "Helper self-test 호출이 실패했습니다: \(error.localizedDescription)",
                details: [:],
                userFacingSummary: "helper self-test 실패로 read-only 상태를 유지합니다."
            )
            return ControllerSelfTestResult(
                outcome: .failed,
                message: error.localizedDescription,
                checkedAt: .now
            )
        }
    }

    public func capabilityProbe() async throws -> HelperCapabilityProbeSummary {
        do {
            let summary = try await transport.capabilityProbe()
            await eventLogger.record(
                level: .notice,
                category: .capabilityProbe,
                message: "Helper capability probe를 완료했습니다.",
                details: [
                    "recommendedMode": summary.report.recommendedControllerMode.rawValue,
                    "helperMode": summary.status.mode.rawValue
                ],
                userFacingSummary: nil
            )
            return summary
        } catch {
            await eventLogger.record(
                level: .error,
                category: .capabilityProbe,
                message: "Helper capability probe가 실패했습니다: \(error.localizedDescription)",
                details: [:],
                userFacingSummary: "helper capability probe 실패로 read-only fallback을 적용합니다."
            )
            throw error
        }
    }
}
