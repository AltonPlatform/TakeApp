import SwiftUI

struct ChatPollComposer: View {
    var onSend: (DMPoll) -> Void

    @State private var question = ""
    @State private var options: [String] = ["", ""]
    @State private var anonymous = true
    @State private var multiple = false
    @State private var quiz = false
    @State private var othersCanAdd = false
    @State private var correctIndex: Int?
    @State private var explanation = ""

    private var filledOptions: [String] {
        options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var canSend: Bool {
        let questionReady = !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard questionReady, filledOptions.count >= 2 else { return false }
        if quiz {
            guard let correctIndex, options.indices.contains(correctIndex) else { return false }
            return !options[correctIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    var body: some View {
        Form {
            Section {
                TextField("Question", text: $question, axis: .vertical)
                    .onChange(of: question) { _, newValue in
                        if newValue.count > 255 { question = String(newValue.prefix(255)) }
                    }
            }
            Section("Options") {
                ForEach(options.indices, id: \.self) { index in
                    HStack(spacing: 10) {
                        if quiz {
                            Button {
                                correctIndex = index
                            } label: {
                                Image(systemName: correctIndex == index ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(correctIndex == index ? Color.green : Color.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        TextField("Option", text: binding(for: index))
                        if options.count > 2 {
                            Button {
                                remove(index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .onMove(perform: move)
                if options.count < ChatPollState.maxOptions {
                    Button("Add Option", systemImage: "plus") {
                        options.append("")
                    }
                }
            }
            Section {
                Toggle("Anonymous Voting", isOn: $anonymous)
                Toggle("Multiple Answers", isOn: $multiple)
                    .disabled(quiz)
                Toggle("Quiz Mode", isOn: $quiz)
                Toggle("Allow Adding Options", isOn: $othersCanAdd)
                    .disabled(quiz)
            }
            if quiz {
                Section("Explanation") {
                    TextField("Shown after the answer", text: $explanation, axis: .vertical)
                        .onChange(of: explanation) { _, newValue in
                            if newValue.count > 200 { explanation = String(newValue.prefix(200)) }
                        }
                }
            }
            Section {
                ChatComposerSendButton(isEnabled: canSend, action: send)
            }
        }
        .environment(\.editMode, .constant(.active))
        .onChange(of: quiz) { _, isQuiz in
            if isQuiz {
                multiple = false
                othersCanAdd = false
            }
        }
        .onChange(of: options) { _, _ in
            guard let last = options.last,
                  !last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  options.count < ChatPollState.maxOptions else { return }
            options.append("")
        }
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { options.indices.contains(index) ? options[index] : "" },
            set: { newValue in
                guard options.indices.contains(index) else { return }
                options[index] = String(newValue.prefix(100))
            }
        )
    }

    private func remove(_ index: Int) {
        guard options.indices.contains(index), options.count > 2 else { return }
        options.remove(at: index)
        if let correctIndex {
            if correctIndex == index {
                self.correctIndex = nil
            } else if correctIndex > index {
                self.correctIndex = correctIndex - 1
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        let previousCorrect = correctIndex.flatMap { options.indices.contains($0) ? options[$0] : nil }
        options.move(fromOffsets: source, toOffset: destination)
        if let previousCorrect {
            correctIndex = options.firstIndex(of: previousCorrect)
        }
    }

    private func send() {
        var cleaned: [String] = []
        var correctID: Int?
        for (index, raw) in options.enumerated() {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            cleaned.append(text)
            if quiz, correctIndex == index {
                correctID = cleaned.count
            }
        }
        guard cleaned.count >= 2 else { return }
        if quiz, correctID == nil { return }
        let trimmedExplanation = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        let poll = DMPoll(
            question: String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(255)),
            options: cleaned.enumerated().map { DMPollOption(id: $0.offset + 1, text: $0.element) },
            nextID: cleaned.count + 1,
            anonymous: anonymous,
            multiple: quiz ? false : multiple,
            quiz: quiz,
            othersCanAdd: quiz ? false : othersCanAdd,
            closed: false,
            correctOptionID: correctID,
            explanation: trimmedExplanation.isEmpty ? nil : String(trimmedExplanation.prefix(200))
        )
        onSend(poll)
    }
}
