import SwiftUI

/// Content preferences: sensitive toggle + interest weights by subcategory.
struct InterestsView: View {
    let userUseCase: UserUseCase
    let onUpdated: ([Interest]) -> Void

    @State private var weights: [String: Double] = [:]
    @State private var expanded: Set<String> = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        List {
            Section {
                ForEach(ContentCategory.all) { category in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expanded.contains(category.id) },
                            set: { open in
                                if open { expanded.insert(category.id) }
                                else { expanded.remove(category.id) }
                            }
                        )
                    ) {
                        ForEach(category.subcategories, id: \.self) { sub in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(category.subcategoryDisplayName(sub))
                                    Spacer()
                                    Text(String(format: "%.0f%%", (weights[key(category.id, sub)] ?? 0.5) * 100))
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                Slider(
                                    value: Binding(
                                        get: { weights[key(category.id, sub)] ?? 0.5 },
                                        set: { newValue in
                                            weights[key(category.id, sub)] = newValue
                                            scheduleSave()
                                        }
                                    ),
                                    in: 0...1,
                                    step: 0.05
                                )
                            }
                            .padding(.vertical, 4)
                        }
                    } label: {
                        Text(category.displayName)
                    }
                }
            } footer: {
                Text("Higher weight means more of this content in your feed.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Interests")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .task { await load() }
        .onDisappear { saveTask?.cancel() }
    }

    private func key(_ category: String, _ subcategory: String) -> String {
        "\(category)/\(subcategory)"
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let interests = try await userUseCase.loadInterests()
            var map: [String: Double] = [:]
            for interest in interests {
                map[key(interest.category, interest.subcategory)] = interest.weight
            }
            weights = map
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await save()
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let interests = weights.compactMap { entry -> Interest? in
            let parts = entry.key.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            // Skip default midpoint unless user touched it — only persist non-default or existing.
            return Interest(category: parts[0], subcategory: parts[1], weight: entry.value)
        }
        .filter { abs($0.weight - 0.5) > 0.001 || $0.weight > 0.5 }
        do {
            try await userUseCase.saveInterests(interests)
            onUpdated(interests)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
