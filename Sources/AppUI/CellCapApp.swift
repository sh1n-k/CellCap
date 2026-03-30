import Core
import SwiftUI

@main
struct CellCapApp: App {
    @StateObject private var viewModel: MenuBarViewModel

    init() {
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
                launchAtLoginManager: LaunchAtLoginManager()
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
