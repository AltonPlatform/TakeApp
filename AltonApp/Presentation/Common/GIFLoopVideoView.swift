import AVFoundation
import SwiftUI
import UIKit

/// Muted looping MP4 for the GIF picker grid. Hardware decode — no ImageIO.
/// Intrinsic size is zero so SwiftUI grid columns are not resized by the video.
struct GIFLoopVideoView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> GIFLoopPlayerUIView {
        let view = GIFLoopPlayerUIView(frame: .zero)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.load(url: url)
        return view
    }

    func updateUIView(_ uiView: GIFLoopPlayerUIView, context: Context) {
        if uiView.currentURL != url {
            uiView.load(url: url)
        }
    }

    static func dismantleUIView(_ uiView: GIFLoopPlayerUIView, coordinator: ()) {
        uiView.teardown()
    }
}

final class GIFLoopPlayerUIView: UIView {
    private(set) var currentURL: URL?

    override var intrinsicContentSize: CGSize { .zero }

    private let playerLayer = AVPlayerLayer()
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        backgroundColor = .clear
        isOpaque = false
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = UIColor.clear.cgColor
        playerLayer.isHidden = true
        layer.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    func load(url: URL) {
        guard currentURL != url else { return }
        teardown()
        currentURL = url

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = true
        self.player = player
        playerLayer.player = player
        playerLayer.isHidden = true

        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self, item.status == .readyToPlay else { return }
            DispatchQueue.main.async {
                guard self.currentURL == url else { return }
                self.playerLayer.isHidden = false
                self.player?.play()
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.currentURL == url else { return }
            self.player?.seek(to: .zero)
            self.player?.play()
        }
    }

    func teardown() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        playerLayer.player = nil
        playerLayer.isHidden = true
        currentURL = nil
    }

    deinit {
        teardown()
    }
}
