import AVFoundation
import Foundation
import UIKit

/// Keeps a small LRU pool of AVPlayer instances for adjacent feed pages.
@MainActor
final class ShotFeedPlaybackCache {
    static let shared = ShotFeedPlaybackCache()

    private var players: [URL: AVPlayer] = [:]
    private var accessOrder: [URL] = []
    private let maxPlayers = 7

    private init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.clearAll()
            }
        }
    }

    func player(for url: URL) -> AVPlayer {
        if let existing = players[url] {
            touch(url)
            return existing
        }

        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 5
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        player.isMuted = false
        player.volume = 1

        players[url] = player
        touch(url)
        trimIfNeeded(keeping: url)
        return player
    }

    func preload(_ url: URL?) {
        guard let url else { return }
        _ = player(for: url)
        players[url]?.pause()
        players[url]?.rate = 0
    }

    func warmAdjacent(currentIndex: Int, urls: [URL?]) {
        guard !urls.isEmpty else { return }
        var keep: Set<URL> = []
        for offset in -3...3 {
            let index = currentIndex + offset
            guard urls.indices.contains(index), let url = urls[index] else { continue }
            keep.insert(url)
            if offset == 0 {
                _ = player(for: url)
            } else {
                preload(url)
            }
        }
        evictAllExcept(keep)
    }

    func clearAll() {
        for url in players.keys {
            players[url]?.pause()
            players[url]?.replaceCurrentItem(with: nil)
        }
        players.removeAll()
        accessOrder.removeAll()
    }

    func evictAllExcept(_ keep: Set<URL>) {
        for url in players.keys where !keep.contains(url) {
            players[url]?.pause()
            players[url]?.replaceCurrentItem(with: nil)
            players.removeValue(forKey: url)
            accessOrder.removeAll { $0 == url }
        }
    }

    private func touch(_ url: URL) {
        accessOrder.removeAll { $0 == url }
        accessOrder.append(url)
    }

    private func trimIfNeeded(keeping recent: URL) {
        var keepSet: Set<URL> = [recent]
        for url in accessOrder.reversed() where keepSet.count < maxPlayers {
            keepSet.insert(url)
        }
        evictAllExcept(keepSet)
    }
}
