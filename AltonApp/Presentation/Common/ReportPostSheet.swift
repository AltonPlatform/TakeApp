import SwiftUI

/// Server-aligned report taxonomy (Llama Guard S-codes + soft buckets).
enum ReportReason: String, CaseIterable, Identifiable, Sendable {
    case s1 = "S1"
    case s9 = "S9"
    case s4 = "S4"
    case s3 = "S3"
    case s2 = "S2"
    case s7 = "S7"
    case s11 = "S11"
    case s10 = "S10"
    case spam
    case harassment
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .s1: return "Violent Crimes"
        case .s9: return "Indiscriminate Weapons"
        case .s4: return "Child Sexual Exploitation"
        case .s3: return "Sex-Related Crimes"
        case .s2: return "Non-Violent Crimes"
        case .s7: return "Privacy"
        case .s11: return "Suicide & Self-Harm"
        case .s10: return "Hate"
        case .spam: return "Spam"
        case .harassment: return "Harassment"
        case .other: return "Other"
        }
    }

    static func displayTitle(for code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        if let known = ReportReason(rawValue: code) {
            return known.title
        }
        return code
    }

    static var defaultItems: [ReportReasonItem] {
        allCases.map { ReportReasonItem(code: $0.rawValue, title: $0.title, description: nil) }
    }
}

enum ReportContentKind: Equatable {
    case post(id: String)
    case comment(id: String)

    var navigationTitle: String {
        switch self {
        case .post: return "Report post"
        case .comment: return "Report comment"
        }
    }
}

struct ReportContentSheet: View {
    let kind: ReportContentKind
    let userUseCase: UserUseCase
    var onSubmitted: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var reasons: [ReportReasonItem] = ReportReason.defaultItems
    @State private var selectedCode: String = ReportReason.spam.rawValue
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Reason") {
                    Picker("Reason", selection: $selectedCode) {
                        ForEach(reasons) { item in
                            Text(item.title).tag(item.code)
                        }
                    }
                    .pickerStyle(.inline)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(kind.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting || selectedCode.isEmpty)
                }
            }
            .task { await loadReasons() }
        }
    }

    private func loadReasons() async {
        do {
            let fetched = try await userUseCase.fetchReportReasons()
            guard !fetched.isEmpty else { return }
            reasons = fetched
            if !fetched.contains(where: { $0.code == selectedCode }), let first = fetched.first {
                selectedCode = first.code
            }
        } catch {
            // Keep hardcoded taxonomy when the endpoint is unavailable.
        }
    }

    private func submit() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            switch kind {
            case .post(let id):
                try await userUseCase.reportPost(postID: id, reason: selectedCode)
            case .comment(let id):
                try await userUseCase.reportComment(commentID: id, reason: selectedCode)
            }
            onSubmitted?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ReportPostSheet: View {
    let postID: String
    let userUseCase: UserUseCase
    var onSubmitted: (() -> Void)? = nil

    var body: some View {
        ReportContentSheet(
            kind: .post(id: postID),
            userUseCase: userUseCase,
            onSubmitted: onSubmitted
        )
    }
}

struct ReportCommentSheet: View {
    let commentID: String
    let userUseCase: UserUseCase
    var onSubmitted: (() -> Void)? = nil

    var body: some View {
        ReportContentSheet(
            kind: .comment(id: commentID),
            userUseCase: userUseCase,
            onSubmitted: onSubmitted
        )
    }
}
