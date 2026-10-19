import NukeUI
import SwiftUI

/// Pack chips and a four-column sticker grid. Used by comments and the chat expression sheet.
struct StickerPackGridView: View {
    let stickersUseCase: StickersUseCase
    let onSelect: (Sticker) -> Void

    @State private var packs: [StickerPackSummary] = []
    @State private var selectedPackID: String?
    @State private var detail: StickerPackDetail?
    @State private var isLoadingPacks = false
    @State private var isLoadingDetail = false
    @State private var errorMessage: String?
    @State private var packLoadTask: Task<Void, Never>?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        Group {
            if isLoadingPacks && packs.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, packs.isEmpty {
                ContentUnavailableView(
                    "Stickers unavailable",
                    systemImage: "face.smiling",
                    description: Text(errorMessage)
                )
            } else if packs.isEmpty {
                ContentUnavailableView(
                    "No stickers yet",
                    systemImage: "face.smiling",
                    description: Text("Published packs will show up here.")
                )
            } else {
                content
            }
        }
        .task { await loadPacks() }
        .onChange(of: selectedPackID) { _, newID in
            guard let newID else { return }
            packLoadTask?.cancel()
            packLoadTask = Task { await loadPack(id: newID) }
        }
        .onDisappear { packLoadTask?.cancel() }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(packs) { pack in
                        Button {
                            selectedPackID = pack.id
                        } label: {
                            Text(pack.title)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    selectedPackID == pack.id
                                        ? Color.primary.opacity(0.12)
                                        : Color.clear,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            Divider()

            if isLoadingDetail && detail == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(detail.stickers) { sticker in
                            Button {
                                onSelect(sticker)
                            } label: {
                                LazyImage(url: sticker.thumbURL) { state in
                                    if let image = state.image {
                                        image
                                            .resizable()
                                            .scaledToFit()
                                    } else {
                                        Color.secondary.opacity(0.08)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fit)
                                .padding(6)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(sticker.emojiHint ?? "Sticker")
                        }
                    }
                    .padding(16)
                }
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func loadPacks() async {
        guard !isLoadingPacks else { return }
        isLoadingPacks = true
        errorMessage = nil
        defer { isLoadingPacks = false }
        do {
            let loaded = try await stickersUseCase.fetchPacks()
            packs = loaded
            if selectedPackID == nil {
                selectedPackID = loaded.first?.id
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadPack(id: String) async {
        isLoadingDetail = true
        errorMessage = nil
        defer { isLoadingDetail = false }
        do {
            let loaded = try await stickersUseCase.fetchPack(id: id)
            if Task.isCancelled { return }
            detail = loaded
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            detail = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
