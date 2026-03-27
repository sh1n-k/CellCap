import Foundation
import Shared

public struct DiagnosticsExportArtifact: Sendable, Equatable {
    public var suggestedFilename: String
    public var contentType: String
    public var utf8Contents: String

    public init(
        suggestedFilename: String,
        contentType: String,
        utf8Contents: String
    ) {
        self.suggestedFilename = suggestedFilename
        self.contentType = contentType
        self.utf8Contents = utf8Contents
    }
}

public protocol EventLogging: Sendable {
    func record(_ event: DiagnosticEvent) async
    func record(
        level: DiagnosticLogLevel,
        category: DiagnosticEventCategory,
        message: String,
        details: [String: String],
        userFacingSummary: String?
    ) async
    func recentEvents(limit: Int?) async -> [DiagnosticEvent]
    func diagnosticsSummary(currentUpdate: AppRuntimeUpdate?) async -> DiagnosticsSummary
    func exportDiagnostics(currentUpdate: AppRuntimeUpdate?) async throws -> DiagnosticsExportArtifact
}

private struct DiagnosticsExportEnvelope: Codable {
    var summary: DiagnosticsSummary
    var events: [DiagnosticEvent]
}

public actor EventLogger: EventLogging {
    private let maxStoredEvents: Int
    private var events: [DiagnosticEvent]

    public init(maxStoredEvents: Int = 500, seedEvents: [DiagnosticEvent] = []) {
        self.maxStoredEvents = max(10, maxStoredEvents)
        self.events = Array(seedEvents.suffix(maxStoredEvents))
    }

    public func record(_ event: DiagnosticEvent) {
        events.append(event)
        if events.count > maxStoredEvents {
            events.removeFirst(events.count - maxStoredEvents)
        }
    }

    public func record(
        level: DiagnosticLogLevel,
        category: DiagnosticEventCategory,
        message: String,
        details: [String: String] = [:],
        userFacingSummary: String? = nil
    ) {
        let sanitizedDetails = details
            .filter { !$0.key.lowercased().contains("token") && !$0.key.lowercased().contains("password") }
            .mapValues { String($0.prefix(240)) }

        record(
            DiagnosticEvent(
                level: level,
                category: category,
                message: message,
                details: sanitizedDetails,
                userFacingSummary: userFacingSummary
            )
        )
    }

    public func recentEvents(limit: Int? = nil) -> [DiagnosticEvent] {
        guard let limit else { return events }
        return Array(events.suffix(max(0, limit)))
    }

    public func diagnosticsSummary(currentUpdate: AppRuntimeUpdate?) -> DiagnosticsSummary {
        let lastCapabilityEvent = events.last { $0.category == .capabilityProbe }
        let lastSelfTestEvent = events.last { $0.category == .selfTest }
        let recentErrors = events
            .filter { $0.level == .error || ($0.category == .helperCommunication && $0.level == .warning) }
            .suffix(5)
            .map(\.message)
        let fallbackReason = events.reversed().first {
            guard let summary = $0.userFacingSummary else { return false }
            return summary.contains("read-only")
                || summary.contains("읽기 전용")
                || summary.contains("관측 전용")
                || summary.contains("helper")
        }?.userFacingSummary

        return DiagnosticsSummary(
            generatedAt: .now,
            eventCount: events.count,
            currentChargeState: currentUpdate?.appState.chargeState,
            currentControllerMode: currentUpdate?.appState.controllerStatus.mode,
            currentPolicyUpperLimit: currentUpdate?.appState.policy.upperLimit,
            currentRechargeThreshold: currentUpdate?.appState.policy.rechargeThreshold,
            lastTransitionReason: currentUpdate?.transitionReason.rawValue,
            lastCapabilityProbeMessage: lastCapabilityEvent?.message,
            lastCapabilityProbeAt: lastCapabilityEvent?.timestamp,
            lastSelfTestMessage: lastSelfTestEvent?.message,
            lastSelfTestAt: lastSelfTestEvent?.timestamp,
            lastReadOnlyFallbackReason: fallbackReason,
            recentErrorMessages: Array(recentErrors)
        )
    }

    public func exportDiagnostics(currentUpdate: AppRuntimeUpdate?) throws -> DiagnosticsExportArtifact {
        let summary = diagnosticsSummary(currentUpdate: currentUpdate)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let envelope = DiagnosticsExportEnvelope(summary: summary, events: events)
        let data = try encoder.encode(envelope)
        let timestamp = Self.filenameFormatter.string(from: summary.generatedAt)
        let filename = "CellCap-Diagnostics-\(timestamp).json"

        record(
            DiagnosticEvent(
                level: .notice,
                category: .export,
                message: "진단 export를 생성했습니다.",
                details: [
                    "eventCount": String(events.count),
                    "filename": filename
                ]
            )
        )

        return DiagnosticsExportArtifact(
            suggestedFilename: filename,
            contentType: "application/json",
            utf8Contents: String(decoding: data, as: UTF8.self)
        )
    }

    private static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
