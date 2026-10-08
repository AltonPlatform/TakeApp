import Foundation

enum PostShareURL {
    /// Public share link: `https://{domain}/p/{postId}` with optional `?c={commentId}`.
    static func make(
        postID: String,
        commentID: String? = nil,
        domain: String = AppEnvironment.current.shareDomain
    ) -> URL? {
        guard (try? APIEndpoint.validateResourceID(postID)) != nil else { return nil }
        if let commentID, (try? APIEndpoint.validateResourceID(commentID)) == nil {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        components.path = "/p/\(postID)"
        if let commentID {
            components.queryItems = [URLQueryItem(name: "c", value: commentID)]
        }
        return components.url
    }
}
