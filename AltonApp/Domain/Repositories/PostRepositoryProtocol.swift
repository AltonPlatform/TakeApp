import Foundation

struct ShotUploadContext: Equatable, Sendable {
    var caption: String?
    var lat: Double?
    var lon: Double?
    var geoSource: String?
    var aiGeneratedLabel: Bool?
}

struct AcceptedShotUpload: Equatable, Sendable {
    var postID: String
    var objectKey: String
}

protocol PostRepositoryProtocol: Sendable {
    func createTakePost(content: String?) async throws -> Post
    func createShotPost(
        content: String?,
        lat: Double?,
        lon: Double?,
        geoSource: String?,
        aiGeneratedLabel: Bool?
    ) async throws -> Post
    /// Post id of an interrupted shot upload for this local file, if the file is unchanged.
    func pendingShotPostID(fileURL: URL) -> String?
    /// Local files whose interrupted shot upload can continue.
    func pendingShotFileURLs() -> [URL]
    func shotUploadContext(fileURL: URL) -> ShotUploadContext?
    func rememberShotUploadContext(fileURL: URL, context: ShotUploadContext)
    /// Drops the server post link and keeps the local video for a new draft.
    func detachPendingShotUpload(fileURL: URL)
    /// Drops the interrupted upload and deletes its durable copy.
    func discardPendingShotUpload(fileURL: URL)
    func shotRequiresExplicitResume(fileURL: URL) -> Bool
    func allowAutomaticShotResume(fileURL: URL)
    func requireExplicitShotResume(fileURL: URL)
    /// Shots whose bytes are stored and whose `upload-complete` was accepted.
    /// The journal stays until the processed video is attached.
    func acceptedShotUploads() -> [AcceptedShotUpload]
    func removeShotJournal(postID: String)
    func resendShotUploadComplete(postID: String, objectKey: String) async throws
    func fetchPost(id: String) async throws -> Post
    func updatePost(id: String, content: String?, mediaKey: String?) async throws -> Post
    func schedulePost(id: String, publishAt: Date) async throws -> Post
    func fetchDrafts(cursor: String?, limit: Int) async throws -> (posts: [Post], nextCursor: String?)
    func fetchScheduled(cursor: String?, limit: Int) async throws -> (posts: [Post], nextCursor: String?)
    func publishPost(id: String) async throws
    func deletePost(id: String) async throws
    func uploadTakeAttachments(postID: String, attachments: [PostAttachment]) async throws -> Post
    func uploadShot(
        postID: String,
        fileURL: URL,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> Post
    func createPoll(postID: String, question: String, options: [String], expiresAt: Date?) async throws -> Poll
    func votePoll(pollID: String, optionIndex: Int) async throws -> Poll
    func fetchPoll(postID: String) async throws -> Poll
    func fetchLinkPreview(url: String) async throws -> LinkPreview?
}

extension PostRepositoryProtocol {
    func shotRequiresExplicitResume(fileURL: URL) -> Bool { false }
    func allowAutomaticShotResume(fileURL: URL) {}
    func requireExplicitShotResume(fileURL: URL) {}
    func acceptedShotUploads() -> [AcceptedShotUpload] { [] }
    func removeShotJournal(postID: String) {}
    func resendShotUploadComplete(postID: String, objectKey: String) async throws {}
}
