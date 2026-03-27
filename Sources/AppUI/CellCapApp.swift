import Core
import Shared
import SwiftUI

@main
struct CellCapApp: App {
    private let stateMachine = ChargeStateMachine()

    var body: some Scene {
        WindowGroup("CellCap") {
            RootView(
                state: previewState,
                transitionReason: stateMachine.transition(
                    from: .waitingForRecharge,
                    context: ChargeStateContext(
                        battery: previewBattery,
                        policy: previewPolicy,
                        controllerStatus: previewControllerStatus
                    )
                ).reason
            )
        }
        .defaultSize(width: 420, height: 280)
    }
}

private let previewBattery = BatterySnapshot(
    chargePercent: 78,
    isPowerConnected: true,
    isCharging: false
)

private let previewPolicy = ChargePolicy(
    upperLimit: 80,
    rechargeThreshold: 75
)

private let previewControllerStatus = ControllerStatus(
    mode: .fullControl,
    helperConnection: .connected,
    isChargingEnabled: false
)

private let previewState = AppState(
    battery: previewBattery,
    policy: previewPolicy,
    controllerStatus: previewControllerStatus,
    chargeState: .waitingForRecharge
)
