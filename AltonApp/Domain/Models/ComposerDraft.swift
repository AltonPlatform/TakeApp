import Foundation
import SwiftData

@Model
final class ComposerDraft {
    @Attribute(.unique) var id: UUID
    var content: String
    @Relationship(deleteRule: .cascade, inverse: \ComposerDraftAttachment.draft)
    var attachments: [ComposerDraftAttachment]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        content: String = "",
        attachments: [ComposerDraftAttachment] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.content = content
        self.attachments = attachments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class ComposerDraftAttachment {
    @Attribute(.unique) var id: UUID
    var draft: ComposerDraft?
    @Attribute(.externalStorage) var data: Data
    var contentType: String
    var filename: String
    var order: Int

    init(
        id: UUID = UUID(),
        data: Data,
        contentType: String,
        filename: String,
        order: Int
    ) {
        self.id = id
        self.data = data
        self.contentType = contentType
        self.filename = filename
        self.order = order
    }
}

/// Lightweight list row for UI (no SwiftData model references).
struct ComposerDraftSummary: Identifiable, Sendable, Hashable {
    let id: UUID
    let contentPreview: String
    let attachmentCount: Int
    let updatedAt: Date
}

/// Payload used to restore a draft into the composer.
struct ComposerDraftPayload: Sendable {
    let id: UUID
    let content: String
    let attachments: [ComposerDraftAttachmentPayload]
}

struct ComposerDraftAttachmentPayload: Sendable {
    let data: Data
    let contentType: String
    let filename: String
}

/// Pre-rename SwiftData entity. Kept in the schema so existing stores are not
/// truncated; `DraftStore` copies rows into `ShotDraft` then deletes these.
@Model
final class VideoDraft {
    @Attribute(.unique) var id: UUID
    var content: String
    var videoPath: String
    var thumbnailPath: String?
    var aiGeneratedLabel: Bool
    var lat: Double?
    var lon: Double?
    var locationName: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        content: String = "",
        videoPath: String,
        thumbnailPath: String? = nil,
        aiGeneratedLabel: Bool = false,
        lat: Double? = nil,
        lon: Double? = nil,
        locationName: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.content = content
        self.videoPath = videoPath
        self.thumbnailPath = thumbnailPath
        self.aiGeneratedLabel = aiGeneratedLabel
        self.lat = lat
        self.lon = lon
        self.locationName = locationName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class ShotDraft {
    @Attribute(.unique) var id: UUID
    var content: String
    var videoPath: String
    var thumbnailPath: String?
    var aiGeneratedLabel: Bool
    var lat: Double?
    var lon: Double?
    var locationName: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        content: String = "",
        videoPath: String,
        thumbnailPath: String? = nil,
        aiGeneratedLabel: Bool = false,
        lat: Double? = nil,
        lon: Double? = nil,
        locationName: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.content = content
        self.videoPath = videoPath
        self.thumbnailPath = thumbnailPath
        self.aiGeneratedLabel = aiGeneratedLabel
        self.lat = lat
        self.lon = lon
        self.locationName = locationName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ShotDraftSummary: Identifiable, Sendable, Hashable {
    let id: UUID
    let contentPreview: String
    let videoURL: URL
    let thumbnailURL: URL?
    let aiGeneratedLabel: Bool
    let updatedAt: Date
}

/// Payload used to restore a video draft into the publication flow.
struct ShotDraftPayload: Sendable {
    let id: UUID
    let content: String
    let videoURL: URL
    let thumbnailURL: URL?
    let aiGeneratedLabel: Bool
    let lat: Double?
    let lon: Double?
    let locationName: String?
}

