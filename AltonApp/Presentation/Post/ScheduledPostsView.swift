import SwiftUI

struct ScheduledPostsView: View {
    let postUseCase: PostUseCase

    @State private var posts: [Post] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && posts.isEmpty {
                ProgressView("Loading scheduled...")
            } else if let errorMessage, posts.isEmpty {
                ContentUnavailableView(
                    "Unable to load scheduled posts",
                    systemImage: "calendar",
                    description: Text(errorMessage)
                )
            } else if posts.isEmpty {
                ContentUnavailableView("No scheduled posts", systemImage: "calendar")
            } else {
                List(posts) { post in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(post.content?.isEmpty == false ? (post.content ?? "") : "Scheduled post")
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
                .listStyle(.plain)
            }
        }
        .navigationTitle("Scheduled")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await postUseCase.fetchScheduled()
            posts = page.posts
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
