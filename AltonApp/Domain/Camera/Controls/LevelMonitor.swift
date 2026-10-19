import CoreMotion
import Foundation

struct LevelReading: Equatable, Sendable {
    /// Degrees from level; negative = left side down.
    var degrees: Double
    var isLevel: Bool
}

enum LevelMath {
    static let levelToleranceDegrees: Double = 1

    /// Gravity-based roll for portrait-upright phone.
    static func degrees(fromGravity x: Double, y: Double) -> Double {
        // atan2(x, -y) → 0 when phone is upright and level.
        (atan2(x, -y) * 180) / .pi
    }

    static func reading(x: Double, y: Double, tolerance: Double = levelToleranceDegrees) -> LevelReading {
        let degrees = Self.degrees(fromGravity: x, y: y)
        return LevelReading(degrees: degrees, isLevel: abs(degrees) <= tolerance)
    }

    static func shouldPublish(previous: LevelReading?, next: LevelReading, minDelta: Double = 0.5) -> Bool {
        guard let previous else { return true }
        if previous.isLevel != next.isLevel { return true }
        return abs(previous.degrees - next.degrees) >= minDelta
    }
}

/// Gravity-driven horizon at ~30 Hz on a private queue.
final class LevelMonitor: @unchecked Sendable {
    private let manager = CMMotionManager()
    private let queue = OperationQueue()
    private let lock = NSLock()
    private var last: LevelReading?
    private var handler: ((LevelReading) -> Void)?

    init() {
        queue.name = "com.alton.dm.camera.level"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
    }

    func start(onChange: @escaping (LevelReading) -> Void) {
        lock.lock()
        handler = onChange
        lock.unlock()
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            let next = LevelMath.reading(x: gravity.x, y: gravity.y)
            self.lock.lock()
            let previous = self.last
            let publish = LevelMath.shouldPublish(previous: previous, next: next)
            if publish { self.last = next }
            let handler = self.handler
            self.lock.unlock()
            guard publish else { return }
            handler?(next)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        lock.lock()
        handler = nil
        last = nil
        lock.unlock()
    }

    deinit {
        manager.stopDeviceMotionUpdates()
    }
}
