import Shared

protocol ControlAvailabilityResolving {
    func effectiveHelperInstallStatus(
        appState: AppState,
        capabilityReport: CapabilityReport
    ) -> HelperInstallStatus?

    func controlAvailability(
        appState: AppState,
        capabilityReport: CapabilityReport
    ) -> MenuBarViewModel.ControlAvailability

    func temporaryOverrideAvailability(
        appState: AppState,
        capabilityReport: CapabilityReport
    ) -> MenuBarViewModel.ControlAvailability

    func shouldAutoExpandAdvancedSection(
        appState: AppState,
        capabilityReport: CapabilityReport
    ) -> Bool
}

struct ControlAvailabilityResolver: ControlAvailabilityResolving {
    func effectiveHelperInstallStatus(
        appState: AppState,
        capabilityReport: CapabilityReport
    ) -> HelperInstallStatus? {
        guard let installStatus = capabilityReport.helperInstallStatus else {
            return nil
        }

        guard appState.controllerStatus.helperConnection == .connected else {
            return installStatus
        }

        switch installStatus.state {
        case .bootstrapped, .installedButNotBootstrapped:
            return HelperInstallStatus(
                state: .xpcReachable,
                serviceName: installStatus.serviceName,
                helperPath: installStatus.helperPath,
                plistPath: installStatus.plistPath,
                helperVersion: installStatus.helperVersion,
                expectedVersion: installStatus.expectedVersion,
                reason: "helper XPC 연결이 확인되었습니다. 권한 및 SMC 키 검사를 계속 진행합니다.",
                checkedAt: installStatus.checkedAt
            )
        case .notInstalled, .xpcReachable, .permissionMismatch, .versionMismatch:
            return installStatus
        }
    }

    func controlAvailability(
        appState: AppState,
        capabilityReport: CapabilityReport
    ) -> MenuBarViewModel.ControlAvailability {
        if let error = appState.controllerStatus.lastErrorDescription, appState.chargeState == .errorReadOnly {
            return .disabled(error)
        }

        guard appState.battery?.isBatteryPresent == true else {
            return .disabled("내장 배터리를 찾지 못했습니다.")
        }

        if let installStatus = effectiveHelperInstallStatus(appState: appState, capabilityReport: capabilityReport),
           installStatus.installationSupport != .supported {
            return .disabled(installStatus.reason)
        }

        for key in [CapabilityKey.helperPrivilege, .chargeControl] {
            guard let status = capabilityReport.status(for: key) else { continue }

            switch status.support {
            case .supported:
                continue
            case .experimental:
                if key == .chargeControl {
                    continue
                }
                return .disabled(status.reason)
            case .unsupported, .readOnlyFallback:
                return .disabled(status.reason)
            }
        }

        switch appState.controllerStatus.mode {
        case .fullControl:
            return .enabled
        case .readOnly:
            return .disabled("현재 제어 모드가 읽기 전용입니다.")
        case .monitoringOnly:
            return .disabled("현재 기기는 관측 전용 모드입니다.")
        }
    }

    func temporaryOverrideAvailability(
        appState: AppState,
        capabilityReport: CapabilityReport
    ) -> MenuBarViewModel.ControlAvailability {
        if appState.chargeState == .temporaryOverride {
            return .enabled
        }

        return controlAvailability(appState: appState, capabilityReport: capabilityReport)
    }

    func shouldAutoExpandAdvancedSection(
        appState: AppState,
        capabilityReport: CapabilityReport
    ) -> Bool {
        if appState.controllerStatus.mode != .fullControl || appState.chargeState == .errorReadOnly {
            return true
        }

        return capabilityReport.statuses.contains { status in
            switch status.support {
            case .unsupported, .readOnlyFallback:
                return true
            case .experimental:
                return status.key != .chargeControl
            case .supported:
                return false
            }
        }
    }
}
