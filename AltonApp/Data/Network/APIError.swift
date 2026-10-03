import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

enum APIError: LocalizedError, Equatable {
    case invalidURL
    case unauthorized
    case forbidden
    case notFound(path: String? = nil)
    case conflict
    case validation(String)
    case serverError(Int)
    case decodingFailed
    case network(String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid request URL."
        case .unauthorized:
            return "Session expired. Please sign in again."
        case .forbidden:
            return "You do not have permission to perform this action."
        case .notFound(let path):
            if let path, !path.isEmpty {
                return "Requested resource was not found (\(path))."
            }
            return "Requested resource was not found."
        case .conflict:
            return "This username is already taken."
        case .validation(let message):
            return message
        case .serverError(let code):
            return "Server error (\(code))."
        case .decodingFailed:
            return "Unable to read server response."
        case .network(let message):
            return message
        case .unknown:
            return "Something went wrong."
        }
    }
}

struct APIErrorResponse: Decodable {
    let error: String?
}

/// Parses API timestamps. Backend uses chrono RFC3339 (`to_rfc3339()`),
/// which often includes fractional seconds — a default `ISO8601DateFormatter` misses those.
enum APIDateParser {
    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let internet: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let date = withFraction.date(from: raw) { return date }
        if let date = internet.date(from: raw) { return date }
        return nil
    }

    /// Parses `YYYY-MM-DD` as a calendar day in the current timezone (no UTC shift).
    static func parseDay(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let parts = raw.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// Formats a `Date` as `YYYY-MM-DD` using local calendar day components.
    static func formatDay(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let year = comps.year, let month = comps.month, let day = comps.day else {
            return ""
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
