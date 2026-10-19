import SwiftUI

struct ChatPollBubble<Meta: View>: View {
    let message: DMMessage
    let poll: DMPoll
    let isMine: Bool
    let currentUserID: String
    var memberName: (String) -> String = { _ in "" }
    var memberAvatarURL: (String) -> URL? = { _ in nil }
    var onVote: ([Int]) -> Void = { _ in }
    var onAppend: (String) -> Void = { _ in }
    @ViewBuilder var meta: () -> Meta

    @Environment(\.chatBubbleInteractionLocked) private var interactionLocked
    @State private var selected: Set<Int> = []
    @State private var showAdd = false
    @State private var draft = ""
    @State private var showVoters = false
    @State private var shake = false
    @State private var quizHaptic = 0
    @State private var quizWasCorrect = false

    private var isAuthor: Bool {
        message.senderID == currentUserID || message.senderID == "me"
    }

    private var myOptionIDs: Set<Int> {
        Set(message.pollVotes.filter { $0.userID == currentUserID }.map(\.optionID))
    }

    private var hasVoted: Bool {
        ChatPollState.hasVoted(message.pollVotes, userID: currentUserID)
    }

    private var revealed: Bool {
        ChatPollState.isRevealed(poll, hasVoted: hasVoted)
    }

    private var canVote: Bool {
        ChatPollState.canVote(poll, hasVoted: hasVoted, isPending: message.isPending)
            && message.deletedAt == nil
    }

    private var counts: [Int: Int] {
        var map = Dictionary(uniqueKeysWithValues: poll.options.map { ($0.id, 0) })
        for tally in message.pollTallies where map[tally.optionID] != nil {
            map[tally.optionID] = tally.count
        }
        return map
    }

    private var percents: [Int: Int] {
        ChatPollState.percentages(counts: counts)
    }

    private var recentVoters: [String] {
        var seen = Set<String>()
        var ids: [String] = []
        for vote in message.pollVotes.reversed() {
            if seen.insert(vote.userID).inserted {
                ids.append(vote.userID)
            }
            if ids.count == 3 { break }
        }
        return ids
    }

    private var subtitle: String {
        if poll.closed { return "Final Results" }
        if poll.quiz { return "Quiz" }
        return poll.anonymous ? "Anonymous Poll" : "Public Poll"
    }

    private var quizSignature: String {
        "\(revealed)-\(poll.correctOptionID ?? 0)-\(myOptionIDs.sorted())"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: poll.quiz ? "questionmark.circle" : "chart.bar.xaxis")
                    .font(.caption.weight(.semibold))
                Text(subtitle)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isMine ? Color.white.opacity(0.75) : .secondary)

            Text(poll.question)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isMine ? Color.white : .primary)
                .fixedSize(horizontal: false, vertical: true)

            if !poll.anonymous, !recentVoters.isEmpty {
                voterStack
            }

            VStack(spacing: 6) {
                ForEach(poll.options) { option in
                    optionRow(option)
                }
            }
            .offset(x: shake ? -6 : 0)

            if poll.multiple, !revealed, canVote {
                Button("Vote") {
                    guard !selected.isEmpty else { return }
                    onVote(selected.sorted())
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(isMine ? Color.accentColor : Color.white)
                .background(isMine ? Color.white : Color.accentColor, in: Capsule())
                .buttonStyle(.plain)
                .disabled(selected.isEmpty || interactionLocked)
            }

            if revealed, poll.quiz, let explanation = poll.explanation, !explanation.isEmpty {
                Label(explanation, systemImage: "lightbulb")
                    .font(.caption)
                    .foregroundStyle(isMine ? Color.white.opacity(0.9) : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text(voteCountLabel)
                    .font(.caption)
                    .foregroundStyle(isMine ? Color.white.opacity(0.7) : .secondary)
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                if !poll.anonymous, revealed {
                    Button("View Results") { showVoters = true }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                }
                if ChatPollState.canAddOption(poll, isAuthor: isAuthor), !message.isPending {
                    Button("Add Option") { showAdd = true }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                }
            }

            meta()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: percents)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: shake)
        .sensoryFeedback(quizWasCorrect ? .success : .error, trigger: quizHaptic)
        .onChange(of: quizSignature) { _, _ in
            reactToQuizReveal()
        }
        .alert("Add Option", isPresented: $showAdd) {
            TextField("Option", text: $draft)
            Button("Add") {
                let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                draft = ""
                guard !text.isEmpty else { return }
                onAppend(text)
            }
            Button("Cancel", role: .cancel) { draft = "" }
        }
        .sheet(isPresented: $showVoters) {
            ChatPollVotersSheet(
                poll: poll,
                votes: message.pollVotes,
                memberName: memberName,
                memberAvatarURL: memberAvatarURL
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var voteCountLabel: String {
        let count = message.pollTotalVoters
        return count == 1 ? "1 vote" : "\(count) votes"
    }

    private func memberUser(_ userID: String) -> User {
        let label = memberName(userID)
        let name = label.isEmpty ? "Member" : label
        return User(
            id: userID,
            username: name,
            displayName: name,
            bio: nil,
            avatarURL: memberAvatarURL(userID),
            suiWallet: nil,
            createdAt: nil
        )
    }

    private var voterStack: some View {
        HStack(spacing: -6) {
            ForEach(recentVoters, id: \.self) { userID in
                UserAvatarView(user: memberUser(userID), size: 18)
                    .overlay { Circle().strokeBorder(Color.white, lineWidth: 1) }
            }
        }
    }

    private func optionRow(_ option: DMPollOption) -> some View {
        let percent = percents[option.id] ?? 0
        let chosen = myOptionIDs.contains(option.id) || selected.contains(option.id)
        let correct = poll.quiz && revealed && poll.correctOptionID == option.id
        let wrong = poll.quiz && revealed && chosen && poll.correctOptionID != nil && poll.correctOptionID != option.id
        return HStack(spacing: 8) {
            if revealed {
                percentLabel(percent)
            }
            Text(option.text)
                .font(.subheadline)
                .foregroundStyle(isMine ? Color.white : Color.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            marker(optionID: option.id, chosen: chosen, correct: correct, wrong: wrong)
                .frame(width: 18, height: 18)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(trackColor)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(barColor(correct: correct))
                            .frame(width: revealed ? geo.size.width * CGFloat(percent) / 100 : 0)
                    }
                }
                .overlay {
                    if wrong {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.red.opacity(isMine ? 0.7 : 0.55), lineWidth: 1)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            guard !interactionLocked else { return }
            tap(option.id)
        }
    }

    private func tap(_ optionID: Int) {
        guard canVote else { return }
        if poll.multiple {
            if selected.contains(optionID) {
                selected.remove(optionID)
            } else {
                selected.insert(optionID)
            }
            return
        }
        onVote([optionID])
    }

    /// Column sized by "100%" so every percentage stays intact at the current text size.
    private func percentLabel(_ percent: Int) -> some View {
        ZStack(alignment: .trailing) {
            Text("100%")
                .hidden()
            Text("\(percent)%")
                .contentTransition(.numericText())
        }
        .font(.caption.weight(.semibold).monospacedDigit())
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(isMine ? Color.white.opacity(0.92) : Color.secondary)
    }

    @ViewBuilder
    private func marker(optionID: Int, chosen: Bool, correct: Bool, wrong: Bool) -> some View {
        if correct {
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(isMine ? Color.white : Color.green)
        } else if wrong {
            Image(systemName: "xmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.red.opacity(0.9))
        } else if poll.multiple, !revealed {
            Image(systemName: chosen ? "checkmark.square.fill" : "square")
                .font(.subheadline)
                .foregroundStyle(isMine ? Color.white : Color.primary)
        } else if !revealed {
            Image(systemName: "circle")
                .font(.subheadline)
                .foregroundStyle(isMine ? Color.white.opacity(0.7) : Color.secondary)
        } else if myOptionIDs.contains(optionID) {
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(isMine ? Color.white : Color.accentColor)
        }
    }

    private var trackColor: Color {
        isMine ? Color.white.opacity(0.14) : Color.primary.opacity(0.06)
    }

    private func barColor(correct: Bool) -> Color {
        if correct { return Color.green.opacity(isMine ? 0.5 : 0.28) }
        return isMine ? Color.white.opacity(0.28) : Color.accentColor.opacity(0.28)
    }

    private func reactToQuizReveal() {
        guard poll.quiz, revealed, let correct = poll.correctOptionID, hasVoted else { return }
        let correctChoice = myOptionIDs.contains(correct)
        quizWasCorrect = correctChoice
        quizHaptic += 1
        guard !correctChoice else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.35)) {
            shake = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            shake = false
        }
    }
}

private struct ChatPollVotersSheet: View {
    let poll: DMPoll
    let votes: [DMPollVote]
    var memberName: (String) -> String
    var memberAvatarURL: (String) -> URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(poll.options) { option in
                    Section(option.text) {
                        let people = votes.filter { $0.optionID == option.id }
                        if people.isEmpty {
                            Text("No votes")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(people, id: \.userID) { vote in
                                HStack(spacing: 10) {
                                    UserAvatarView(user: memberUser(vote.userID), size: 28)
                                    Text(name(vote.userID))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func name(_ userID: String) -> String {
        let resolved = memberName(userID)
        return resolved.isEmpty ? "Member" : resolved
    }

    private func memberUser(_ userID: String) -> User {
        let label = name(userID)
        return User(
            id: userID,
            username: label,
            displayName: label,
            bio: nil,
            avatarURL: memberAvatarURL(userID),
            suiWallet: nil,
            createdAt: nil
        )
    }
}
