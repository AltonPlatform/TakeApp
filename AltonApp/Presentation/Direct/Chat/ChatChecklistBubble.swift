import SwiftUI
import UIKit

struct ChatChecklistBubble<Meta: View>: View {
    let message: DMMessage
    let checklist: DMChecklist
    let isMine: Bool
    let currentUserID: String
    var isGroup: Bool = false
    var memberName: (String) -> String = { _ in "" }
    var memberAvatarURL: (String) -> URL? = { _ in nil }
    var onToggle: (Int) -> Void = { _ in }
    var onAppend: (String) -> Void = { _ in }
    @ViewBuilder var meta: () -> Meta

    @Environment(\.chatBubbleInteractionLocked) private var interactionLocked
    @State private var showAdd = false
    @State private var draft = ""
    @State private var shakenID: Int?
    @State private var shakeX: CGFloat = 0
    @State private var markHaptic = 0

    private var isAuthor: Bool {
        message.senderID == currentUserID || message.senderID == "me"
    }

    private var canMark: Bool {
        ChatChecklistState.canMark(checklist, isAuthor: isAuthor) && !message.isPending
    }

    private var canAdd: Bool {
        ChatChecklistState.canAdd(checklist, isAuthor: isAuthor) && !message.isPending
    }

    private var doneCount: Int {
        let ids = Set(checklist.items.map(\.id))
        return message.checklistMarks.filter { ids.contains($0.itemID) }.count
    }

    private var progress: CGFloat {
        guard !checklist.items.isEmpty else { return 0 }
        return CGFloat(doneCount) / CGFloat(checklist.items.count)
    }

    private var markSignature: String {
        message.checklistMarks.map { "\($0.itemID):\($0.userID)" }.joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.subheadline.weight(.semibold))
                Text(checklist.title.isEmpty ? "Checklist" : checklist.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
            }
            .foregroundStyle(isMine ? Color.white : Color.primary)

            Text("Checklist · \(doneCount) of \(checklist.items.count)")
                .font(.caption)
                .foregroundStyle(isMine ? Color.white.opacity(0.75) : Color.secondary)

            progressBar

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(checklist.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Rectangle()
                            .fill((isMine ? Color.white : Color.primary).opacity(0.12))
                            .frame(height: 0.5)
                            .padding(.leading, 30)
                    }
                    itemRow(item)
                }
            }

            HStack(alignment: .center, spacing: 8) {
                if canAdd {
                    Button {
                        guard !interactionLocked else { return }
                        draft = ""
                        showAdd = true
                    } label: {
                        Label("Add Task", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isMine ? Color.white : Color.accentColor)
                }
                Spacer(minLength: 0)
                meta()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(response: 0.2, dampingFraction: 0.85), value: markSignature)
        .sensoryFeedback(.impact(weight: .light), trigger: markHaptic)
        .alert("Add Task", isPresented: $showAdd) {
            TextField("Task", text: $draft)
            Button("Add") { submitDraft() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill((isMine ? Color.white : Color.accentColor).opacity(0.22))
                Capsule()
                    .fill(isMine ? Color.white : Color.accentColor)
                    .frame(width: max(0, geo.size.width * progress))
            }
        }
        .frame(height: 3)
    }

    private func itemRow(_ item: DMChecklistItem) -> some View {
        let mark = message.checklistMarks.first { $0.itemID == item.id }
        let done = mark != nil
        return HStack(alignment: .center, spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(circleColor(done: done))
                .symbolEffect(.bounce, options: .speed(1.8), value: done)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .font(.subheadline)
                    .strikethrough(done)
                    .foregroundStyle(textColor(done: done))
                    .multilineTextAlignment(.leading)
                if done, isGroup, let userID = mark?.userID {
                    HStack(spacing: 4) {
                        UserAvatarView(
                            user: User(
                                id: userID,
                                username: memberName(userID),
                                displayName: memberName(userID),
                                bio: nil,
                                avatarURL: memberAvatarURL(userID),
                                suiWallet: nil,
                                createdAt: nil
                            ),
                            size: 16
                        )
                        Text(memberName(userID))
                            .font(.caption2)
                            .foregroundStyle(isMine ? Color.white.opacity(0.7) : Color.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 38)
        .contentShape(Rectangle())
        .offset(x: shakenID == item.id ? shakeX : 0)
        .onTapGesture {
            guard !interactionLocked else { return }
            guard canMark else {
                refuse(item.id)
                return
            }
            markHaptic += 1
            onToggle(item.id)
        }
    }

    private func circleColor(done: Bool) -> Color {
        if !canMark && !done {
            return (isMine ? Color.white : Color.secondary).opacity(0.35)
        }
        if done {
            return isMine ? Color.white : Color.accentColor
        }
        return isMine ? Color.white.opacity(0.85) : Color.secondary
    }

    private func textColor(done: Bool) -> Color {
        if done {
            return (isMine ? Color.white : Color.primary).opacity(0.55)
        }
        return isMine ? Color.white : Color.primary
    }

    private func refuse(_ itemID: Int) {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        shakenID = itemID
        shakeX = 0
        withAnimation(.linear(duration: 0.05)) { shakeX = 6 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.linear(duration: 0.05)) { shakeX = -6 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            withAnimation(.linear(duration: 0.05)) { shakeX = 3 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.08)) { shakeX = 0 }
        }
    }

    private func submitDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        guard !text.isEmpty else { return }
        onAppend(String(text.prefix(100)))
    }
}
