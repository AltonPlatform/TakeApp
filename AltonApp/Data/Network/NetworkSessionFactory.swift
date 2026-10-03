import CryptoKit
import Foundation
import Security

enum CertPinningPolicy {
    /// SPKI pinning is enabled only in Release/AppStore builds with `ENABLE_CERT_PINNING`.
    static var isEnabled: Bool {
        #if ENABLE_CERT_PINNING
        #if DEBUG
        return false
        #else
        return true
        #endif
        #else
        return false
        #endif
    }

    /// Hosts served under `*.altons.trade` and media CDN endpoints require SPKI validation when pinning is enabled.
    static func shouldPin(host: String) -> Bool {
        let lowered = host.lowercased()
        if lowered == "altons.trade" || lowered.hasSuffix(".altons.trade") {
            return true
        }
        return lowered == "media.altons.trade"
            || lowered == "dev-media.altons.trade"
            || lowered.hasSuffix(".r2.cloudflarestorage.com")
    }

    /// Base64-encoded SHA-256 hashes of SPKI for trusted intermediates/roots.
    private static let pinnedSPKIHashesBase64: [String] = [
        "C5+lpZ7tcVwmGwQ60fwDwJJbjwPKi8wZy4GRsmpW1oo=",
        "lvcV9GLT7w0xkvwhG1TI7Wo5FYsQ3MmXxXlY0lQrJ6Y=",
    ]

    static func validate(serverTrust: SecTrust, host: String) -> Bool {
        guard shouldPin(host: host) else { return true }

        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            return false
        }

        let pinnedHashes = Set(pinnedSPKIHashesBase64.compactMap { Data(base64Encoded: $0) })
        guard !pinnedHashes.isEmpty else {
            return false
        }

        guard let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
            return false
        }

        return chain.contains { certificate in
            guard let hash = spkiSHA256(for: certificate) else { return false }
            return pinnedHashes.contains(hash)
        }
    }

    private static func spkiSHA256(for certificate: SecCertificate) -> Data? {
        guard let publicKey = SecCertificateCopyKey(certificate),
              let keyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?,
              let attributes = SecKeyCopyAttributes(publicKey) as? [CFString: Any],
              let keyType = attributes[kSecAttrKeyType] as? String,
              let keySize = attributes[kSecAttrKeySizeInBits] as? Int else {
            return nil
        }

        let header: Data
        if keyType == (kSecAttrKeyTypeRSA as String) {
            switch keySize {
            case 2048:
                header = Data([
                    0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
                    0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00,
                ])
            case 4096:
                header = Data([
                    0x30, 0x82, 0x02, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
                    0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x02, 0x0f, 0x00,
                ])
            default:
                return nil
            }
        } else if keyType == (kSecAttrKeyTypeECSECPrimeRandom as String) {
            switch keySize {
            case 256:
                header = Data([
                    0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02,
                    0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03,
                    0x42, 0x00,
                ])
            case 384:
                header = Data([
                    0x30, 0x76, 0x30, 0x10, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02,
                    0x01, 0x06, 0x05, 0x2b, 0x81, 0x04, 0x00, 0x22, 0x03, 0x62, 0x00,
                ])
            default:
                return nil
            }
        } else {
            return nil
        }

        return Data(SHA256.hash(data: header + keyData))
    }
}

final class CertPinningSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard CertPinningPolicy.isEnabled,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host
        if CertPinningPolicy.validate(serverTrust: serverTrust, host: host) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            PipelineLogger.media.error("cert pinning rejected host=\(host, privacy: .public)")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

enum NetworkSessionFactory {
    private static let pinningDelegate = CertPinningSessionDelegate()

    /// Shared session with a short request timeout so hung refresh calls fail fast.
    static func makeSession(requestTimeout: TimeInterval = 15) -> URLSession {
        makeConfiguredSession(
            requestTimeout: requestTimeout,
            resourceTimeout: requestTimeout * 4,
            waitsForConnectivity: false
        )
    }

    /// Long-lived session for large media PUTs (video / multi-MB images).
    static func makeMediaUploadSession(
        requestTimeout: TimeInterval = 120,
        resourceTimeout: TimeInterval = 30 * 60
    ) -> URLSession {
        makeConfiguredSession(
            requestTimeout: requestTimeout,
            resourceTimeout: resourceTimeout,
            waitsForConnectivity: true
        )
    }

    private static func makeConfiguredSession(
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval,
        waitsForConnectivity: Bool
    ) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.waitsForConnectivity = waitsForConnectivity
        // Images are cached via Nuke; API JSON responses should not inflate URLCache.
        configuration.urlCache = nil

        if CertPinningPolicy.isEnabled {
            return URLSession(configuration: configuration, delegate: pinningDelegate, delegateQueue: nil)
        }
        return URLSession(configuration: configuration)
    }
}

enum NetworkErrorClassifier {
    static func isTransientNetworkFailure(_ error: Error) -> Bool {
        if isCancellation(error) { return false }
        if error is URLError { return true }
        if case APIError.network = error { return true }
        return false
    }

    static func isAuthFailure(_ error: Error) -> Bool {
        if case APIError.unauthorized = error { return true }
        return false
    }

    /// Task / URLSession cancellation — must not surface as user-facing errors.
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        if case APIError.network(let message) = error {
            let lower = message.lowercased()
            return lower == "cancelled" || lower.contains("canceled") || lower.contains("cancelled")
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled {
            return true
        }
        return false
    }
}
