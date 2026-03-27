import Foundation

@objcMembers
public class HelperRequestDTO: NSObject, NSSecureCoding {
    public static let supportsSecureCoding = true

    public let requestIdentifier: String
    public let sentAt: Date

    public init(
        requestIdentifier: String = UUID().uuidString,
        sentAt: Date = .now
    ) {
        self.requestIdentifier = requestIdentifier
        self.sentAt = sentAt
    }

    public required init?(coder: NSCoder) {
        guard
            let requestIdentifier = coder.decodeObject(of: NSString.self, forKey: "requestIdentifier") as String?,
            let sentAt = coder.decodeObject(of: NSDate.self, forKey: "sentAt") as Date?
        else {
            return nil
        }

        self.requestIdentifier = requestIdentifier
        self.sentAt = sentAt
    }

    public func encode(with coder: NSCoder) {
        coder.encode(requestIdentifier as NSString, forKey: "requestIdentifier")
        coder.encode(sentAt as NSDate, forKey: "sentAt")
    }
}

public final class HelperSelfTestRequestDTO: HelperRequestDTO {}

public final class HelperCapabilityProbeRequestDTO: HelperRequestDTO {}

@objcMembers
public final class HelperSetChargingEnabledRequestDTO: HelperRequestDTO {
    public let enabled: Bool

    public init(
        enabled: Bool,
        requestIdentifier: String = UUID().uuidString,
        sentAt: Date = .now
    ) {
        self.enabled = enabled
        super.init(requestIdentifier: requestIdentifier, sentAt: sentAt)
    }

    public required init?(coder: NSCoder) {
        self.enabled = coder.decodeBool(forKey: "enabled")
        super.init(coder: coder)
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(enabled, forKey: "enabled")
    }
}

@objcMembers
public final class HelperSetTemporaryOverrideRequestDTO: HelperRequestDTO {
    public let until: Date?

    public init(
        until: Date?,
        requestIdentifier: String = UUID().uuidString,
        sentAt: Date = .now
    ) {
        self.until = until
        super.init(requestIdentifier: requestIdentifier, sentAt: sentAt)
    }

    public required init?(coder: NSCoder) {
        self.until = coder.decodeObject(of: NSDate.self, forKey: "until") as Date?
        super.init(coder: coder)
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        if let until {
            coder.encode(until as NSDate, forKey: "until")
        }
    }
}

@objcMembers
public final class HelperXPCErrorDTO: NSObject, NSSecureCoding {
    public static let supportsSecureCoding = true

    public let domain: String
    public let code: String
    public let message: String
    public let suggestedFallbackModeRawValue: String
    public let failureReason: String?

    public init(
        domain: String,
        code: String,
        message: String,
        suggestedFallbackModeRawValue: String,
        failureReason: String? = nil
    ) {
        self.domain = domain
        self.code = code
        self.message = message
        self.suggestedFallbackModeRawValue = suggestedFallbackModeRawValue
        self.failureReason = failureReason
    }

    public required init?(coder: NSCoder) {
        guard
            let domain = coder.decodeObject(of: NSString.self, forKey: "domain") as String?,
            let code = coder.decodeObject(of: NSString.self, forKey: "code") as String?,
            let message = coder.decodeObject(of: NSString.self, forKey: "message") as String?,
            let suggestedFallbackModeRawValue = coder.decodeObject(of: NSString.self, forKey: "suggestedFallbackModeRawValue") as String?
        else {
            return nil
        }

        self.domain = domain
        self.code = code
        self.message = message
        self.suggestedFallbackModeRawValue = suggestedFallbackModeRawValue
        self.failureReason = coder.decodeObject(of: NSString.self, forKey: "failureReason") as String?
    }

    public func encode(with coder: NSCoder) {
        coder.encode(domain as NSString, forKey: "domain")
        coder.encode(code as NSString, forKey: "code")
        coder.encode(message as NSString, forKey: "message")
        coder.encode(suggestedFallbackModeRawValue as NSString, forKey: "suggestedFallbackModeRawValue")
        if let failureReason {
            coder.encode(failureReason as NSString, forKey: "failureReason")
        }
    }
}

@objcMembers
public final class ControllerStatusDTO: NSObject, NSSecureCoding {
    public static let supportsSecureCoding = true

    public let modeRawValue: String
    public let helperConnectionRawValue: String
    public let isChargingEnabledValue: NSNumber?
    public let temporaryOverrideUntil: Date?
    public let lastErrorDescription: String?
    public let checkedAt: Date

    public init(
        modeRawValue: String,
        helperConnectionRawValue: String,
        isChargingEnabledValue: NSNumber?,
        temporaryOverrideUntil: Date?,
        lastErrorDescription: String?,
        checkedAt: Date
    ) {
        self.modeRawValue = modeRawValue
        self.helperConnectionRawValue = helperConnectionRawValue
        self.isChargingEnabledValue = isChargingEnabledValue
        self.temporaryOverrideUntil = temporaryOverrideUntil
        self.lastErrorDescription = lastErrorDescription
        self.checkedAt = checkedAt
    }

    public convenience init(_ status: ControllerStatus) {
        self.init(
            modeRawValue: status.mode.rawValue,
            helperConnectionRawValue: status.helperConnection.rawValue,
            isChargingEnabledValue: status.isChargingEnabled.map(NSNumber.init(value:)),
            temporaryOverrideUntil: status.temporaryOverrideUntil,
            lastErrorDescription: status.lastErrorDescription,
            checkedAt: status.checkedAt
        )
    }

    public func toDomain() -> ControllerStatus {
        ControllerStatus(
            mode: ControllerStatus.Mode(rawValue: modeRawValue) ?? .readOnly,
            helperConnection: ControllerStatus.HelperConnection(rawValue: helperConnectionRawValue) ?? .unavailable,
            isChargingEnabled: isChargingEnabledValue?.boolValue,
            temporaryOverrideUntil: temporaryOverrideUntil,
            lastErrorDescription: lastErrorDescription,
            checkedAt: checkedAt
        )
    }

    public required init?(coder: NSCoder) {
        guard
            let modeRawValue = coder.decodeObject(of: NSString.self, forKey: "modeRawValue") as String?,
            let helperConnectionRawValue = coder.decodeObject(of: NSString.self, forKey: "helperConnectionRawValue") as String?,
            let checkedAt = coder.decodeObject(of: NSDate.self, forKey: "checkedAt") as Date?
        else {
            return nil
        }

        self.modeRawValue = modeRawValue
        self.helperConnectionRawValue = helperConnectionRawValue
        self.isChargingEnabledValue = coder.decodeObject(of: NSNumber.self, forKey: "isChargingEnabledValue")
        self.temporaryOverrideUntil = coder.decodeObject(of: NSDate.self, forKey: "temporaryOverrideUntil") as Date?
        self.lastErrorDescription = coder.decodeObject(of: NSString.self, forKey: "lastErrorDescription") as String?
        self.checkedAt = checkedAt
    }

    public func encode(with coder: NSCoder) {
        coder.encode(modeRawValue as NSString, forKey: "modeRawValue")
        coder.encode(helperConnectionRawValue as NSString, forKey: "helperConnectionRawValue")
        if let isChargingEnabledValue {
            coder.encode(isChargingEnabledValue, forKey: "isChargingEnabledValue")
        }
        if let temporaryOverrideUntil {
            coder.encode(temporaryOverrideUntil as NSDate, forKey: "temporaryOverrideUntil")
        }
        if let lastErrorDescription {
            coder.encode(lastErrorDescription as NSString, forKey: "lastErrorDescription")
        }
        coder.encode(checkedAt as NSDate, forKey: "checkedAt")
    }
}

@objcMembers
public final class ControllerSelfTestResultDTO: NSObject, NSSecureCoding {
    public static let supportsSecureCoding = true

    public let outcomeRawValue: String
    public let message: String
    public let checkedAt: Date

    public init(outcomeRawValue: String, message: String, checkedAt: Date) {
        self.outcomeRawValue = outcomeRawValue
        self.message = message
        self.checkedAt = checkedAt
    }

    public convenience init(_ result: ControllerSelfTestResult) {
        self.init(
            outcomeRawValue: result.outcome.rawValue,
            message: result.message,
            checkedAt: result.checkedAt
        )
    }

    public func toDomain() -> ControllerSelfTestResult {
        ControllerSelfTestResult(
            outcome: ControllerSelfTestResult.Outcome(rawValue: outcomeRawValue) ?? .failed,
            message: message,
            checkedAt: checkedAt
        )
    }

    public required init?(coder: NSCoder) {
        guard
            let outcomeRawValue = coder.decodeObject(of: NSString.self, forKey: "outcomeRawValue") as String?,
            let message = coder.decodeObject(of: NSString.self, forKey: "message") as String?,
            let checkedAt = coder.decodeObject(of: NSDate.self, forKey: "checkedAt") as Date?
        else {
            return nil
        }

        self.outcomeRawValue = outcomeRawValue
        self.message = message
        self.checkedAt = checkedAt
    }

    public func encode(with coder: NSCoder) {
        coder.encode(outcomeRawValue as NSString, forKey: "outcomeRawValue")
        coder.encode(message as NSString, forKey: "message")
        coder.encode(checkedAt as NSDate, forKey: "checkedAt")
    }
}

@objcMembers
public final class CapabilityStatusDTO: NSObject, NSSecureCoding {
    public static let supportsSecureCoding = true

    public let keyRawValue: String
    public let supportRawValue: String
    public let reason: String

    public init(keyRawValue: String, supportRawValue: String, reason: String) {
        self.keyRawValue = keyRawValue
        self.supportRawValue = supportRawValue
        self.reason = reason
    }

    public convenience init(_ status: CapabilityStatus) {
        self.init(
            keyRawValue: status.key.rawValue,
            supportRawValue: status.support.rawValue,
            reason: status.reason
        )
    }

    public func toDomain() -> CapabilityStatus {
        CapabilityStatus(
            key: CapabilityKey(rawValue: keyRawValue) ?? .chargeControl,
            support: CapabilitySupport(rawValue: supportRawValue) ?? .unsupported,
            reason: reason
        )
    }

    public required init?(coder: NSCoder) {
        guard
            let keyRawValue = coder.decodeObject(of: NSString.self, forKey: "keyRawValue") as String?,
            let supportRawValue = coder.decodeObject(of: NSString.self, forKey: "supportRawValue") as String?,
            let reason = coder.decodeObject(of: NSString.self, forKey: "reason") as String?
        else {
            return nil
        }

        self.keyRawValue = keyRawValue
        self.supportRawValue = supportRawValue
        self.reason = reason
    }

    public func encode(with coder: NSCoder) {
        coder.encode(keyRawValue as NSString, forKey: "keyRawValue")
        coder.encode(supportRawValue as NSString, forKey: "supportRawValue")
        coder.encode(reason as NSString, forKey: "reason")
    }
}

@objcMembers
public final class CapabilityReportDTO: NSObject, NSSecureCoding {
    public static let supportsSecureCoding = true

    public let statuses: [CapabilityStatusDTO]
    public let recommendedControllerModeRawValue: String

    public init(
        statuses: [CapabilityStatusDTO],
        recommendedControllerModeRawValue: String
    ) {
        self.statuses = statuses
        self.recommendedControllerModeRawValue = recommendedControllerModeRawValue
    }

    public convenience init(_ report: CapabilityReport) {
        self.init(
            statuses: report.statuses.map(CapabilityStatusDTO.init),
            recommendedControllerModeRawValue: report.recommendedControllerMode.rawValue
        )
    }

    public func toDomain() -> CapabilityReport {
        CapabilityReport(
            statuses: statuses.map { $0.toDomain() },
            recommendedControllerMode: ControllerStatus.Mode(rawValue: recommendedControllerModeRawValue) ?? .monitoringOnly
        )
    }

    public required init?(coder: NSCoder) {
        guard
            let recommendedControllerModeRawValue = coder.decodeObject(of: NSString.self, forKey: "recommendedControllerModeRawValue") as String?
        else {
            return nil
        }

        let allowed: [AnyClass] = [NSArray.self, CapabilityStatusDTO.self]
        self.statuses = coder.decodeObject(of: allowed, forKey: "statuses") as? [CapabilityStatusDTO] ?? []
        self.recommendedControllerModeRawValue = recommendedControllerModeRawValue
    }

    public func encode(with coder: NSCoder) {
        coder.encode(statuses as NSArray, forKey: "statuses")
        coder.encode(recommendedControllerModeRawValue as NSString, forKey: "recommendedControllerModeRawValue")
    }
}

@objcMembers
public final class HelperControllerStatusResponseDTO: NSObject, NSSecureCoding {
    public static let supportsSecureCoding = true

    public let requestIdentifier: String
    public let controllerStatus: ControllerStatusDTO
    public let error: HelperXPCErrorDTO?

    public init(
        requestIdentifier: String,
        controllerStatus: ControllerStatusDTO,
        error: HelperXPCErrorDTO? = nil
    ) {
        self.requestIdentifier = requestIdentifier
        self.controllerStatus = controllerStatus
        self.error = error
    }

    public required init?(coder: NSCoder) {
        guard
            let requestIdentifier = coder.decodeObject(of: NSString.self, forKey: "requestIdentifier") as String?,
            let controllerStatus = coder.decodeObject(of: ControllerStatusDTO.self, forKey: "controllerStatus")
        else {
            return nil
        }

        self.requestIdentifier = requestIdentifier
        self.controllerStatus = controllerStatus
        self.error = coder.decodeObject(of: HelperXPCErrorDTO.self, forKey: "error")
    }

    public func encode(with coder: NSCoder) {
        coder.encode(requestIdentifier as NSString, forKey: "requestIdentifier")
        coder.encode(controllerStatus, forKey: "controllerStatus")
        if let error {
            coder.encode(error, forKey: "error")
        }
    }
}

@objcMembers
public final class HelperSelfTestResponseDTO: NSObject, NSSecureCoding {
    public static let supportsSecureCoding = true

    public let requestIdentifier: String
    public let result: ControllerSelfTestResultDTO
    public let controllerStatus: ControllerStatusDTO
    public let error: HelperXPCErrorDTO?

    public init(
        requestIdentifier: String,
        result: ControllerSelfTestResultDTO,
        controllerStatus: ControllerStatusDTO,
        error: HelperXPCErrorDTO? = nil
    ) {
        self.requestIdentifier = requestIdentifier
        self.result = result
        self.controllerStatus = controllerStatus
        self.error = error
    }

    public required init?(coder: NSCoder) {
        guard
            let requestIdentifier = coder.decodeObject(of: NSString.self, forKey: "requestIdentifier") as String?,
            let result = coder.decodeObject(of: ControllerSelfTestResultDTO.self, forKey: "result"),
            let controllerStatus = coder.decodeObject(of: ControllerStatusDTO.self, forKey: "controllerStatus")
        else {
            return nil
        }

        self.requestIdentifier = requestIdentifier
        self.result = result
        self.controllerStatus = controllerStatus
        self.error = coder.decodeObject(of: HelperXPCErrorDTO.self, forKey: "error")
    }

    public func encode(with coder: NSCoder) {
        coder.encode(requestIdentifier as NSString, forKey: "requestIdentifier")
        coder.encode(result, forKey: "result")
        coder.encode(controllerStatus, forKey: "controllerStatus")
        if let error {
            coder.encode(error, forKey: "error")
        }
    }
}

@objcMembers
public final class HelperCapabilityProbeResponseDTO: NSObject, NSSecureCoding {
    public static let supportsSecureCoding = true

    public let requestIdentifier: String
    public let capabilityReport: CapabilityReportDTO
    public let controllerStatus: ControllerStatusDTO
    public let error: HelperXPCErrorDTO?

    public init(
        requestIdentifier: String,
        capabilityReport: CapabilityReportDTO,
        controllerStatus: ControllerStatusDTO,
        error: HelperXPCErrorDTO? = nil
    ) {
        self.requestIdentifier = requestIdentifier
        self.capabilityReport = capabilityReport
        self.controllerStatus = controllerStatus
        self.error = error
    }

    public required init?(coder: NSCoder) {
        guard
            let requestIdentifier = coder.decodeObject(of: NSString.self, forKey: "requestIdentifier") as String?,
            let capabilityReport = coder.decodeObject(of: CapabilityReportDTO.self, forKey: "capabilityReport"),
            let controllerStatus = coder.decodeObject(of: ControllerStatusDTO.self, forKey: "controllerStatus")
        else {
            return nil
        }

        self.requestIdentifier = requestIdentifier
        self.capabilityReport = capabilityReport
        self.controllerStatus = controllerStatus
        self.error = coder.decodeObject(of: HelperXPCErrorDTO.self, forKey: "error")
    }

    public func encode(with coder: NSCoder) {
        coder.encode(requestIdentifier as NSString, forKey: "requestIdentifier")
        coder.encode(capabilityReport, forKey: "capabilityReport")
        coder.encode(controllerStatus, forKey: "controllerStatus")
        if let error {
            coder.encode(error, forKey: "error")
        }
    }
}

@objcMembers
public final class HelperCommandResponseDTO: NSObject, NSSecureCoding {
    public static let supportsSecureCoding = true

    public let requestIdentifier: String
    public let controllerStatus: ControllerStatusDTO
    public let error: HelperXPCErrorDTO?

    public init(
        requestIdentifier: String,
        controllerStatus: ControllerStatusDTO,
        error: HelperXPCErrorDTO? = nil
    ) {
        self.requestIdentifier = requestIdentifier
        self.controllerStatus = controllerStatus
        self.error = error
    }

    public required init?(coder: NSCoder) {
        guard
            let requestIdentifier = coder.decodeObject(of: NSString.self, forKey: "requestIdentifier") as String?,
            let controllerStatus = coder.decodeObject(of: ControllerStatusDTO.self, forKey: "controllerStatus")
        else {
            return nil
        }

        self.requestIdentifier = requestIdentifier
        self.controllerStatus = controllerStatus
        self.error = coder.decodeObject(of: HelperXPCErrorDTO.self, forKey: "error")
    }

    public func encode(with coder: NSCoder) {
        coder.encode(requestIdentifier as NSString, forKey: "requestIdentifier")
        coder.encode(controllerStatus, forKey: "controllerStatus")
        if let error {
            coder.encode(error, forKey: "error")
        }
    }
}
