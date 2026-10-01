import CryptoKit
import Foundation
import Security

/// root helper에 연결할 수 있는 앱을 "helper와 같은 인증서로 서명된 CellCap 앱"으로 제한한다.
/// 인증서 지문은 helper 자신의 서명에서 읽으므로 서명 인증서를 코드에 고정하지 않는다.
enum ClientCodeSigningRequirement {
    static func make(clientIdentifier: String, leafCertificateData: Data) -> String {
        let fingerprint = Insecure.SHA1.hash(data: leafCertificateData)
            .map { String(format: "%02X", $0) }
            .joined()
        return "identifier \"\(clientIdentifier)\" and certificate leaf = H\"\(fingerprint)\""
    }

    /// helper가 인증서로 서명되지 않았으면(ad-hoc, 미서명) nil을 돌려주고, 호출부는 모든 연결을 거부한다.
    static func makeForCurrentProcess(clientIdentifier: String) -> String? {
        guard let leafCertificateData = currentProcessLeafCertificateData() else {
            return nil
        }
        return make(clientIdentifier: clientIdentifier, leafCertificateData: leafCertificateData)
    }

    private static func currentProcessLeafCertificateData() -> Data? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
            let information = information as? [String: Any],
            let certificates = information[kSecCodeInfoCertificates as String] as? [SecCertificate],
            let leafCertificate = certificates.first
        else {
            return nil
        }

        return SecCertificateCopyData(leafCertificate) as Data
    }
}
