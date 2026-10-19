import CoreHaptics
import Foundation
import UIKit

/// Pure charge/shake math for Telegram-style reaction long-press.
enum ChatReactionCharge {
    static let highlightScale: CGFloat = 1.38
    static let maxScale: CGFloat = 1.9
    static let minRotationDegrees: CGFloat = 4
    static let maxRotationDegrees: CGFloat = 14
    static let maxOffsetX: CGFloat = 2

    /// 0…1 progress of the charge after highlight delay.
    static func progress(elapsed: TimeInterval, delay: TimeInterval = ChatContextMotion.chargeDelay, duration: TimeInterval = ChatContextMotion.chargeDuration) -> CGFloat {
        let t = elapsed - delay
        guard t > 0 else { return 0 }
        return CGFloat(min(1, max(0, t / duration)))
    }

    static func scale(progress: CGFloat) -> CGFloat {
        let p = min(1, max(0, progress))
        return highlightScale + (maxScale - highlightScale) * p
    }

    /// Rotation in degrees at `elapsed` (absolute time since highlight started).
    static func rotationDegrees(progress: CGFloat, elapsed: TimeInterval, hz: Double = ChatContextMotion.chargeShakeHz) -> CGFloat {
        let p = min(1, max(0, progress))
        guard p > 0 else { return 0 }
        let amplitude = minRotationDegrees + (maxRotationDegrees - minRotationDegrees) * p
        return amplitude * CGFloat(sin(elapsed * hz * 2 * .pi))
    }

    static func offsetX(progress: CGFloat, elapsed: TimeInterval, hz: Double = ChatContextMotion.chargeShakeHz) -> CGFloat {
        let p = min(1, max(0, progress))
        guard p > 0 else { return 0 }
        let amplitude = maxOffsetX * p
        return amplitude * CGFloat(sin(elapsed * hz * 2 * .pi + .pi / 2))
    }

    /// Peak times (seconds since highlight start) for discrete haptic ticks during charge.
    static func pulseTimes(delay: TimeInterval = ChatContextMotion.chargeDelay, duration: TimeInterval = ChatContextMotion.chargeDuration, hz: Double = ChatContextMotion.chargeShakeHz) -> [TimeInterval] {
        guard hz > 0, duration > 0 else { return [] }
        let period = 1.0 / hz
        var times: [TimeInterval] = []
        var t = delay + period * 0.25
        let end = delay + duration
        while t < end - 0.001 {
            times.append(t)
            t += period
        }
        return times
    }

    static func pulseIntensity(at time: TimeInterval, delay: TimeInterval = ChatContextMotion.chargeDelay, duration: TimeInterval = ChatContextMotion.chargeDuration) -> Float {
        let p = progress(elapsed: time, delay: delay, duration: duration)
        return Float(0.3 + 0.7 * p)
    }
}

/// Continuous + pulsed haptics synchronized with charge shake.
@MainActor
final class ChatReactionChargeHaptics {
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var fallbackTimer: Timer?
    private var fallbackPulseIndex = 0
    private var startDate: Date?
    private var usingCoreHaptics = false

    func start() {
        stop()
        startDate = Date()
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics,
           let engine = try? CHHapticEngine()
        {
            self.engine = engine
            engine.isAutoShutdownEnabled = true
            do {
                try engine.start()
                let pattern = try Self.makePattern()
                let player = try engine.makeAdvancedPlayer(with: pattern)
                try player.start(atTime: CHHapticTimeImmediate)
                self.player = player
                usingCoreHaptics = true
                return
            } catch {
                usingCoreHaptics = false
            }
        }
        startFallback()
    }

    func stop() {
        if let player {
            try? player.cancel()
        }
        player = nil
        engine?.stop(completionHandler: nil)
        engine = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        fallbackPulseIndex = 0
        startDate = nil
        usingCoreHaptics = false
    }

    private func startFallback() {
        let pulses = ChatReactionCharge.pulseTimes()
        guard !pulses.isEmpty else { return }
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        let start = Date()
        startDate = start
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            let elapsed = Date().timeIntervalSince(start)
            while self.fallbackPulseIndex < pulses.count, pulses[self.fallbackPulseIndex] <= elapsed {
                let intensity = CGFloat(ChatReactionCharge.pulseIntensity(at: pulses[self.fallbackPulseIndex]))
                generator.impactOccurred(intensity: intensity)
                self.fallbackPulseIndex += 1
            }
            if self.fallbackPulseIndex >= pulses.count {
                timer.invalidate()
                self.fallbackTimer = nil
            }
        }
        fallbackTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private static func makePattern() throws -> CHHapticPattern {
        let delay = ChatContextMotion.chargeDelay
        let duration = ChatContextMotion.chargeDuration
        var events: [CHHapticEvent] = []

        let continuous = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.35),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.45),
            ],
            relativeTime: delay,
            duration: duration
        )
        events.append(continuous)

        for time in ChatReactionCharge.pulseTimes() {
            let intensity = ChatReactionCharge.pulseIntensity(at: time)
            events.append(
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6),
                    ],
                    relativeTime: time
                )
            )
        }
        return try CHHapticPattern(events: events, parameters: [])
    }
}
