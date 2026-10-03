import AVFoundation
import os
import SwiftUI
import UIKit

private let videoPlaybackLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.alton.altonApp",
    category: "VideoPlayback"
)

final class ShotPlayerUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = UIColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = UIColor.black.cgColor
    }
}

struct ShotPlayerView: UIViewRepresentable {
    let url: URL?
    let isActive: Bool
    var loops: Bool = true
    var preloadOnly: Bool = false
    /// When true, playback stays silent (e.g. sensitive blur before reveal).
    var isMuted: Bool = false
    @Binding var progress: Double
    @Binding var isScrubbing: Bool
    @Binding var seekToProgress: Double?
    @Binding var currentTime: TimeInterval
    @Binding var duration: TimeInterval
    @Binding var isPausedByUser: Bool
    @Binding var playbackRate: Float
    var subtitlesURL: URL? = nil
    var subtitlesEnabled: Bool = false
    var onSubtitleCuesLoaded: ([WebVTTCue]) -> Void = { _ in }

    init(
        url: URL?,
        isActive: Bool,
        loops: Bool = true,
        preloadOnly: Bool = false,
        isMuted: Bool = false,
        progress: Binding<Double> = .constant(0),
        isScrubbing: Binding<Bool> = .constant(false),
        seekToProgress: Binding<Double?> = .constant(nil),
        currentTime: Binding<TimeInterval> = .constant(0),
        duration: Binding<TimeInterval> = .constant(0),
        isPausedByUser: Binding<Bool> = .constant(false),
        playbackRate: Binding<Float> = .constant(1),
        subtitlesURL: URL? = nil,
        subtitlesEnabled: Bool = false,
        onSubtitleCuesLoaded: @escaping ([WebVTTCue]) -> Void = { _ in }
    ) {
        self.url = url
        self.isActive = isActive
        self.loops = loops
        self.preloadOnly = preloadOnly
        self.isMuted = isMuted
        self._progress = progress
        self._isScrubbing = isScrubbing
        self._seekToProgress = seekToProgress
        self._currentTime = currentTime
        self._duration = duration
        self._isPausedByUser = isPausedByUser
        self._playbackRate = playbackRate
        self.subtitlesURL = subtitlesURL
        self.subtitlesEnabled = subtitlesEnabled
        self.onSubtitleCuesLoaded = onSubtitleCuesLoaded
    }

    func makeUIView(context: Context) -> ShotPlayerUIView {
        ShotPlayerUIView()
    }

    func updateUIView(_ view: ShotPlayerUIView, context: Context) {
        let coordinator = context.coordinator
        coordinator.playbackRate = playbackRate
        coordinator.shouldReportProgress = isActive && !preloadOnly
        coordinator.isScrubbing = isScrubbing
        coordinator.onSubtitleCuesLoaded = onSubtitleCuesLoaded
        coordinator.progressHandler = { fraction, time, total in
            progress = fraction
            currentTime = time
            duration = total
        }
        coordinator.refreshSubtitles(url: subtitlesURL, enabled: subtitlesEnabled)

        let shouldPlay = isActive && !preloadOnly

        if let url, shouldPlay || preloadOnly {
            if coordinator.currentURL != url {
                coordinator.teardownObservers()
                coordinator.currentURL = url
                videoPlaybackLogger.info("attaching player url=\(url.absoluteString, privacy: .public) shouldPlay=\(shouldPlay, privacy: .public) preload=\(preloadOnly, privacy: .public)")
                if shouldPlay {
                    do {
                        try CameraSessionConfigurator.configurePlaybackAudioSession()
                    } catch {
                        videoPlaybackLogger.error("audio session config failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
                let player = ShotFeedPlaybackCache.shared.player(for: url)
                view.player = player
                coordinator.attachObservers(
                    to: player,
                    loops: loops,
                    playbackRateProvider: { [weak coordinator] in
                        coordinator?.playbackRate ?? 1
                    }
                )
            } else if view.player == nil {
                // Player was nilled out (e.g. tab hidden) — reattach from cache.
                let player = ShotFeedPlaybackCache.shared.player(for: url)
                view.player = player
                coordinator.attachObservers(
                    to: player,
                    loops: loops,
                    playbackRateProvider: { [weak coordinator] in
                        coordinator?.playbackRate ?? 1
                    }
                )
            }

            view.player?.isMuted = isMuted
            if shouldPlay {
                updatePlaybackState(for: view)
            } else {
                view.player?.pause()
            }
        } else {
            view.player?.pause()
            if !preloadOnly {
                view.player = nil
            }
        }

        if let target = seekToProgress, let player = view.player, shouldPlay {
            coordinator.seek(player: player, to: target)
            let total = duration
            DispatchQueue.main.async {
                progress = target
                if total > 0 {
                    currentTime = total * target
                }
                seekToProgress = nil
            }
        } else if shouldPlay {
            updatePlaybackState(for: view)
        }
    }

    private func updatePlaybackState(for view: ShotPlayerUIView) {
        guard isActive, !preloadOnly, let player = view.player else {
            view.player?.pause()
            return
        }

        if isScrubbing || isPausedByUser {
            if player.rate != 0 {
                player.pause()
            }
            return
        }

        let targetRate = playbackRate
        if abs(player.rate - targetRate) > 0.01 {
            player.playImmediately(atRate: targetRate)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var currentURL: URL?
        var playbackRate: Float = 1
        var shouldReportProgress = false
        var isScrubbing = false
        var progressHandler: ((Double, TimeInterval, TimeInterval) -> Void)?
        var onSubtitleCuesLoaded: ([WebVTTCue]) -> Void = { _ in }
        private var subtitleLoadTask: Task<Void, Never>?
        private var loadedSubtitleURL: URL?
        private var subtitlesEnabled = false
        private var timeObserver: Any?
        private var endObserver: NSObjectProtocol?
        private var failedObserver: NSObjectProtocol?
        private var statusObservation: NSKeyValueObservation?
        private weak var observedPlayer: AVPlayer?

        func refreshSubtitles(url: URL?, enabled: Bool) {
            guard enabled, let url else {
                subtitlesEnabled = enabled
                if loadedSubtitleURL != nil || !enabled {
                    loadedSubtitleURL = nil
                    subtitleLoadTask?.cancel()
                    subtitleLoadTask = nil
                    DispatchQueue.main.async { [onSubtitleCuesLoaded] in
                        onSubtitleCuesLoaded([])
                    }
                }
                return
            }

            guard enabled != subtitlesEnabled || loadedSubtitleURL != url else { return }
            subtitlesEnabled = enabled
            loadedSubtitleURL = url
            subtitleLoadTask?.cancel()
            subtitleLoadTask = Task { [weak self] in
                guard let self else { return }
                let cues: [WebVTTCue]
                do {
                    cues = try await WebVTTSubtitleLoader.loadCues(from: url)
                } catch {
                    cues = []
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.onSubtitleCuesLoaded(cues)
                }
            }
        }

        func attachObservers(
            to player: AVPlayer,
            loops: Bool,
            playbackRateProvider: @escaping () -> Float
        ) {
            observedPlayer = player
            let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                guard let self,
                      self.shouldReportProgress,
                      !self.isScrubbing else { return }
                guard let itemDuration = player.currentItem?.duration,
                      itemDuration.isNumeric,
                      itemDuration.seconds > 0 else { return }
                let total = itemDuration.seconds
                let current = min(max(time.seconds, 0), total)
                let fraction = min(max(current / total, 0), 1)
                self.progressHandler?(fraction, current, total)
            }

            if loops {
                endObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: player.currentItem,
                    queue: .main
                ) { [weak self, weak player] _ in
                    guard let self, let player else { return }
                    player.seek(to: .zero)
                    player.playImmediately(atRate: playbackRateProvider())
                    self.progressHandler?(0, 0, player.currentItem?.duration.seconds ?? 0)
                }
            }

            // Observe item status to surface load failures (network, codec, 404, …).
            failedObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { _ in
                videoPlaybackLogger.error("AVPlayerItemFailedToPlayToEndTime url=\(player.currentItem?.description ?? "?", privacy: .public)")
            }

            statusObservation = player.currentItem?.observe(\.status, options: [.new]) { item, _ in
                switch item.status {
                case .readyToPlay:
                    videoPlaybackLogger.info("item readyToPlay url=\(item.description, privacy: .public)")
                case .failed:
                    let ns = item.error as NSError?
                    videoPlaybackLogger.error(
                        "item failed url=\(item.description, privacy: .public) domain=\(ns?.domain ?? "?", privacy: .public) code=\(ns?.code ?? -1) desc=\(ns?.localizedDescription ?? "?", privacy: .public)"
                    )
                default:
                    break
                }
            }
        }

        func seek(player: AVPlayer, to fraction: Double) {
            guard let itemDuration = player.currentItem?.duration,
                  itemDuration.isNumeric,
                  itemDuration.seconds > 0 else { return }
            let clamped = min(max(fraction, 0), 1)
            let target = CMTime(seconds: itemDuration.seconds * clamped, preferredTimescale: 600)
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        func teardownObservers() {
            subtitleLoadTask?.cancel()
            subtitleLoadTask = nil
            loadedSubtitleURL = nil
            if let timeObserver, let observedPlayer {
                observedPlayer.removeTimeObserver(timeObserver)
            }
            timeObserver = nil
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
            }
            endObserver = nil
            if let failedObserver {
                NotificationCenter.default.removeObserver(failedObserver)
            }
            failedObserver = nil
            statusObservation?.invalidate()
            statusObservation = nil
            observedPlayer = nil
        }
    }

    static func dismantleUIView(_ uiView: ShotPlayerUIView, coordinator: Coordinator) {
        coordinator.teardownObservers()
        uiView.player?.pause()
        uiView.player = nil
        coordinator.currentURL = nil
    }
}

struct WebVTTCue: Sendable, Equatable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

enum WebVTTParser {
    static func parse(_ raw: String) -> [WebVTTCue] {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        var cues: [WebVTTCue] = []
        var index = normalized.startIndex

        while index < normalized.endIndex {
            guard let arrowRange = normalized.range(of: "-->", range: index..<normalized.endIndex) else {
                break
            }

            let timingLineStart = normalized[..<arrowRange.lowerBound]
            let startToken = timingLineStart
                .split(whereSeparator: \.isWhitespace)
                .last
                .map(String.init) ?? ""
            let endToken = normalized[arrowRange.upperBound...]
                .split(whereSeparator: \.isWhitespace)
                .first
                .map(String.init) ?? ""

            guard let start = parseTimestamp(startToken),
                  let end = parseTimestamp(endToken),
                  end > start
            else {
                index = arrowRange.upperBound
                continue
            }

            var lineEnd = normalized.index(after: arrowRange.upperBound)
            while lineEnd < normalized.endIndex, normalized[lineEnd].isNewline == false {
                lineEnd = normalized.index(after: lineEnd)
            }

            var textStart = lineEnd
            if textStart < normalized.endIndex, normalized[textStart].isNewline {
                textStart = normalized.index(after: textStart)
            }

            var textEnd = textStart
            while textEnd < normalized.endIndex {
                if normalized[textEnd].isNewline {
                    let next = normalized.index(after: textEnd)
                    if next < normalized.endIndex, normalized[next].isNewline {
                        break
                    }
                }
                textEnd = normalized.index(after: textEnd)
            }

            let body = String(normalized[textStart..<textEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                cues.append(WebVTTCue(start: start, end: end, text: body))
            }

            index = textEnd
        }

        return cues.sorted { $0.start < $1.start }
    }

    static func activeCue(at time: TimeInterval, in cues: [WebVTTCue]) -> String? {
        cues.first { time >= $0.start && time < $0.end }?.text
    }

    private static func parseTimestamp(_ token: String) -> TimeInterval? {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }

        if parts.count == 3 {
            guard let hours = Double(parts[0]),
                  let minutes = Double(parts[1]),
                  let seconds = Double(parts[2])
            else { return nil }
            return hours * 3600 + minutes * 60 + seconds
        }

        guard let minutes = Double(parts[0]),
              let seconds = Double(parts[1])
        else { return nil }
        return minutes * 60 + seconds
    }
}

enum WebVTTSubtitleLoader {
    static func loadCues(from url: URL) async throws -> [WebVTTCue] {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }
        return WebVTTParser.parse(text)
    }
}
