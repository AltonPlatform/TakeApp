import SwiftUI

struct RequestsView: View {
    @State var viewModel: InboxViewModel
    let container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.conversations) { conversation in
                    VStack(alignment: .leading, spacing: 8) {
                        InboxRow(conversation: conversation)
                        HStack {
                            Button("Accept") {
                                Task {
                                    _ = try? await container.directUseCase.accept(
                                        conversationID: conversation.id
                                    )
                                    await viewModel.refresh()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Decline", role: .destructive) {
                                Task {
                                    try? await container.directUseCase.decline(
                                        conversationID: conversation.id
                                    )
                                    await viewModel.refresh()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Message requests")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                viewModel.folder = "requests"
                viewModel.start()
                Task { await viewModel.refresh() }
            }
            .onDisappear { viewModel.stop() }
        }
    }
}
