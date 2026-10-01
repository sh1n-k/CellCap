import Foundation
import Shared

final class CellCapHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: CellCapHelperService
    private let clientRequirement: String?

    init(
        service: CellCapHelperService,
        clientRequirement: String? = ClientCodeSigningRequirement.makeForCurrentProcess(
            clientIdentifier: CellCapHelperXPC.clientBundleIdentifier
        )
    ) {
        self.service = service
        self.clientRequirement = clientRequirement
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // helper 서명을 읽지 못하면 연결 앱을 검증할 기준이 없으므로 root 기능을 열지 않는다.
        guard let clientRequirement else {
            return false
        }

        newConnection.setCodeSigningRequirement(clientRequirement)
        newConnection.exportedInterface = CellCapHelperXPC.makeRemoteInterface()
        newConnection.exportedObject = service
        newConnection.resume()
        return true
    }
}
