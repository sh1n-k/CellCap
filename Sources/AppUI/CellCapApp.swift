import Core
import Foundation
import SwiftUI
import SystemSupport

@main
struct CellCapApp: App {
    @StateObject private var viewModel: MenuBarViewModel

    init() {
        if UninstallCleanupCommand.runIfRequested() {
            Foundation.exit(0)
        }

        let eventLogger = EventLogger()
        let controller = XPCChargeController(eventLogger: eventLogger)
        let batteryMonitor = BatteryMonitor(
            snapshotProvider: SystemBatterySnapshotProvider(),
            eventSource: SystemBatteryMonitorEventSource()
        )
        let orchestrator = AppRuntimeOrchestrator(
            batteryMonitor: batteryMonitor,
            controller: controller,
            capabilityProber: controller,
            policyStore: UserDefaultsChargePolicyStore(),
            eventLogger: eventLogger
        )
        _viewModel = StateObject(
            wrappedValue: MenuBarViewModel(
                service: orchestrator,
                launchAtLoginManager: LaunchAtLoginManager(),
                // helper는 앱 번들에 내장되므로 swift run 같은 번들 밖 실행에서는 설치 기능을 열지 않는다.
                helperServiceManager: Bundle.main.bundleURL.pathExtension == "app"
                    ? HelperServiceManager(controller: controller)
                    : nil
            )
        )
    }

    var body: some Scene {
        MenuBarExtra {
            RootView(viewModel: viewModel)
        } label: {
            MenuBarLabelView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
