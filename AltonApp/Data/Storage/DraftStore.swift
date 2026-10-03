import Foundation
import SwiftData

@MainActor
final class DraftStore {
    static let maxDraftCount = 20
    static let maxAgeDays = 30

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(inMemory: Bool = false) throws {
        let schema = Schema([
            ComposerDraft.self,
            ComposerDraftAttachment.self,
            VideoDraft.self,
            ShotDraft.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        container = try ModelContainer(for: schema, configurations: [configuration])
        migrateLegacyVideoDraftsIfNeeded()
    }

    /// Creates an empty in-memory store for tests / fallback.
    static func makeInMemory() -> DraftStore {
        do {
            return try DraftStore(inMemory: true)
        } catch {
            fatalError("Failed to create in-memory DraftStore: \(error)")
        }
    }

    static func makePersistent() -> DraftStore {
        do {
            return try DraftStore(inMemory: false)
        } catch {
            // Fall back so composer still works if store fails to open.
            PipelineLogger.media.error("DraftStore open failed, using in-memory: \(String(describing: error), privacy: .public)")
            return makeInMemory()
        }
    }

    // MARK: - CRUD

    @discardableResult
    func upsert(
        id: UUID?,
        content: String,
        attachments: [ComposerDraftAttachmentPayload]
    ) throws -> UUID? {
        let trimmedEmpty = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if trimmedEmpty && attachments.isEmpty {
            if let id {
                try delete(id: id)
            }
            return nil
        }

        let now = Date()
        if let id, let existing = try fetchModel(id: id) {
            existing.content = content
            existing.updatedAt = now
            replaceAttachments(on: existing, with: attachments)
            try context.save()
            try enforceDraftLimit()
            return existing.id
        }

        let draft = ComposerDraft(
            id: id ?? UUID(),
            content: content,
            attachments: [],
            createdAt: now,
            updatedAt: now
        )
        replaceAttachments(on: draft, with: attachments)
        context.insert(draft)
        try context.save()
        try enforceDraftLimit()
        return draft.id
    }

    func load(id: UUID) throws -> ComposerDraftPayload? {
        guard let draft = try fetchModel(id: id) else { return nil }
        let sorted = draft.attachments.sorted { $0.order < $1.order }
        return ComposerDraftPayload(
            id: draft.id,
            content: draft.content,
            attachments: sorted.map {
                ComposerDraftAttachmentPayload(
                    data: $0.data,
                    contentType: $0.contentType,
                    filename: $0.filename
                )
            }
        )
    }

    func fetchAll() throws -> [ComposerDraftSummary] {
        let descriptor = FetchDescriptor<ComposerDraft>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { draft in
            let preview = draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return ComposerDraftSummary(
                id: draft.id,
                contentPreview: preview.isEmpty ? "Untitled draft" : preview,
                attachmentCount: draft.attachments.count,
                updatedAt: draft.updatedAt
            )
        }
    }

    func delete(id: UUID) throws {
        guard let draft = try fetchModel(id: id) else { return }
        context.delete(draft)
        try context.save()
    }

    func deleteOlderThan(_ date: Date) throws {
        let descriptor = FetchDescriptor<ComposerDraft>(
            predicate: #Predicate { $0.updatedAt < date }
        )
        let stale = try context.fetch(descriptor)
        for draft in stale {
            context.delete(draft)
        }
        if !stale.isEmpty {
            try context.save()
        }
    }

    func purgeStaleOnLaunch() {
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -Self.maxAgeDays,
            to: Date()
        ) ?? Date.distantPast
        try? deleteOlderThan(cutoff)
        try? enforceDraftLimit()
    }

    // MARK: - Private

    private func fetchModel(id: UUID) throws -> ComposerDraft? {
        let descriptor = FetchDescriptor<ComposerDraft>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    private func replaceAttachments(
        on draft: ComposerDraft,
        with payloads: [ComposerDraftAttachmentPayload]
    ) {
        for existing in draft.attachments {
            context.delete(existing)
        }
        draft.attachments = payloads.enumerated().map { index, payload in
            ComposerDraftAttachment(
                data: payload.data,
                contentType: payload.contentType,
                filename: payload.filename,
                order: index
            )
        }
    }

    private func enforceDraftLimit() throws {
        let all = try context.fetch(
            FetchDescriptor<ComposerDraft>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        )
        guard all.count > Self.maxDraftCount else { return }
        for draft in all.suffix(from: Self.maxDraftCount) {
            context.delete(draft)
        }
        try context.save()
    }

    /// Copies leftover `VideoDraft` rows into `ShotDraft` so the Thread→Take / Video→Shot
    /// rename does not drop local drafts or truncate persistent history.
    private func migrateLegacyVideoDraftsIfNeeded() {
        let legacy: [VideoDraft]
        do {
            legacy = try context.fetch(FetchDescriptor<VideoDraft>())
        } catch {
            PipelineLogger.media.error(
                "VideoDraft fetch failed during migration: \(String(describing: error), privacy: .public)"
            )
            return
        }
        guard !legacy.isEmpty else { return }

        for old in legacy {
            if (try? fetchShotModel(id: old.id)) == nil {
                context.insert(
                    ShotDraft(
                        id: old.id,
                        content: old.content,
                        videoPath: old.videoPath,
                        thumbnailPath: old.thumbnailPath,
                        aiGeneratedLabel: old.aiGeneratedLabel,
                        lat: old.lat,
                        lon: old.lon,
                        locationName: old.locationName,
                        createdAt: old.createdAt,
                        updatedAt: old.updatedAt
                    )
                )
            }
            context.delete(old)
        }
        do {
            try context.save()
            PipelineLogger.media.info("migrated \(legacy.count) VideoDraft rows to ShotDraft")
        } catch {
            PipelineLogger.media.error(
                "VideoDraft → ShotDraft save failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    // MARK: - Video drafts

    @discardableResult
    func upsertShotDraft(
        id: UUID?,
        content: String,
        videoURL: URL,
        thumbnailURL: URL?,
        aiGeneratedLabel: Bool,
        lat: Double?,
        lon: Double?,
        locationName: String?
    ) throws -> UUID {
        let now = Date()
        if let id, let existing = try fetchShotModel(id: id) {
            existing.content = content
            existing.videoPath = videoURL.path
            existing.thumbnailPath = thumbnailURL?.path
            existing.aiGeneratedLabel = aiGeneratedLabel
            existing.lat = lat
            existing.lon = lon
            existing.locationName = locationName
            existing.updatedAt = now
            try context.save()
            try enforceShotDraftLimit()
            return existing.id
        }

        let draft = ShotDraft(
            id: id ?? UUID(),
            content: content,
            videoPath: videoURL.path,
            thumbnailPath: thumbnailURL?.path,
            aiGeneratedLabel: aiGeneratedLabel,
            lat: lat,
            lon: lon,
            locationName: locationName,
            createdAt: now,
            updatedAt: now
        )
        context.insert(draft)
        try context.save()
        try enforceShotDraftLimit()
        return draft.id
    }

    func fetchShotDrafts() throws -> [ShotDraftSummary] {
        let descriptor = FetchDescriptor<ShotDraft>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { draft in
            let preview = draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return ShotDraftSummary(
                id: draft.id,
                contentPreview: preview.isEmpty ? "Відео-чернетка" : preview,
                videoURL: URL(fileURLWithPath: draft.videoPath),
                thumbnailURL: draft.thumbnailPath.map { URL(fileURLWithPath: $0) },
                aiGeneratedLabel: draft.aiGeneratedLabel,
                updatedAt: draft.updatedAt
            )
        }
    }

    func deleteShotDraft(id: UUID) throws {
        guard let draft = try fetchShotModel(id: id) else { return }
        try? FileManager.default.removeItem(atPath: draft.videoPath)
        if let thumb = draft.thumbnailPath {
            try? FileManager.default.removeItem(atPath: thumb)
        }
        context.delete(draft)
        try context.save()
    }

    /// Returns full video draft details for restoration into the camera/publication flow.
    func loadShotDraft(id: UUID) throws -> ShotDraftPayload? {
        guard let draft = try fetchShotModel(id: id) else { return nil }
        return ShotDraftPayload(
            id: draft.id,
            content: draft.content,
            videoURL: URL(fileURLWithPath: draft.videoPath),
            thumbnailURL: draft.thumbnailPath.map { URL(fileURLWithPath: $0) },
            aiGeneratedLabel: draft.aiGeneratedLabel,
            lat: draft.lat,
            lon: draft.lon,
            locationName: draft.locationName
        )
    }

    private func fetchShotModel(id: UUID) throws -> ShotDraft? {
        let descriptor = FetchDescriptor<ShotDraft>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    private func enforceShotDraftLimit() throws {
        let all = try context.fetch(
            FetchDescriptor<ShotDraft>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        )
        guard all.count > Self.maxDraftCount else { return }
        for draft in all.suffix(from: Self.maxDraftCount) {
            try? FileManager.default.removeItem(atPath: draft.videoPath)
            if let thumb = draft.thumbnailPath {
                try? FileManager.default.removeItem(atPath: thumb)
            }
            context.delete(draft)
        }
        try context.save()
    }
}

#if DEBUG
extension DraftStore {
    func insertLegacyVideoDraftForTesting(id: UUID, content: String, videoPath: String) {
        context.insert(
            VideoDraft(
                id: id,
                content: content,
                videoPath: videoPath
            )
        )
        try? context.save()
    }

    func migrateLegacyVideoDraftsForTesting() {
        migrateLegacyVideoDraftsIfNeeded()
    }

    func fetchLegacyVideoDraftsForTesting() throws -> [VideoDraft] {
        try context.fetch(FetchDescriptor<VideoDraft>())
    }
}
#endif
