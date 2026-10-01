@testable import Helper
import Foundation
import Security
import Testing

@Test
func clientRequirementPinsIdentifierAndLeafCertificateFingerprint() throws {
    let requirement = ClientCodeSigningRequirement.make(
        clientIdentifier: "com.shin.cellcap.app",
        leafCertificateData: Data("certificate".utf8)
    )

    // SHA-1("certificate")
    #expect(requirement == "identifier \"com.shin.cellcap.app\" and certificate leaf = H\"735AD571C189D7BA84464BF4A9F1D2280175B128\"")

    var compiled: SecRequirement?
    #expect(SecRequirementCreateWithString(requirement as CFString, [], &compiled) == errSecSuccess)
}

@Test
func listenerRejectsConnectionsWithoutClientRequirement() {
    let delegate = CellCapHelperListenerDelegate(service: CellCapHelperService(), clientRequirement: nil)
    let listener = NSXPCListener.anonymous()
    let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
    defer { connection.invalidate() }

    #expect(delegate.listener(listener, shouldAcceptNewConnection: connection) == false)
}
