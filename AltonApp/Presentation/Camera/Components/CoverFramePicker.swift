import AVFoundation
import SwiftUI
import UIKit

struct CoverFramePicker: View {
    let videoURL: URL
    @Binding var selectedTime: CMTime
    @Binding var coverImage: UIImage?

    @Environment(\.dismiss) private var dismiss
    @State private var duration: Double = 1
    @State private var scrub: Double = 0
    @State private var preview: UIImage?
    @State private var filmstrip: [UIImage] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Group {
                    if let preview {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        ProgressView()
                            .frame(height: 360)
                    }
                }

                if !filmstrip.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(Array(filmstrip.enumerated()), id: \.offset) { index, image in
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 48, height: 72)
                                    .clipped()
                                    .onTapGesture {
                                        let t = duration * Double(index) / Double(max(filmstrip.count - 1, 1))
                                        scrub = t
                                        Task { await refreshPreview() }
                                    }
                            }
                        }
                    }
                    .frame(height: 72)
                }

                Slider(value: $scrub, in: 0...max(duration, 0.1))
                    .tint(.blue)
                    .onChange(of: scrub) { _, _ in
                        Task { await refreshPreview() }
                    }

                Text("Select a frame for the cover")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        selectedTime = CMTime(seconds: scrub, preferredTimescale: 600)
                        coverImage = preview
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .task {
                scrub = selectedTime.seconds
                await loadDurationAndFilmstrip()
                await refreshPreview()
            }
        }
    }

    private func loadDurationAndFilmstrip() async {
        let asset = AVURLAsset(url: videoURL)
        do {
            let d = try await asset.load(.duration).seconds
            duration = max(d, 0.1)
            scrub = min(max(scrub, 0), duration)
            filmstrip = await Self.generateFilmstrip(from: videoURL, duration: duration, count: 12)
        } catch {
            duration = 1
        }
    }

    private func refreshPreview() async {
        let time = CMTime(seconds: scrub, preferredTimescale: 600)
        preview = await Self.generateFrame(from: videoURL, at: time)
    }

    static func generateFrame(from url: URL, at time: CMTime) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 720, height: 1280)
            do {
                let (cg, _) = try await generator.image(at: time)
                return UIImage(cgImage: cg)
            } catch {
                return nil
            }
        }.value
    }

    private static func generateFilmstrip(from url: URL, duration: Double, count: Int) async -> [UIImage] {
        await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 120, height: 180)
            var images: [UIImage] = []
            for i in 0..<count {
                let t = duration * Double(i) / Double(max(count - 1, 1))
                let time = CMTime(seconds: t, preferredTimescale: 600)
                if let (cg, _) = try? await generator.image(at: time) {
                    images.append(UIImage(cgImage: cg))
                }
            }
            return images
        }.value
    }
}
