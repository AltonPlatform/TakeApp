import Foundation

actor APIClient {
    private let baseURL: URL
    private let ssoBaseURL: URL
    private let session: URLSession
    private let tokenStore: TokenStoreProtocol
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var ongoingRefresh: Task<AuthTokens, Error>?
    private var sessionInvalidationHandler: (@MainActor @Sendable () async -> Void)?
    private var tokensRefreshedHandler: (@MainActor @Sendable (AuthTokens) async -> Void)?

    init(
        baseURL: URL = AppEnvironment.current.apiBaseURL,
        ssoBaseURL: URL = AppEnvironment.current.ssoBaseURL,
        session: URLSession = NetworkSessionFactory.makeSession(),
        tokenStore: TokenStoreProtocol = KeychainTokenStore()
    ) {
        self.baseURL = baseURL
        self.ssoBaseURL = ssoBaseURL
        self.session = session
        self.tokenStore = tokenStore
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func setSessionInvalidationHandler(_ handler: (@MainActor @Sendable () async -> Void)?) {
        sessionInvalidationHandler = handler
    }

    func setTokensRefreshedHandler(_ handler: (@MainActor @Sendable (AuthTokens) async -> Void)?) {
        tokensRefreshedHandler = handler
    }

    func request<T: Decodable>(
        _ endpoint: APIEndpoint,
        body: (any Encodable)? = nil,
        authorized: Bool? = nil
    ) async throws -> T {
        let requiresAuth = authorized ?? endpoint.requiresAuth
        return try await performRequest(endpoint, body: body, authorized: requiresAuth, retryOnUnauthorized: true)
    }

    func requestVoid(
        _ endpoint: APIEndpoint,
        body: (any Encodable)? = nil,
        authorized: Bool? = nil
    ) async throws {
        let _: EmptyResponse = try await request(endpoint, body: body, authorized: authorized)
    }

    private struct EmptyResponse: Decodable {}

    private func performRequest<T: Decodable>(
        _ endpoint: APIEndpoint,
        body: (any Encodable)?,
        authorized: Bool,
        retryOnUnauthorized: Bool
    ) async throws -> T {
        if authorized {
            try await ensureValidAccessToken()
        }

        let url = try endpoint.url(baseURL: baseURL)

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        if authorized, let tokens = try tokenStore.load() {
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.unknown
            }

            if httpResponse.statusCode == 401, authorized {
                if retryOnUnauthorized {
                    do {
                        _ = try await refreshTokens()
                        return try await performRequest(
                            endpoint,
                            body: body,
                            authorized: authorized,
                            retryOnUnauthorized: false
                        )
                    } catch let error as APIError {
                        if NetworkErrorClassifier.isAuthFailure(error) {
                            await invalidateSession()
                        }
                        throw error
                    } catch {
                        if NetworkErrorClassifier.isCancellation(error) { throw error }
                        throw APIError.network(error.localizedDescription)
                    }
                }

                await invalidateSession()
                throw APIError.unauthorized
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw mapHTTPError(
                    statusCode: httpResponse.statusCode,
                    data: data,
                    path: url.path
                )
            }

            if T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            }

            guard !data.isEmpty else {
                throw APIError.decodingFailed
            }

            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                PipelineLogger.media.error(
                    "decode failed path=\(url.path, privacy: .public) type=\(String(describing: T.self), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                throw APIError.decodingFailed
            }
        } catch let error as APIError {
            throw error
        } catch {
            if NetworkErrorClassifier.isCancellation(error) { throw error }
            throw APIError.network(error.localizedDescription)
        }
    }

    func refreshTokens() async throws -> AuthTokens {
        if let ongoingRefresh {
            return try await ongoingRefresh.value
        }

        let task = Task<AuthTokens, Error> {
            try await self.performRefresh()
        }
        ongoingRefresh = task
        defer { ongoingRefresh = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> AuthTokens {
        guard let current = try tokenStore.load() else {
            throw APIError.unauthorized
        }

        do {
            let response: AuthResponseDTO = try await performRequest(
                .refresh,
                body: RefreshRequestDTO(refreshToken: current.refreshToken),
                authorized: false,
                retryOnUnauthorized: false
            )

            let tokens = AuthTokens(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresIn: TimeInterval(response.expiresIn),
                userID: response.userID,
                username: response.username,
                issuedAt: Date()
            )
            try tokenStore.save(tokens)
            await tokensRefreshedHandler?(tokens)
            return tokens
        } catch let error as APIError {
            if NetworkErrorClassifier.isAuthFailure(error) {
                await invalidateSession()
            }
            throw error
        } catch {
            throw APIError.network(error.localizedDescription)
        }
    }

    private func ensureValidAccessToken() async throws {
        guard let tokens = try tokenStore.load() else {
            throw APIError.unauthorized
        }

        guard tokens.isExpired else { return }

        do {
            _ = try await refreshTokens()
        } catch let error as APIError {
            if NetworkErrorClassifier.isAuthFailure(error) {
                await invalidateSession()
                throw APIError.unauthorized
            }
            throw error
        } catch {
            throw APIError.network(error.localizedDescription)
        }
    }

    private func invalidateSession() async {
        await clearTokensWithLogging()
        await sessionInvalidationHandler?()
    }

    func logout() async throws {
        if let tokens = try tokenStore.load() {
            await performServerLogout(refreshToken: tokens.refreshToken, accessToken: tokens.accessToken)
        }
        do {
            try tokenStore.clear()
        } catch {
            PipelineLogger.logError(PipelineLogger.media, "keychain clear failed during logout", error: error)
            throw error
        }
    }

    func saveTokens(_ tokens: AuthTokens) throws {
        try tokenStore.save(tokens)
    }

    func loadTokens() throws -> AuthTokens? {
        try tokenStore.load()
    }

    func clearTokens() throws {
        try tokenStore.clear()
    }

    private func performServerLogout(refreshToken: String, accessToken: String) async {
        guard let url = URL(string: "auth/logout", relativeTo: ssoBaseURL) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try encoder.encode(LogoutRequestDTO(refreshToken: refreshToken))
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                PipelineLogger.media.error(
                    "server logout failed status=\(httpResponse.statusCode, privacy: .public)"
                )
            }
        } catch {
            PipelineLogger.logError(PipelineLogger.media, "server logout request failed", error: error)
        }
    }

    private func clearTokensWithLogging() async {
        do {
            try tokenStore.clear()
        } catch {
            PipelineLogger.logError(PipelineLogger.media, "keychain clear failed during logout", error: error)
        }
    }

    private func mapHTTPError(statusCode: Int, data: Data, path: String = "") -> APIError {
        let serverMessage = (try? decoder.decode(APIErrorResponse.self, from: data))?.error

        switch statusCode {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 404:
            return .notFound(path: path.isEmpty ? nil : path)
        case 409:
            return .conflict
        case 400:
            return .validation(serverMessage ?? "Invalid request.")
        case 429:
            return .network(serverMessage ?? "Too many requests. Try again.")
        case 502, 503, 504:
            return .network(serverMessage ?? "Service temporarily unavailable. Try again.")
        default:
            if let serverMessage, !serverMessage.isEmpty {
                return .network(serverMessage)
            }
            return .serverError(statusCode)
        }
    }
}

private struct LogoutRequestDTO: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        encodeClosure = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
