import SwiftUI

enum ChatExpressionTab: String, CaseIterable, Identifiable {
    case stickers
    case gif
    case emoji

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stickers: return "Stickers"
        case .gif: return "GIF"
        case .emoji: return "Emoji"
        }
    }

    var symbol: String {
        switch self {
        case .stickers: return "face.smiling"
        case .gif: return "gift"
        case .emoji: return "smiley"
        }
    }
}

struct ChatExpressionSheet: View {
    var stickersUseCase: StickersUseCase?
    var onPickSticker: (Sticker) -> Void
    var onPickGIF: (KlipyGIF) -> Void
    var onInsertEmoji: (String) -> Void

    @AppStorage("chat.expression.tab") private var storedTab = ChatExpressionTab.stickers.rawValue
    @State private var tab: ChatExpressionTab = .stickers
    @State private var contentReady = true
    @State private var contentReveal: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if !contentReady {
                    expressionSkeleton
                } else {
                    switch tab {
                    case .stickers:
                        if let stickersUseCase {
                            StickerPackGridView(stickersUseCase: stickersUseCase) { sticker in
                                dismiss()
                                onPickSticker(sticker)
                            }
                        } else {
                            ContentUnavailableView(
                                "Stickers unavailable",
                                systemImage: "face.smiling",
                                description: Text("Sign in to load sticker packs.")
                            )
                        }
                    case .gif:
                        KlipyGIFGridView { gif in
                            dismiss()
                            onPickGIF(gif)
                        }
                        .onAppear {
                            GIFThumbGate.setAllowed(true)
                            Task { await GIFAnimateSlots.shared.noteMounted() }
                        }
                        .onDisappear {
                            GIFThumbGate.setAllowed(false)
                            Task { await GIFAnimateSlots.shared.stop() }
                        }
                    case .emoji:
                        EmojiGridView { emoji in
                            onInsertEmoji(emoji)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            tabBar
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            if let restored = ChatExpressionTab(rawValue: storedTab) {
                tab = restored
            }
            KlipyGIFCatalog.shared.ensureTrending()
        }
        .onDisappear {
            GIFThumbGate.setAllowed(false)
            Task { await GIFAnimateSlots.shared.stop() }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ChatExpressionTab.allCases) { item in
                Button {
                    select(item)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol)
                            .font(.body.weight(.semibold))
                        Text(item.title)
                            .font(.caption2.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(tab == item ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .directGlass(Capsule())
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var expressionSkeleton: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 120, height: 28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 140)
                }
            }
            .padding(.horizontal, 12)
            Spacer()
        }
        .padding(.top, 12)
    }

    private func select(_ item: ChatExpressionTab) {
        if tab == .gif, item != .gif {
            GIFThumbGate.setAllowed(false)
            Task { await GIFAnimateSlots.shared.stop() }
        }
        storedTab = item.rawValue
        tab = item
        contentReveal?.cancel()
        contentReady = false
        contentReveal = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            contentReady = true
        }
    }
}
