import SwiftUI

/// Modal prompting the user to set date of birth and gender. Dismissible; reappears until filled.
struct AgeGenderModal: View {
    let userUseCase: UserUseCase
    let onSaved: (UserProfile) -> Void
    let onSkip: () -> Void

    @State private var dateOfBirth: Date
    @State private var gender: Gender = .preferNotToSay
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let dateRange: ClosedRange<Date>

    init(
        userUseCase: UserUseCase,
        initialDateOfBirth: Date? = nil,
        initialGender: Gender? = nil,
        onSaved: @escaping (UserProfile) -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.userUseCase = userUseCase
        self.onSaved = onSaved
        self.onSkip = onSkip
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()
        let min = calendar.date(from: DateComponents(year: 1900, month: 1, day: 1)) ?? today
        dateRange = min...today
        let defaultDOB = calendar.date(byAdding: .year, value: -18, to: today) ?? today
        _dateOfBirth = State(initialValue: initialDateOfBirth ?? defaultDOB)
        if let initialGender {
            _gender = State(initialValue: initialGender)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Date of birth",
                        selection: $dateOfBirth,
                        in: dateRange,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.wheel)

                    Picker("Gender", selection: $gender) {
                        ForEach(Gender.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                } footer: {
                    Text("Used to personalize your experience and keep the feed age-appropriate. You must be 18+ to view age-restricted content.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("About you")
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
                    .disabled(isSaving)
                }
            }
        }
        .interactiveDismissDisabled(false)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let profile = try await userUseCase.updateProfile(
                dateOfBirth: dateOfBirth,
                gender: gender
            )
            onSaved(profile)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
