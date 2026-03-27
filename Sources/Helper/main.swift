import Foundation
import Shared

@main
enum CellCapHelperMain {
    static func main() {
        let placeholderStatus = ControllerStatus(
            mode: .readOnly,
            helperConnection: .unavailable,
            isChargingEnabled: nil,
            temporaryOverrideUntil: nil,
            lastErrorDescription: "TODO: XPC helper and capability probe are not implemented in this stage."
        )

        print("CellCapHelper stub started.")
        print("Mode: \(placeholderStatus.mode.rawValue)")
        print("Helper connection: \(placeholderStatus.helperConnection.rawValue)")
        print("TODO: privileged helper bootstrap and capability checks.")
    }
}
