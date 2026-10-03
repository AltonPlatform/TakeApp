import Foundation

enum SSOEndpoint {
    case appleCallback
    case googleNativeSignIn
    case passkeyLoginStart
    case passkeyLoginFinish
    case magicLinkSend
    case magicLinkVerify
    case refresh

    func url(baseURL: URL) -> URL? {
        switch self {
        case .appleCallback:
            return baseURL.appending(path: "auth/apple/callback")
        case .googleNativeSignIn:
            return baseURL.appending(path: "auth/google/ios")
        case .passkeyLoginStart:
            return baseURL.appending(path: "auth/passkey/login/start")
        case .passkeyLoginFinish:
            return baseURL.appending(path: "auth/passkey/login/finish")
        case .magicLinkSend:
            return baseURL.appending(path: "auth/magic-link/send")
        case .magicLinkVerify:
            return baseURL.appending(path: "auth/magic-link/verify")
        case .refresh:
            return baseURL.appending(path: "auth/refresh")
        }
    }

    var method: HTTPMethod {
        .post
    }
}
