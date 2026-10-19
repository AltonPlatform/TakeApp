import SwiftUI

struct DMPhotoReviewView: View {
    let photo: ChatCapturedPhoto
    var onRetake: () -> Void
    var onEdit: () -> Void
    var onAddText: () -> Void
    var onUse: () -> Void

    @State private var fullImage: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Image(uiImage: fullImage ?? photo.preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onAddText)
                    .task(id: photo.fileURL) {
                        let url = photo.fileURL
                        let image = await Task.detached(priority: .userInitiated) {
                            try? PhotoFinisher.loadFullImage(at: url)
                        }.value
                        fullImage = image
                    }

                HStack(spacing: 20) {
                    reviewButton("Retake", systemImage: "arrow.counterclockwise", action: onRetake)
                    reviewButton("Edit", systemImage: "pencil.tip.crop.circle", action: onEdit)
                    Button(action: onUse) {
                        Text("Use")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
        }
    }

    private func reviewButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(width: 72)
        }
        .buttonStyle(.plain)
    }
}
