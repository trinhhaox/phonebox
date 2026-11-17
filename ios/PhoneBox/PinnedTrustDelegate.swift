import CryptoKit
import Foundation
import Security

/// Trusts exactly one certificate: the one whose DER SHA-256 equals the pin from pairing. CA chain and host name are
/// deliberately not evaluated (the agent's certificate is self-signed and addressed by IP).
final class PinnedTrustDelegate: NSObject, URLSessionDelegate {
    private static let hex64 = try! NSRegularExpression(pattern: "^[0-9a-f]{64}$")
    let pin: String

    init(pin: String) { self.pin = pin.lowercased() }

    static func fingerprint(of certificate: SecCertificate) -> String {
        fingerprint(ofDER: SecCertificateCopyData(certificate) as Data)
    }

    static func fingerprint(ofDER der: Data) -> String {
        SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    }

    /// Valid pins are 64 lowercase/uppercase hex characters; anything else never matches.
    static func matches(fingerprint: String, pin: String) -> Bool {
        let p = pin.lowercased()
        let range = NSRange(p.startIndex..., in: p)
        guard hex64.firstMatch(in: p, range: range) != nil else { return false }
        return fingerprint.lowercased() == p
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first,
              Self.matches(fingerprint: Self.fingerprint(of: leaf), pin: pin) else {
            completionHandler(.cancelAuthenticationChallenge, nil) // never fall back to system trust
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
