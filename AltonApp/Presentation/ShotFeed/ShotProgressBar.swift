import SwiftUI
import UIKit

struct ShotProgressBar: View {
    @Binding var progress: Double
    @Binding var isScrubbing: Bool
    let onSeek: (Double) -> Void

    private var trackHeight: CGFloat { isScrubbing ? 6 : 2 }
    private var thumbSize: CGFloat { isScrubbing ? 14 : 8 }
    private var containerHeight: CGFloat { isScrubbing ? 36 : 22 }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let thumbCenterX = width * progress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(Color.white)
                    .frame(width: max(thumbCenterX, trackHeight), height: trackHeight)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(x: thumbOffset(in: width))
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .animation(.easeInOut(duration: 0.2), value: isScrubbing)
            .contentShape(Rectangle().inset(by: -14))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isScrubbing {
                            ShotHaptics.scrubBegan()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isScrubbing = true
                            }
                        }
                        progress = min(max(value.location.x / width, 0), 1)
                    }
                    .onEnded { _ in
                        onSeek(progress)
                        ShotHaptics.scrubEnded()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isScrubbing = false
                        }
                    }
            )
        }
        .frame(height: containerHeight)
        .animation(.easeInOut(duration: 0.2), value: isScrubbing)
        .padding(.horizontal, isScrubbing ? 0 : 12)
    }

    private func thumbOffset(in width: CGFloat) -> CGFloat {
        let halfThumb = thumbSize / 2
        let centerX = width * progress
        return min(max(centerX - halfThumb, -halfThumb), width - halfThumb)
    }
}

func formatVideoTime(_ time: TimeInterval) -> String {
    let totalSeconds = max(0, Int(time.rounded()))
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%02d:%02d", minutes, seconds)
}
