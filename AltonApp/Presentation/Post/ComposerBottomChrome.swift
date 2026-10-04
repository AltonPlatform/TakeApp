import SwiftUI

/// Rule deciding whether the composer's Post pill is tappable.
struct ComposerPublishState: Equatable {
    let canSubmitContent: Bool
    let isSubmitting: Bool

    var canPublish: Bool { !isSubmitting && canSubmitContent }
}

/// Bottom glass chrome of the Take composer (skeleton).
///
/// Hosts the tool row (`tools`) and the primary Post pill. Task 3 replaces this
/// skeleton with the format capsule, the real tool row and the character meter.
struct ComposerBottomChrome<Tools: View>: View {
    let publishState: ComposerPublishState
    var publishTitle = "Post"
    let onPublish: () -> Void
    @ViewBuilder let tools: () -> Tools

    var body: some View {
        HStack(spacing: 8) {
            tools()
            postPill
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
    }

    private var postPill: some View {
        Button(action: onPublish) {
            Group {
                if publishState.isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Text(publishTitle).font(.subheadline.weight(.semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(minWidth: 44)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(#colorLiteral(red: 0.1098, green: 0.1098, blue: 0.1176, alpha: 1)), in: Capsule())
            .opacity(publishState.canPublish ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!publishState.canPublish)
        .accessibilityLabel(publishTitle)
    }
}
