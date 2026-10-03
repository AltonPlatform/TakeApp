import Foundation

actor SSOClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        baseURL: URL = AppEnvironment.current.ssoBaseURL,
        session: URLSession = NetworkSessionFactory.makeSession()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func request<T: Decodable>(
        _ endpoint: SSOEndpoint,
        body: (any Encodable)? = nil
    ) async throws -> T {
        guard let url = endpoint.url(baseURL: baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body, endpoint.method == .post {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.unknown
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw mapHTTPError(statusCode: httpResponse.statusCode, data: data)
            }

            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingFailed
            }
        } catch let error as APIError {
            throw error
        } catch {
            if NetworkErrorClassifier.isCancellation(error) { throw error }
            throw APIError.network(error.localizedDescription)
        }
    }

    private func mapHTTPError(statusCode: Int, data: Data) -> APIError {
        let serverMessage = (try? decoder.decode(APIErrorResponse.self, from: data))?.error

        switch statusCode {
        case 401:
            return .validation(serverMessage ?? "Sign in failed.")
        case 403:
            return .forbidden
        case 404:
            return .validation(
                "SSO endpoint not found. Rebuild sso-service: " +
                "docker compose -f infra/docker/compose.dev.yml build sso-service && up -d sso-service"
            )
        case 409:
            return .conflict
        case 400:
            return .validation(serverMessage ?? "Invalid request.")
        case 410:
            return .validation("Link expired or already used.")
        default:
            return .serverError(statusCode)
        }
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
