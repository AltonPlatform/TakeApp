import Foundation

/// Auth token lifecycle helpers built on top of `APIClient`.
extension APIClient {
    func authorizedRequest<T: Decodable>(
        _ endpoint: APIEndpoint,
        body: (any Encodable)? = nil
    ) async throws -> T {
        try await request(endpoint, body: body, authorized: true)
    }
}
