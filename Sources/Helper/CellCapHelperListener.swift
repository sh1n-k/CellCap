import Foundation
import Shared

final class CellCapHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: CellCapHelperService

    init(service: CellCapHelperService) {
        self.service = service
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = CellCapHelperXPC.makeRemoteInterface()
        newConnection.exportedObject = service
        newConnection.resume()
        return true
    }
}
