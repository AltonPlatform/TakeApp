import SwiftUI
import PhotosUI
import UIKit

@Observable
@MainActor
final class NewGroupViewModel {
    var query = ""
    var following: [FollowUser] = []
    var selectedIDs: Set<String> = []
    var title = ""
    var avatarJPEG: Data?
    var avatarPreview: UIImage?
    var isLoading = false
    var isCreating = false
    var errorMessage: String?
    var loadError: String?
    var createdConversation: DMConversation?

    private let currentUserID: String
    private let userUseCase: UserUseCase
    private let directUseCase: DirectUseCase

    init(currentUserID: String, userUseCase: UserUseCase, directUseCase: DirectUseCase) {
        self.currentUserID = currentUserID
        self.userUseCase = userUseCase
        self.directUseCase = directUseCase
    }

    var filteredFollowing: [FollowUser] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return following }
        return following.filter {
            $0.username.lowercased().contains(trimmed)
                || $0.displayName.lowercased().contains(trimmed)
        }
    }

    var canCreate: Bool {
        selectedIDs.count >= 1
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isCreating
    }

    func loadFollowing() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await userUseCase.listFollowing(userID: currentUserID, cursor: nil, limit: 50)
            following = page.users
        } catch {
            loadError = error.localizedDescription
        }
    }

    func toggle(_ userID: String) {
        if selectedIDs.contains(userID) {
            selectedIDs.remove(userID)
        } else if selectedIDs.count < 31 {
            selectedIDs.insert(userID)
        }
    }

    func stageAvatar(_ data: Data) async {
        let image = await Task.detached(priority: .userInitiated) {
            UIImage(data: data)
        }.value
        guard let image else { return }
        let compressed = await Task.detached(priority: .userInitiated) {
            DirectUseCase.compressImageForDM(image)
        }.value
        avatarPreview = image
        avatarJPEG = compressed?.data
    }

    func create() async {
        guard canCreate else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            var conversation = try await directUseCase.createGroup(
                memberIDs: Array(selectedIDs),
                title: title.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if let jpeg = avatarJPEG {
                do {
                    let uploaded = try await directUseCase.uploadGroupAvatar(
                        conversationID: conversation.id,
                        data: jpeg
                    )
                    conversation = try await directUseCase.updateGroupInfo(
                        conversationID: conversation.id,
                        title: nil,
                        avatarKey: uploaded
                    )
                } catch {
                    createdConversation = conversation
                    return
                }
            }
            createdConversation = conversation
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct NewGroupView: View {
    @State var viewModel: NewGroupViewModel
    @State private var avatarItem: PhotosPickerItem?
    @Environment(\.dismiss) private var dismiss
    var onCreated: (DMConversation) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $avatarItem, matching: .images) {
                        HStack(spacing: 12) {
                            groupAvatar
                            Text(viewModel.avatarPreview == nil ? "Add photo" : "Change photo")
                        }
                    }
                }
                Section("Title") {
                    TextField("Group name", text: $viewModel.title)
                }
                Section("Members (\(viewModel.selectedIDs.count))") {
                    TextField("Search following", text: $viewModel.query)
                    ForEach(viewModel.filteredFollowing) { user in
                        Button {
                            viewModel.toggle(user.id)
                        } label: {
                            HStack(spacing: 12) {
                                UserAvatarView(
                                    user: User(
                                        id: user.id,
                                        username: user.username,
                                        displayName: user.displayName,
                                        bio: nil,
                                        avatarURL: user.avatarURL,
                                        suiWallet: nil,
                                        createdAt: nil
                                    ),
                                    size: 36
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.displayName.isEmpty ? user.username : user.displayName)
                                        .foregroundStyle(.primary)
                                    Text("@\(user.username)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: viewModel.selectedIDs.contains(user.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(viewModel.selectedIDs.contains(user.id) ? Color.accentColor : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("New group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await viewModel.create() }
                    }
                    .disabled(!viewModel.canCreate)
                }
            }
            .task { await viewModel.loadFollowing() }
            .onChange(of: avatarItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await viewModel.stageAvatar(data)
                    }
                }
            }
            .alert("Couldn't load following", isPresented: Binding(
                get: { viewModel.loadError != nil },
                set: { if !$0 { viewModel.loadError = nil } }
            )) {
                Button("OK") { viewModel.loadError = nil }
            } message: {
                Text(viewModel.loadError ?? "")
            }
            .alert("Couldn't create group", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onChange(of: viewModel.createdConversation?.id) { _, _ in
                guard let conversation = viewModel.createdConversation else { return }
                onCreated(conversation)
                dismiss()
            }
        }
    }

    private var groupAvatar: some View {
        Group {
            if let preview = viewModel.avatarPreview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "camera.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.15))
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
    }
}

struct GroupMembersSheet: View {
    var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var rightsTarget: DMConversationMember?
    @State private var actionError: String?

    var body: some View {
        NavigationStack {
            List(viewModel.conversation.members) { member in
                HStack(spacing: 12) {
                    UserAvatarView(
                        user: User(
                            id: member.userID,
                            username: member.username,
                            displayName: member.displayName,
                            bio: nil,
                            avatarURL: member.avatarURL,
                            suiWallet: nil,
                            createdAt: nil
                        ),
                        size: 40
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.displayName.isEmpty ? member.username : member.displayName)
                        Text(member.role)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if viewModel.canAssignGroupAdmins, !member.isOwner, member.userID != viewModel.currentUserID {
                        Button("Rights") { rightsTarget = member }
                            .font(.caption)
                    }
                    if viewModel.canBanGroupMembers, !member.isOwner, member.userID != viewModel.currentUserID {
                        Button("Remove", role: .destructive) {
                            Task { actionError = await viewModel.removeGroupMember(member.userID) }
                        }
                        .font(.caption)
                    }
                }
            }
            .navigationTitle("Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $rightsTarget) { member in
                GroupAdminRightsSheet(viewModel: viewModel, member: member)
            }
            .alert("Couldn't update members", isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("OK") { actionError = nil }
            } message: {
                Text(actionError ?? "")
            }
        }
    }
}

private struct GroupAdminRightsSheet: View {
    var viewModel: ChatViewModel
    let member: DMConversationMember
    @Environment(\.dismiss) private var dismiss
    @State private var isAdmin: Bool
    @State private var selected: Set<String>
    @State private var saveError: String?

    private static let catalog: [(key: String, title: String)] = [
        ("change_info", "Change info"),
        ("delete_messages", "Delete messages"),
        ("ban_members", "Ban members"),
        ("invite_by_link", "Invite by link"),
        ("pin_messages", "Pin messages"),
        ("assign_admins", "Appoint admins"),
    ]

    init(viewModel: ChatViewModel, member: DMConversationMember) {
        self.viewModel = viewModel
        self.member = member
        _isAdmin = State(initialValue: member.isAdmin)
        _selected = State(initialValue: member.rights)
        _saveError = State(initialValue: nil)
    }

    private var grantable: Set<String> {
        guard let me = viewModel.currentMember else { return [] }
        if me.isOwner { return Set(Self.catalog.map(\.key)) }
        return me.rights
    }

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Admin", isOn: $isAdmin)
                if isAdmin {
                    Section("Rights") {
                        ForEach(Self.catalog, id: \.key) { item in
                            Toggle(item.title, isOn: binding(for: item.key))
                                .disabled(!grantable.contains(item.key))
                        }
                    }
                }
            }
            .navigationTitle(member.displayName.isEmpty ? member.username : member.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let rights = isAdmin ? Array(selected.intersection(grantable)) : []
                        Task {
                            if let message = await viewModel.setGroupAdmin(
                                memberID: member.userID,
                                isAdmin: isAdmin,
                                rights: rights
                            ) {
                                saveError = message
                            } else {
                                dismiss()
                            }
                        }
                    }
                }
            }
            .alert("Couldn't update rights", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func binding(for key: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(key) },
            set: { on in
                if on { selected.insert(key) } else { selected.remove(key) }
            }
        )
    }
}

