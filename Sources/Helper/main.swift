import Foundation
import Shared

let service = CellCapHelperService()
let delegate = CellCapHelperListenerDelegate(service: service)
let listener = NSXPCListener(machServiceName: CellCapHelperXPC.serviceName)

listener.delegate = delegate
listener.resume()
RunLoop.current.run()
