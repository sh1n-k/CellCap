import Foundation
import Shared
import SystemSupport

let backend = ChargeControlBackendSelector()
let service = CellCapHelperService(backend: backend)
let delegate = CellCapHelperListenerDelegate(service: service)
let listener = NSXPCListener(machServiceName: CellCapHelperXPC.serviceName)

// 앱이 꺼져 있어도 SoC 하락에 맞춰 충전 한도를 낮출 수 있도록 helper가 전원 변화를 직접 받는다.
let powerSourceObserver = PowerSourceNotificationObserver()
powerSourceObserver.start {
    Task {
        await backend.handlePowerSourceChange(now: Date())
    }
}

listener.delegate = delegate
listener.resume()
RunLoop.current.run()
