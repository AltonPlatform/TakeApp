import Foundation

enum KlipyConfig {
    /// Set `KlipyAPIKey` in Info.plist (from https://partner.klipy.com/api-keys).
    static var apiKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "KlipyAPIKey") as? String else {
            return nil
        }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty,
              !key.hasPrefix("$("),
              key != "YOUR_KLIPY_API_KEY" else {
            return nil
        }
        return key
    }

    /// Stable anonymous customer id for personalization / share tracking.
    static var customerID: String {
        let defaults = UserDefaults.standard
        let key = "klipy.customer_id"
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString.lowercased()
        defaults.set(fresh, forKey: key)
        return fresh
    }
}

struct KlipyGIF: Identifiable, Hashable, Sendable {
    let id: String
    let slug: String
    let title: String
    let previewURL: URL
    let downloadURL: URL
    let contentType: String
    let width: Int
    let height: Int

    var fileExtension: String {
        contentType == "image/webp" ? "webp" : "gif"
    }
}

/// Picks the best Klipy raster that still copies through media-service: md → sm → xs, under 4 MB.
enum KlipyAssetPicker {
    static let maxBytes = 4 * 1024 * 1024
    /// media-service copies WebP as-is only when both sides are ≤ this.
    static let maxCopyDimension = 2048

    struct Candidate: Equatable {
        let url: String
        let size: Int
        let width: Int
        let height: Int
        let contentType: String
    }

    struct Asset: Equatable {
        let url: URL
        let contentType: String
        let size: Int
        let width: Int
        let height: Int
    }

    static func preferred(from candidates: [Candidate]) -> Asset? {
        if let asset = candidates.compactMap(acceptable).first {
            return asset
        }

        // GIF is copied regardless of pixel size; WebP over 2048 may flatten on re-encode.
        return candidates.compactMap { candidate -> Asset? in
            guard candidate.contentType == "image/gif" else { return nil }
            return acceptableIgnoringDimension(candidate)
        }.first
    }

    /// Smallest safe raster for grid/chips so a missing `size` on md does not load the heaviest file.
    static func preview(from candidates: [Candidate]) -> Asset? {
        let accepted = candidates.compactMap(acceptable)
        if let smallest = accepted.min(by: isLighterPreview) {
            return smallest
        }
        return preferred(from: candidates)
    }

    private static func isLighterPreview(_ lhs: Asset, _ rhs: Asset) -> Bool {
        let leftUnknown = lhs.size == 0
        let rightUnknown = rhs.size == 0
        if leftUnknown != rightUnknown {
            return !leftUnknown
        }
        if lhs.size != rhs.size {
            return lhs.size < rhs.size
        }
        let leftPixels = lhs.width * lhs.height
        let rightPixels = rhs.width * rhs.height
        if leftPixels != rightPixels {
            return leftPixels < rightPixels
        }
        if lhs.contentType != rhs.contentType {
            return lhs.contentType == "image/webp"
        }
        return false
    }

    private static func acceptable(_ candidate: Candidate) -> Asset? {
        guard max(candidate.width, candidate.height) <= maxCopyDimension else { return nil }
        return acceptableIgnoringDimension(candidate)
    }

    private static func acceptableIgnoringDimension(_ candidate: Candidate) -> Asset? {
        guard !candidate.url.isEmpty,
              candidate.size >= 0,
              candidate.size == 0 || candidate.size <= maxBytes,
              let url = URL(string: candidate.url) else {
            return nil
        }
        return Asset(
            url: url,
            contentType: candidate.contentType,
            size: candidate.size,
            width: candidate.width,
            height: candidate.height
        )
    }
}

enum KlipyShareURL {
    private static let pathAllowed: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return allowed
    }()

    static func make(apiKey: String, slug: String) -> URL? {
        guard let encodedKey = apiKey.addingPercentEncoding(withAllowedCharacters: pathAllowed),
              let encodedSlug = slug.addingPercentEncoding(withAllowedCharacters: pathAllowed),
              !encodedKey.isEmpty,
              !encodedSlug.isEmpty else {
            return nil
        }
        return URL(string: "https://api.klipy.com/api/v1/\(encodedKey)/gifs/share/\(encodedSlug)")
    }
}

enum KlipyClientError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case badStatus(Int)
    case decodingFailed
    case emptyData
    case tooLarge
    case apiMessage(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your Klipy API key to Info.plist (KlipyAPIKey)."
        case .invalidURL:
            return "Couldn’t build a Klipy request."
        case .badStatus(let code):
            return "Klipy request failed (\(code))."
        case .decodingFailed:
            return "Couldn’t parse Klipy response."
        case .emptyData:
            return "That GIF had no data."
        case .tooLarge:
            return "GIF too large (max 4 MB)."
        case .apiMessage(let message):
            return message
        }
    }
}

actor KlipyClient {
    static let shared = KlipyClient()

    private let session: URLSession
    private let maxGIFBytes = KlipyAssetPicker.maxBytes

    init(session: URLSession = .shared) {
        self.session = session
    }

    func trending(page: Int = 1, perPage: Int = 30) async throws -> [KlipyGIF] {
        try await fetch(path: "/gifs/trending", queryItems: [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
            URLQueryItem(name: "customer_id", value: KlipyConfig.customerID),
            URLQueryItem(name: "locale", value: "en"),
        ])
    }

    func search(query: String, page: Int = 1, perPage: Int = 30) async throws -> [KlipyGIF] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try await trending(page: page, perPage: perPage)
        }
        return try await fetch(path: "/gifs/search", queryItems: [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
            URLQueryItem(name: "customer_id", value: KlipyConfig.customerID),
            URLQueryItem(name: "locale", value: "en"),
        ])
    }

    func downloadGIF(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw KlipyClientError.badStatus(http.statusCode)
        }
        guard !data.isEmpty else { throw KlipyClientError.emptyData }
        guard data.count <= maxGIFBytes else { throw KlipyClientError.tooLarge }
        return data
    }

    /// Best-effort share signal for ranking (does not throw to callers).
    func registerShare(slug: String) async {
        guard let apiKey = KlipyConfig.apiKey,
              let url = KlipyShareURL.make(apiKey: apiKey, slug: slug) else {
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["customer_id": KlipyConfig.customerID]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await session.data(for: request)
    }

    private func fetch(path: String, queryItems: [URLQueryItem]) async throws -> [KlipyGIF] {
        guard let apiKey = KlipyConfig.apiKey else {
            throw KlipyClientError.missingAPIKey
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.klipy.com"
        components.path = "/api/v1/\(apiKey)\(path)"
        components.queryItems = queryItems

        guard let url = components.url else {
            throw KlipyClientError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw KlipyClientError.badStatus(http.statusCode)
        }

        let decoded: KlipyAPIResponse
        do {
            decoded = try JSONDecoder().decode(KlipyAPIResponse.self, from: data)
        } catch {
            throw KlipyClientError.decodingFailed
        }

        guard decoded.result else {
            throw KlipyClientError.apiMessage("Klipy returned an error.")
        }

        return decoded.data.data.compactMap { $0.asGIF() }
    }
}

// MARK: - API DTOs

private struct KlipyAPIResponse: Decodable {
    let result: Bool
    let data: KlipyPaginatedData
}

private struct KlipyPaginatedData: Decodable {
    let data: [KlipyAPIItem]
}

private struct KlipyAPIItem: Decodable {
    let id: Int?
    let title: String?
    let slug: String?
    let blurPreview: String?
    let file: KlipySizeVariants?
    /// Ad rows include HTML `content` instead of `file` — skip those.
    let content: String?

    enum CodingKeys: String, CodingKey {
        case id, title, slug, file, content
        case blurPreview = "blur_preview"
    }

    func asGIF() -> KlipyGIF? {
        guard content == nil,
              let id,
              let slug,
              let file else {
            return nil
        }

        let download = KlipyAssetPicker.preferred(from: file.candidates())

        guard let download else {
            return nil
        }
        let preview = KlipyAssetPicker.preview(from: file.candidates()) ?? download

        return KlipyGIF(
            id: String(id),
            slug: slug,
            title: title ?? "",
            previewURL: preview.url,
            downloadURL: download.url,
            contentType: download.contentType,
            width: download.width,
            height: download.height
        )
    }
}

private struct KlipySizeVariants: Decodable {
    let hd: KlipyFileFormats
    let md: KlipyFileFormats
    let sm: KlipyFileFormats
    let xs: KlipyFileFormats

    func candidates() -> [KlipyAssetPicker.Candidate] {
        [
            md.asCandidates(),
            sm.asCandidates(),
            xs.asCandidates(),
        ].flatMap { $0 }
    }
}

private extension KlipyFileFormats {
    func asCandidates() -> [KlipyAssetPicker.Candidate] {
        [
            webp.asCandidate(contentType: "image/webp"),
            gif.asCandidate(contentType: "image/gif"),
        ]
    }
}

private extension KlipyFileMeta {
    func asCandidate(contentType: String) -> KlipyAssetPicker.Candidate {
        KlipyAssetPicker.Candidate(
            url: url,
            size: size,
            width: width,
            height: height,
            contentType: contentType
        )
    }
}

private struct KlipyFileFormats: Decodable {
    let gif: KlipyFileMeta
    let webp: KlipyFileMeta
}

private struct KlipyFileMeta: Decodable {
    let url: String
    let width: Int
    let height: Int
    let size: Int
}
