import MapKit
import SwiftUI

enum ChatLocationBubbleMetrics {
    static let mapWidth: CGFloat = 264
    static let mapHeight: CGFloat = 164
}

struct ChatLocationBubble<Meta: View>: View {

    let location: DMLocation
    let isMine: Bool
    @ViewBuilder var meta: () -> Meta

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var snapshot: UIImage?
    @State private var pinLanded = false
    @State private var pulse = false

    private var isMyLocation: Bool {
        location.name == "My Location"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let snapshot {
                    Image(uiImage: snapshot)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    ChatLocationShimmer()
                }
                pin
            }
            .frame(width: ChatLocationBubbleMetrics.mapWidth, height: ChatLocationBubbleMetrics.mapHeight)
            .frame(maxWidth: .infinity, alignment: isMine ? .leading : .trailing)
            .clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text(location.name ?? "Location")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isMine ? Color.white : Color.primary)
                    .lineLimit(1)
                if let address = location.address, !address.isEmpty {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(isMine ? Color.white.opacity(0.75) : Color.secondary)
                        .lineLimit(2)
                }
                meta()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .animation(.easeOut(duration: 0.35), value: snapshot != nil)
        .task(id: taskID) {
            let scale = max(displayScale, 1)
            let image = await ChatMapSnapshot.image(
                for: location,
                size: CGSize(width: ChatLocationBubbleMetrics.mapWidth, height: ChatLocationBubbleMetrics.mapHeight),
                scale: scale,
                colorScheme: colorScheme
            )
            snapshot = image
            guard image != nil else { return }
            pinLanded = false
            withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
                pinLanded = true
            }
            if isMyLocation {
                pulse = false
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
        }
    }

    private var pin: some View {
        ZStack {
            if isMyLocation {
                Circle()
                    .stroke(Color.accentColor.opacity(0.45), lineWidth: 2)
                    .frame(width: 28, height: 28)
                    .scaleEffect(pulse ? 1.8 : 1)
                    .opacity(pulse ? 0 : 0.9)
            }
            Circle()
                .fill(Color.accentColor)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(Color.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.28), radius: 3, y: 2)
                .scaleEffect(pinLanded ? 1 : 0.55)
                .offset(y: pinLanded ? 0 : -16)
        }
        .opacity(snapshot == nil ? 0 : 1)
        .allowsHitTesting(false)
    }

    private var taskID: String {
        let style = colorScheme == .dark ? "d" : "l"
        return String(format: "%.5f,%.5f,%@,%.0f", location.lat, location.lng, style, displayScale)
    }
}

private struct ChatLocationShimmer: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [
                    Color.secondary.opacity(0.10),
                    Color.secondary.opacity(0.28),
                    Color.secondary.opacity(0.10),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.55)
            .offset(x: phase * geo.size.width)
        }
        .background(Color.secondary.opacity(0.12))
        .clipped()
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                phase = 1.5
            }
        }
    }
}
