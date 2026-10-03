import SwiftUI
import UIKit

struct DraftsView: View {
    let postUseCase: PostUseCase
    let draftStore: DraftStore
    var onOpenDraft: ((UUID) -> Void)?
    var onOpenShotDraft: ((UUID) -> Void)?

    @State private var localDrafts: [ComposerDraftSummary] = []
    @State private var videoDrafts: [ShotDraftSummary] = []
    @State private var posts: [Post] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var isEmpty: Bool {
        localDrafts.isEmpty && videoDrafts.isEmpty && posts.isEmpty && errorMessage == nil
    }

    var body: some View {
        Group {
            if isLoading && isEmpty {
                ProgressView("Loading drafts...")
            } else if let errorMessage, isEmpty {
                ContentUnavailableView(
                    "Unable to load drafts",
                    systemImage: "doc.text",
                    description: Text(errorMessage)
                )
            } else if isEmpty {
                ContentUnavailableView("No drafts", systemImage: "doc.text")
            } else {
                List {
                    if !videoDrafts.isEmpty {
                        Section("Відео на цьому пристрої") {
                            ForEach(videoDrafts) { draft in
                                Button {
                                    onOpenShotDraft?(draft.id)
                                } label: {
                                    videoDraftRow(draft)
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete(perform: deleteShotDrafts)
                        }
                    }

                    if !localDrafts.isEmpty {
                        Section("Drafts on this device") {
                            ForEach(localDrafts) { draft in
                                Button {
                                    onOpenDraft?(draft.id)
                                } label: {
                                    localDraftRow(draft)
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete(perform: deleteLocalDrafts)
                        }
                    }

                    if !posts.isEmpty || errorMessage != nil {
                        Section("On server") {
                            if let errorMessage, posts.isEmpty {
                                Text(errorMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(posts) { post in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(post.content?.isEmpty == false ? (post.content ?? "") : "Untitled draft")
                                        .font(.body)
                                        .lineLimit(3)
                                    if let createdAt = post.createdAt {
                                        Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Drafts")
        .task { await load() }
        .refreshable { await load() }
    }

    private func videoDraftRow(_ draft: ShotDraftSummary) -> some View {
        HStack(spacing: 12) {
            Group {
                if let thumb = draft.thumbnailURL,
                   let image = UIImage(contentsOfFile: thumb.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.gray.opacity(0.3)
                        .overlay {
                            Image(systemName: "video")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 48, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(draft.contentPreview)
                    .font(.body)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(relativeTime(draft.updatedAt))
                    if draft.aiGeneratedLabel {
                        Text("· ШІ")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func localDraftRow(_ draft: ComposerDraftSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(draft.contentPreview)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            HStack(spacing: 8) {
                Text(relativeTime(draft.updatedAt))
                if draft.attachmentCount > 0 {
                    Text("·")
                    Label("\(draft.attachmentCount)", systemImage: "photo")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func deleteLocalDrafts(at offsets: IndexSet) {
        for index in offsets {
            let id = localDrafts[index].id
            try? draftStore.delete(id: id)
        }
        localDrafts.remove(atOffsets: offsets)
    }

    private func deleteShotDrafts(at offsets: IndexSet) {
        for index in offsets {
            let id = videoDrafts[index].id
            try? draftStore.deleteShotDraft(id: id)
        }
        videoDrafts.remove(atOffsets: offsets)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        localDrafts = (try? draftStore.fetchAll()) ?? []
        videoDrafts = (try? draftStore.fetchShotDrafts()) ?? []

        do {
            let page = try await postUseCase.fetchDrafts()
            posts = page.posts
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
