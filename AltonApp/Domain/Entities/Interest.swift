import Foundation

struct Interest: Equatable, Sendable, Identifiable, Hashable {
    let category: String
    let subcategory: String
    var weight: Double

    var id: String { "\(category)/\(subcategory)" }

    /// Category-level interest marker used by onboarding (maps to `{category}_other`).
    static func categoryLevel(category: String, weight: Double = 1.0) -> Interest {
        let sub = category == "other" ? "other_general" : "\(category)_other"
        return Interest(category: category, subcategory: sub, weight: weight)
    }
}
