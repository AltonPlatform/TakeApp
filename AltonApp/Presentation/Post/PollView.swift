import SwiftUI

struct PollView: View {
    let poll: Poll
    var onVote: ((Int) async -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(poll.question)
                .font(.subheadline.weight(.semibold))

            ForEach(Array(poll.options.enumerated()), id: \.offset) { index, option in
                Button {
                    guard poll.viewerVote == nil else { return }
                    Task { await onVote?(index) }
                } label: {
                    optionRow(index: index, option: option)
                }
                .buttonStyle(.plain)
                .disabled(poll.viewerVote != nil || onVote == nil)
            }

            Text("\(poll.votesCount) votes")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func optionRow(index: Int, option: PollOption) -> some View {
        let selected = poll.viewerVote == index
        let fraction: CGFloat = poll.votesCount > 0
            ? CGFloat(option.votes) / CGFloat(poll.votesCount)
            : 0

        return ZStack(alignment: .leading) {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(selected ? 0.25 : 0.12))
                    .frame(width: geo.size.width * fraction)
            }

            HStack {
                Text(option.text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                if poll.viewerVote != nil {
                    Text("\(option.votes)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .frame(height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(.separator), lineWidth: 1)
        )
    }
}
