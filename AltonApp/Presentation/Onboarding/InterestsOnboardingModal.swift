import SwiftUI

/// Onboarding: pick interesting categories (category-level weights). Dismissible until filled.
struct InterestsOnboardingModal: View {
    let userUseCase: UserUseCase
    let onSaved: ([Interest]) -> Void
    let onSkip: () -> Void

    @State private var selected: Set<String> = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(ContentCategory.all.filter { $0.id != "other" }) { category in
                        Button {
                            if selected.contains(category.id) {
                                selected.remove(category.id)
                            } else {
                                selected.insert(category.id)
                            }
                        } label: {
                            Text(category.displayName)
                                .font(.subheadline.weight(.medium))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .padding(.horizontal, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(selected.contains(category.id)
                                              ? Color.accentColor.opacity(0.18)
                                              : Color(.secondarySystemBackground))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(
                                            selected.contains(category.id)
                                                ? Color.accentColor
                                                : Color.clear,
                                            lineWidth: 1.5
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .padding(.horizontal)
                }
            }
            .navigationTitle("What interests you?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { onSkip() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || selected.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Pick a few topics. You can fine-tune subcategories later in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let interests = selected.map { Interest.categoryLevel(category: $0, weight: 1.0) }
        do {
            try await userUseCase.saveInterests(interests)
            onSaved(interests)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
