import SwiftUI

struct PaywallPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(CameraChrome.accent)

                Text("Premium Feature")
                    .font(.title2.weight(.bold))

                Text("Record up to 10 minutes of video with Take Premium.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)

                Button("Upgrade to Premium") {}
                    .buttonStyle(.borderedProminent)
                    .tint(CameraChrome.accent)
                    .disabled(true)

                Text("Coming soon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
