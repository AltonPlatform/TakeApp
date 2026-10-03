import UIKit

enum ShotHaptics {
    static func play() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func pause() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func like() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func longPressBegan() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    static func speedStep() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func speedLocked() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func speedUnlocked() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.75)
    }

    static func speedReverted() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func menuOpened() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func scrubBegan() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
    }

    static func scrubEnded() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
    }
}
