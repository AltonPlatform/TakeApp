import SwiftUI
import UIKit

struct ShotOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var playbackSpeedIndex: Int
    @Binding var lockedSpeedIndex: Int?
    @Binding var isCleanMode: Bool
    @Binding var subtitlesEnabled: Bool
    var subtitlesAvailable: Bool = false
    var canReport: Bool = true
    var onReport: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    optionsGroup {
                        optionButton(icon: "heart.slash", title: "Not interested") { dismiss() }
                        if canReport, let onReport {
                            optionButton(icon: "flag", title: "Report") {
                                dismiss()
                                onReport()
                            }
                        }
                    }

                    optionsGroup {
                        speedRow
                        cleanModeRow
                        subtitlesRow
                        optionButton(icon: "pip.enter", title: "Picture in picture") { dismiss() }
                    }

                    optionsGroup {
                        optionButton(icon: "questionmark.circle", title: "Why this post") { dismiss() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var speedRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "speedometer")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                Text("Speed")
                    .font(.body)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(ShotPlaybackSpeed.rates.enumerated()), id: \.offset) { index, rate in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                playbackSpeedIndex = index
                                lockedSpeedIndex = index
                            }
                            ShotHaptics.speedStep()
                        } label: {
                            Text(speedButtonLabel(rate))
                                .font(.subheadline.weight(playbackSpeedIndex == index ? .semibold : .regular))
                                .foregroundStyle(playbackSpeedIndex == index ? Color.primary : Color.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    playbackSpeedIndex == index
                                        ? Color(.secondarySystemGroupedBackground)
                                        : Color(.tertiarySystemGroupedBackground),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var subtitlesRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "captions.bubble")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text("Subtitles & translation")
                .font(.body)
            Spacer()
            Toggle("", isOn: $subtitlesEnabled)
                .labelsHidden()
                .disabled(!subtitlesAvailable)
                .onChange(of: subtitlesEnabled) { _, _ in
                    ShotHaptics.speedStep()
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .opacity(subtitlesAvailable ? 1 : 0.45)
    }

    private var cleanModeRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "viewfinder")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text("Clear mode")
                .font(.body)
            Spacer()
            Toggle("", isOn: $isCleanMode)
                .labelsHidden()
                .onChange(of: isCleanMode) { _, _ in
                    ShotHaptics.speedStep()
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func optionsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func optionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button {
            ShotHaptics.menuOpened()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func speedButtonLabel(_ rate: Float) -> String {
        if rate == floor(rate) {
            return String(format: "%.0fx", rate)
        }
        return String(format: "%.2gx", rate)
    }
}

private struct ShotLikeBurst: View {
    let location: CGPoint
    @State private var scale: CGFloat = 0.35
    @State private var opacity: Double = 1

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 92))
            .foregroundStyle(.red)
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            .scaleEffect(scale)
            .opacity(opacity)
            .position(location)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
                    scale = 1.05
                }
                withAnimation(.easeOut(duration: 0.55).delay(0.15)) {
                    opacity = 0
                    scale = 1.3
                }
            }
    }
}

struct ShotLikeBurstOverlay: View {
    let bursts: [ShotLikeBurstItem]

    var body: some View {
        ZStack {
            ForEach(bursts) { burst in
                ShotLikeBurst(location: burst.location)
                    .id(burst.id)
            }
        }
        .allowsHitTesting(false)
    }
}

struct ShotLikeBurstItem: Identifiable {
    let id = UUID()
    let location: CGPoint
}
