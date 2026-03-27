import Foundation

public class HelperRequestDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let requestedAt: Date

    public init(requestedAt: Date = .now) {
        self.requestedAt = requestedAt
    }

    public required init?(coder: NSCoder) {
        guard let requestedAt = coder.decodeObject(of: NSDate.self, forKey: "requestedAt") as Date? else {
            return nil
        }

        self.requestedAt = requestedAt
    }

    public func encode(with coder: NSCoder) {
        coder.encode(requestedAt as NSDate, forKey: "requestedAt")
    }
}

public final class HelperSelfTestRequestDTO: HelperRequestDTO {}

public final class HelperCapabilityProbeRequestDTO: HelperRequestDTO {}

public final class HelperSetChargingEnabledRequestDTO: HelperRequestDTO {
    public let enabled: Bool

    public init(enabled: Bool, requestedAt: Date = .now) {
        self.enabled = enabled
        super.init(requestedAt: requestedAt)
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

public final class HelperSetTemporaryOverrideRequestDTO: HelperRequestDTO {
    public let until: Date?

    public init(until: Date?, requestedAt: Date = .now) {
        self.until = until
        super.init(requestedAt: requestedAt)
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

public final class HelperXPCErrorDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let code: String
    public let message: String
    public let isRetryable: Bool

    public init(code: String, message: String, isRetryable: Bool) {
        self.code = code
        self.message = message
        self.isRetryable = isRetryable
    }

    public required init?(coder: NSCoder) {
        guard
            let code = coder.decodeObject(of: NSString.self, forKey: "code") as String?,
            let message = coder.decodeObject(of: NSString.self, forKey: "message") as String?
        else {
            return nil
        }

        self.code = code
        self.message = message
        self.isRetryable = coder.decodeBool(forKey: "isRetryable")
    }

    public func encode(with coder: NSCoder) {
        coder.encode(code as NSString, forKey: "code")
        coder.encode(message as NSString, forKey: "message")
        coder.encode(isRetryable, forKey: "isRetryable")
    }
}

public final class ControllerStatusDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let modeRawValue: String
    public let helperConnectionRawValue: String
    public let isChargingEnabled: NSNumber?
    public let temporaryOverrideUntil: Date?
    public let lastErrorDescription: String?
    public let checkedAt: Date

    public init(status: ControllerStatus) {
        self.modeRawValue = status.mode.rawValue
        self.helperConnectionRawValue = status.helperConnection.rawValue
        self.isChargingEnabled = status.isChargingEnabled.map(NSNumber.init(value:))
        self.temporaryOverrideUntil = status.temporaryOverrideUntil
        self.lastErrorDescription = status.lastErrorDescription
        self.checkedAt = status.checkedAt
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
        self.isChargingEnabled = coder.decodeObject(of: NSNumber.self, forKey: "isChargingEnabled")
        self.temporaryOverrideUntil = coder.decodeObject(of: NSDate.self, forKey: "temporaryOverrideUntil") as Date?
        self.lastErrorDescription = coder.decodeObject(of: NSString.self, forKey: "lastErrorDescription") as String?
        self.checkedAt = checkedAt
    }

    public func encode(with coder: NSCoder) {
        coder.encode(modeRawValue as NSString, forKey: "modeRawValue")
        coder.encode(helperConnectionRawValue as NSString, forKey: "helperConnectionRawValue")
        if let isChargingEnabled {
            coder.encode(isChargingEnabled, forKey: "isChargingEnabled")
        }
        if let temporaryOverrideUntil {
            coder.encode(temporaryOverrideUntil as NSDate, forKey: "temporaryOverrideUntil")
        }
        if let lastErrorDescription {
            coder.encode(lastErrorDescription as NSString, forKey: "lastErrorDescription")
        }
        coder.encode(checkedAt as NSDate, forKey: "checkedAt")
    }

    public func makeModel() -> ControllerStatus {
        ControllerStatus(
            mode: ControllerStatus.Mode(rawValue: modeRawValue) ?? .readOnly,
            helperConnection: ControllerStatus.HelperConnection(rawValue: helperConnectionRawValue) ?? .unavailable,
            isChargingEnabled: isChargingEnabled?.boolValue,
            temporaryOverrideUntil: temporaryOverrideUntil,
            lastErrorDescription: lastErrorDescription,
            checkedAt: checkedAt
        )
    }
}

public final class ControllerSelfTestResultDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let outcomeRawValue: String
    public let message: String
    public let checkedAt: Date

    public init(result: ControllerSelfTestResult) {
        self.outcomeRawValue = result.outcome.rawValue
        self.message = result.message
        self.checkedAt = result.checkedAt
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

    public func makeModel() -> ControllerSelfTestResult {
        ControllerSelfTestResult(
            outcome: ControllerSelfTestResult.Outcome(rawValue: outcomeRawValue) ?? .failed,
            message: message,
            checkedAt: checkedAt
        )
    }
}

public final class CapabilityStatusDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let keyRawValue: String
    public let supportRawValue: String
    public let reason: String

    public init(status: CapabilityStatus) {
        self.keyRawValue = status.key.rawValue
        self.supportRawValue = status.support.rawValue
        self.reason = status.reason
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

    public func makeModel() -> CapabilityStatus {
        CapabilityStatus(
            key: CapabilityKey(rawValue: keyRawValue) ?? .chargeControl,
            support: CapabilitySupport(rawValue: supportRawValue) ?? .readOnlyFallback,
            reason: reason
        )
    }
}

public final class CapabilityReportDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let statuses: [CapabilityStatusDTO]
    public let recommendedControllerModeRawValue: String
    public let helperInstallStatus: HelperInstallStatusDTO?

    public init(report: CapabilityReport) {
        self.statuses = report.statuses.map(CapabilityStatusDTO.init(status:))
        self.recommendedControllerModeRawValue = report.recommendedControllerMode.rawValue
        self.helperInstallStatus = report.helperInstallStatus.map(HelperInstallStatusDTO.init(status:))
    }

    public required init?(coder: NSCoder) {
        guard
            let statuses = coder.decodeObject(
                of: [NSArray.self, CapabilityStatusDTO.self],
                forKey: "statuses"
            ) as? [CapabilityStatusDTO],
            let recommendedControllerModeRawValue = coder.decodeObject(
                of: NSString.self,
                forKey: "recommendedControllerModeRawValue"
            ) as String?
        else {
            return nil
        }

        self.statuses = statuses
        self.recommendedControllerModeRawValue = recommendedControllerModeRawValue
        self.helperInstallStatus = coder.decodeObject(of: HelperInstallStatusDTO.self, forKey: "helperInstallStatus")
    }

    public func encode(with coder: NSCoder) {
        coder.encode(statuses as NSArray, forKey: "statuses")
        coder.encode(
            recommendedControllerModeRawValue as NSString,
            forKey: "recommendedControllerModeRawValue"
        )
        if let helperInstallStatus {
            coder.encode(helperInstallStatus, forKey: "helperInstallStatus")
        }
    }

    public func makeModel() -> CapabilityReport {
        CapabilityReport(
            statuses: statuses.map { $0.makeModel() },
            recommendedControllerMode: ControllerStatus.Mode(rawValue: recommendedControllerModeRawValue) ?? .monitoringOnly,
            helperInstallStatus: helperInstallStatus?.makeModel()
        )
    }
}

public final class HelperInstallStatusDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let stateRawValue: String
    public let serviceName: String
    public let helperPath: String
    public let plistPath: String
    public let helperVersion: String?
    public let expectedVersion: String?
    public let reason: String
    public let checkedAt: Date

    public init(status: HelperInstallStatus) {
        self.stateRawValue = status.state.rawValue
        self.serviceName = status.serviceName
        self.helperPath = status.helperPath
        self.plistPath = status.plistPath
        self.helperVersion = status.helperVersion
        self.expectedVersion = status.expectedVersion
        self.reason = status.reason
        self.checkedAt = status.checkedAt
    }

    public required init?(coder: NSCoder) {
        guard
            let stateRawValue = coder.decodeObject(of: NSString.self, forKey: "stateRawValue") as String?,
            let serviceName = coder.decodeObject(of: NSString.self, forKey: "serviceName") as String?,
            let helperPath = coder.decodeObject(of: NSString.self, forKey: "helperPath") as String?,
            let plistPath = coder.decodeObject(of: NSString.self, forKey: "plistPath") as String?,
            let reason = coder.decodeObject(of: NSString.self, forKey: "reason") as String?,
            let checkedAt = coder.decodeObject(of: NSDate.self, forKey: "checkedAt") as Date?
        else {
            return nil
        }

        self.stateRawValue = stateRawValue
        self.serviceName = serviceName
        self.helperPath = helperPath
        self.plistPath = plistPath
        self.helperVersion = coder.decodeObject(of: NSString.self, forKey: "helperVersion") as String?
        self.expectedVersion = coder.decodeObject(of: NSString.self, forKey: "expectedVersion") as String?
        self.reason = reason
        self.checkedAt = checkedAt
    }

    public func encode(with coder: NSCoder) {
        coder.encode(stateRawValue as NSString, forKey: "stateRawValue")
        coder.encode(serviceName as NSString, forKey: "serviceName")
        coder.encode(helperPath as NSString, forKey: "helperPath")
        coder.encode(plistPath as NSString, forKey: "plistPath")
        if let helperVersion {
            coder.encode(helperVersion as NSString, forKey: "helperVersion")
        }
        if let expectedVersion {
            coder.encode(expectedVersion as NSString, forKey: "expectedVersion")
        }
        coder.encode(reason as NSString, forKey: "reason")
        coder.encode(checkedAt as NSDate, forKey: "checkedAt")
    }

    public func makeModel() -> HelperInstallStatus {
        HelperInstallStatus(
            state: HelperInstallState(rawValue: stateRawValue) ?? .notInstalled,
            serviceName: serviceName,
            helperPath: helperPath,
            plistPath: plistPath,
            helperVersion: helperVersion,
            expectedVersion: expectedVersion,
            reason: reason,
            checkedAt: checkedAt
        )
    }
}

public final class HelperControllerStatusResponseDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let status: ControllerStatusDTO
    public let error: HelperXPCErrorDTO?

    public init(status: ControllerStatusDTO, error: HelperXPCErrorDTO? = nil) {
        self.status = status
        self.error = error
    }

    public required init?(coder: NSCoder) {
        guard let status = coder.decodeObject(of: ControllerStatusDTO.self, forKey: "status") else {
            return nil
        }

        self.status = status
        self.error = coder.decodeObject(of: HelperXPCErrorDTO.self, forKey: "error")
    }

    public func encode(with coder: NSCoder) {
        coder.encode(status, forKey: "status")
        if let error {
            coder.encode(error, forKey: "error")
        }
    }
}

public final class HelperSelfTestResponseDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let result: ControllerSelfTestResultDTO
    public let status: ControllerStatusDTO?
    public let error: HelperXPCErrorDTO?

    public init(
        result: ControllerSelfTestResultDTO,
        status: ControllerStatusDTO? = nil,
        error: HelperXPCErrorDTO? = nil
    ) {
        self.result = result
        self.status = status
        self.error = error
    }

    public required init?(coder: NSCoder) {
        guard let result = coder.decodeObject(of: ControllerSelfTestResultDTO.self, forKey: "result") else {
            return nil
        }

        self.result = result
        self.status = coder.decodeObject(of: ControllerStatusDTO.self, forKey: "status")
        self.error = coder.decodeObject(of: HelperXPCErrorDTO.self, forKey: "error")
    }

    public func encode(with coder: NSCoder) {
        coder.encode(result, forKey: "result")
        if let status {
            coder.encode(status, forKey: "status")
        }
        if let error {
            coder.encode(error, forKey: "error")
        }
    }
}

public final class HelperCapabilityProbeResponseDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let report: CapabilityReportDTO
    public let status: ControllerStatusDTO
    public let error: HelperXPCErrorDTO?

    public init(
        report: CapabilityReportDTO,
        status: ControllerStatusDTO,
        error: HelperXPCErrorDTO? = nil
    ) {
        self.report = report
        self.status = status
        self.error = error
    }

    public required init?(coder: NSCoder) {
        guard
            let report = coder.decodeObject(of: CapabilityReportDTO.self, forKey: "report"),
            let status = coder.decodeObject(of: ControllerStatusDTO.self, forKey: "status")
        else {
            return nil
        }

        self.report = report
        self.status = status
        self.error = coder.decodeObject(of: HelperXPCErrorDTO.self, forKey: "error")
    }

    public func encode(with coder: NSCoder) {
        coder.encode(report, forKey: "report")
        coder.encode(status, forKey: "status")
        if let error {
            coder.encode(error, forKey: "error")
        }
    }
}

public final class HelperCommandResponseDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let status: ControllerStatusDTO
    public let error: HelperXPCErrorDTO?

    public init(status: ControllerStatusDTO, error: HelperXPCErrorDTO? = nil) {
        self.status = status
        self.error = error
    }

    public required init?(coder: NSCoder) {
        guard let status = coder.decodeObject(of: ControllerStatusDTO.self, forKey: "status") else {
            return nil
        }

        self.status = status
        self.error = coder.decodeObject(of: HelperXPCErrorDTO.self, forKey: "error")
    }

    public func encode(with coder: NSCoder) {
        coder.encode(status, forKey: "status")
        if let error {
            coder.encode(error, forKey: "error")
        }
    }
}
