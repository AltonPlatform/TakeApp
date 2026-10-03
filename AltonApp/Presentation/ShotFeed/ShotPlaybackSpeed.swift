import Foundation

enum ShotPlaybackSpeed {
    static let rates: [Float] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3]
    static let defaultIndex = 3
    static let leftZoneStartIndex = 0
    static let rightZoneStartIndex = rates.count - 1
    static let zoneEndIndex = defaultIndex
    static let zoneStepPoints: CGFloat = 60

    static func label(for index: Int) -> String {
        let rate = rates[clamped(index)]
        if rate == floor(rate) {
            return String(format: "%.0fx", rate)
        }
        return String(format: "%.2gx", rate)
    }

    static func clamped(_ index: Int) -> Int {
        min(max(index, 0), rates.count - 1)
    }
}
