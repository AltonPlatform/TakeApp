import SwiftUI

struct HashtagInsertSheet: View {
    @Binding var caption: String
    @Binding var query: String
    @Environment(\.dismiss) private var dismiss

    private let suggestions = ["alton", "reels", "video", "fyp", "creator"]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Search hashtag", text: $query)
                }
                Section("Popular") {
                    ForEach(filtered, id: \.self) { tag in
                        Button {
                            let token = "#\(tag)"
                            if caption.isEmpty {
                                caption = token
                            } else if !caption.contains(token) {
                                caption += " \(token)"
                            }
                            dismiss()
                        } label: {
                            Text("#\(tag)")
                        }
                    }
                }
            }
            .navigationTitle("Hashtags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .keyboardDoneButton()
        }
        .presentationDetents([.medium])
    }

    private var filtered: [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return suggestions }
        return suggestions.filter { $0.contains(q) }
    }
}
