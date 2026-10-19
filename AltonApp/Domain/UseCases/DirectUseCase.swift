import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

final class DirectUseCase: Sendable {
    private let repository: DirectRepositoryProtocol

    init(repository: DirectRepositoryProtocol) {
        self.repository = repository
    }

    func inbox(folder: String, cursor: String?) async throws -> DMInboxPage {
        try await repository.fetchInbox(folder: folder, cursor: cursor, limit: 30)
    }

    func openDirect(with recipientID: String) async throws -> DMConversation {
        try await repository.getOrCreateDirect(recipientID: recipientID)
    }

    func history(conversationID: String, beforeSeq: Int64?) async throws -> DMHistoryPage {
        try await repository.fetchHistory(
            conversationID: conversationID,
            beforeSeq: beforeSeq,
            afterSeq: nil,
            limit: 50
        )
    }

    func syncAfter(conversationID: String, afterSeq: Int64) async throws -> DMHistoryPage {
        try await repository.fetchHistory(
            conversationID: conversationID,
            beforeSeq: nil,
            afterSeq: afterSeq,
            limit: 100
        )
    }

    /// Fetches post cards for a single message seq (cursor: after `seq - 1`, limit 1).
    func postCards(conversationID: String, seq: Int64) async throws -> [DMPostCard] {
        let page = try await repository.fetchHistory(
            conversationID: conversationID,
            beforeSeq: nil,
            afterSeq: max(0, seq - 1),
            limit: 1
        )
        return page.postCards
    }

    func sendText(
        conversationID: String,
        text: String,
        clientMsgID: String = UUID().uuidString,
        replyToSeq: Int64? = nil
    ) async throws -> DMMessage {
        try await repository.sendMessage(
            conversationID: conversationID,
            clientMsgID: clientMsgID,
            kind: "text",
            body: text,
            postID: nil,
            mediaKey: nil,
            mediaWidth: nil,
            mediaHeight: nil,
            replyToSeq: replyToSeq,
            klipyGifID: nil,
            gifSourceURL: nil,
            gifContentType: nil,
            payload: nil
        )
    }

    func sendImage(
        conversationID: String,
        imageData: Data,
        contentType: String,
        width: Int?,
        height: Int?,
        clientMsgID: String = UUID().uuidString,
        replyToSeq: Int64? = nil,
        caption: String? = nil
    ) async throws -> DMMessage {
        guard let repo = repository as? DirectRepository else {
            throw APIError.validation("Image upload unavailable")
        }
        let uploaded = try await repo.uploadImageData(
            conversationID: conversationID,
            data: imageData,
            contentType: contentType
        )
        let trimmedCaption = caption?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (trimmedCaption?.isEmpty == false) ? trimmedCaption : nil
        return try await repository.sendMessage(
            conversationID: conversationID,
            clientMsgID: clientMsgID,
            kind: "image",
            body: body,
            postID: nil,
            mediaKey: uploaded.mediaKey,
            mediaWidth: width ?? uploaded.width,
            mediaHeight: height ?? uploaded.height,
            replyToSeq: replyToSeq,
            klipyGifID: nil,
            gifSourceURL: nil,
            gifContentType: nil,
            payload: nil
        )
    }

    func sendGIF(
        conversationID: String,
        gif: KlipyGIF,
        clientMsgID: String = UUID().uuidString,
        replyToSeq: Int64? = nil
    ) async throws -> DMMessage {
        try await repository.sendMessage(
            conversationID: conversationID,
            clientMsgID: clientMsgID,
            kind: "gif",
            body: nil,
            postID: nil,
            mediaKey: nil,
            mediaWidth: gif.width,
            mediaHeight: gif.height,
            replyToSeq: replyToSeq,
            klipyGifID: gif.id,
            gifSourceURL: gif.downloadURL.absoluteString,
            gifContentType: gif.contentType,
            payload: nil
        )
    }

    func sendSticker(
        conversationID: String,
        stickerID: String,
        clientMsgID: String = UUID().uuidString,
        replyToSeq: Int64? = nil
    ) async throws -> DMMessage {
        try await repository.sendMessage(
            conversationID: conversationID,
            clientMsgID: clientMsgID,
            kind: "sticker",
            body: nil,
            postID: nil,
            mediaKey: nil,
            mediaWidth: nil,
            mediaHeight: nil,
            replyToSeq: replyToSeq,
            klipyGifID: nil,
            gifSourceURL: nil,
            gifContentType: nil,
            payload: .sticker(id: stickerID)
        )
    }

    func sendLocation(
        conversationID: String,
        location: DMLocation,
        clientMsgID: String = UUID().uuidString,
        replyToSeq: Int64? = nil
    ) async throws -> DMMessage {
        try await repository.sendMessage(
            conversationID: conversationID,
            clientMsgID: clientMsgID,
            kind: "location",
            body: nil,
            postID: nil,
            mediaKey: nil,
            mediaWidth: nil,
            mediaHeight: nil,
            replyToSeq: replyToSeq,
            klipyGifID: nil,
            gifSourceURL: nil,
            gifContentType: nil,
            payload: .location(location)
        )
    }

    func sendChecklist(
        conversationID: String,
        checklist: DMChecklist,
        clientMsgID: String = UUID().uuidString,
        replyToSeq: Int64? = nil
    ) async throws -> DMMessage {
        try await repository.sendMessage(
            conversationID: conversationID,
            clientMsgID: clientMsgID,
            kind: "checklist",
            body: nil,
            postID: nil,
            mediaKey: nil,
            mediaWidth: nil,
            mediaHeight: nil,
            replyToSeq: replyToSeq,
            klipyGifID: nil,
            gifSourceURL: nil,
            gifContentType: nil,
            payload: .checklist(checklist)
        )
    }

    func toggleChecklistItem(messageID: String, itemID: Int, done: Bool) async throws -> [DMChecklistMark] {
        try await repository.setChecklistItem(messageID: messageID, itemID: itemID, done: done)
    }

    func appendChecklistItems(messageID: String, items: [String]) async throws -> DMMessage {
        try await repository.appendChecklistItems(messageID: messageID, items: items)
    }

    func sendPoll(
        conversationID: String,
        poll: DMPoll,
        clientMsgID: String = UUID().uuidString,
        replyToSeq: Int64? = nil
    ) async throws -> DMMessage {
        try await repository.sendMessage(
            conversationID: conversationID,
            clientMsgID: clientMsgID,
            kind: "poll",
            body: nil,
            postID: nil,
            mediaKey: nil,
            mediaWidth: nil,
            mediaHeight: nil,
            replyToSeq: replyToSeq,
            klipyGifID: nil,
            gifSourceURL: nil,
            gifContentType: nil,
            payload: .poll(poll)
        )
    }

    func votePoll(messageID: String, optionIDs: [Int]) async throws -> DMMessage {
        try await repository.votePoll(messageID: messageID, optionIDs: optionIDs)
    }

    func closePoll(messageID: String) async throws -> DMMessage {
        try await repository.closePoll(messageID: messageID)
    }

    func appendPollOptions(messageID: String, options: [String]) async throws -> DMMessage {
        try await repository.appendPollOptions(messageID: messageID, options: options)
    }

    func forward(messageID: String, conversationIDs: [String]) async throws {
        try await repository.forwardMessage(messageID: messageID, conversationIDs: conversationIDs)
    }

    func createGroup(memberIDs: [String], title: String) async throws -> DMConversation {
        try await repository.createGroup(memberIDs: memberIDs, title: title)
    }

    func updateGroupInfo(
        conversationID: String,
        title: String?,
        avatarKey: String?
    ) async throws -> DMConversation {
        try await repository.updateGroupInfo(
            conversationID: conversationID,
            title: title,
            avatarKey: avatarKey
        )
    }

    func addGroupMembers(conversationID: String, memberIDs: [String]) async throws -> DMConversation {
        try await repository.addGroupMembers(conversationID: conversationID, memberIDs: memberIDs)
    }

    func removeGroupMember(conversationID: String, userID: String) async throws -> DMConversation? {
        try await repository.removeGroupMember(conversationID: conversationID, userID: userID)
    }

    func setGroupAdmin(
        conversationID: String,
        memberID: String,
        isAdmin: Bool,
        rights: [String]
    ) async throws -> DMConversation {
        try await repository.setGroupAdmin(
            conversationID: conversationID,
            memberID: memberID,
            isAdmin: isAdmin,
            rights: rights
        )
    }

    func banGroupMember(conversationID: String, memberID: String) async throws -> DMConversation {
        try await repository.banGroupMember(conversationID: conversationID, memberID: memberID)
    }

    func unbanGroupMember(conversationID: String, userID: String) async throws -> DMConversation {
        try await repository.unbanGroupMember(conversationID: conversationID, userID: userID)
    }

    func groupMembers(conversationID: String) async throws -> [DMConversationMember] {
        try await repository.groupMembers(conversationID: conversationID)
    }

    func uploadGroupAvatar(conversationID: String, data: Data) async throws -> String {
        try await repository.uploadGroupAvatar(conversationID: conversationID, data: data)
    }

    func editMessage(messageID: String, body: String) async throws -> DMMessage {
        try await repository.editMessage(messageID: messageID, body: body)
    }

    func deleteMessage(messageID: String) async throws {
        try await repository.deleteMessage(messageID: messageID)
    }

    func setReaction(messageID: String, emoji: String) async throws -> [DMMessageReaction] {
        try await repository.setReaction(messageID: messageID, emoji: emoji)
    }

    func clearReaction(messageID: String) async throws -> [DMMessageReaction] {
        try await repository.clearReaction(messageID: messageID)
    }

    func markRead(conversationID: String, seq: Int64) async throws {
        try await repository.markRead(conversationID: conversationID, seq: seq)
    }

    func accept(conversationID: String) async throws -> DMConversation {
        try await repository.acceptRequest(conversationID: conversationID)
    }

    func decline(conversationID: String) async throws {
        try await repository.declineRequest(conversationID: conversationID)
    }

    func sharePost(postID: String, recipientIDs: [String], text: String?) async throws {
        try await repository.sharePost(postID: postID, recipientIDs: recipientIDs, text: text)
    }

    /// Aspect must be within 1:3…3:1; short edge ≥ 64 after crop. Long edge ≤ 2048.
    /// Returns nil when the image is too small to send.
    ///
    /// Camera stills often arrive with non-`.up` `imageOrientation`. Cropping the raw
    /// `cgImage` against the oriented `size` stretches the result — normalize first.
    ///
    /// CPU only. `UIGraphicsImageRenderer` and `UIImage.jpegData` run through the GPU
    /// and stall the chat for the whole encode.
    static func compressImageForDM(_ image: UIImage) -> (data: Data, width: Int, height: Int)? {
        guard DMImageRules.isSendable(image) else { return nil }
        guard let oriented = orientedCGImage(from: image) else { return nil }
        let srcW = CGFloat(oriented.width)
        let srcH = CGFloat(oriented.height)
        let cropSize = DMImageRules.centerCropToAspect(width: srcW, height: srcH)
        let target = DMImageRules.fitLongEdge(
            width: cropSize.width,
            height: cropSize.height,
            maxEdge: DMImageRules.maxLongEdge
        )
        let cropW = min(srcW, srcH * (cropSize.width / max(cropSize.height, 1)))
        let cropH = min(srcH, srcW * (cropSize.height / max(cropSize.width, 1)))
        // Tall screenshots: prefer top of frame; otherwise center.
        let originY: CGFloat = srcH / max(srcW, 1) > DMImageRules.maxAspect
            ? 0
            : (srcH - cropH) / 2
        var crop = CGRect(x: (srcW - cropW) / 2, y: originY, width: cropW, height: cropH).integral
        crop.origin.x = max(0, min(crop.origin.x, srcW - 1))
        crop.origin.y = max(0, min(crop.origin.y, srcH - 1))
        crop.size.width = min(crop.width, srcW - crop.origin.x)
        crop.size.height = min(crop.height, srcH - crop.origin.y)
        guard crop.width >= 1, crop.height >= 1, let cropped = oriented.cropping(to: crop) else {
            return nil
        }
        let outW = max(1, Int(target.width.rounded()))
        let outH = max(1, Int(target.height.rounded()))
        let scaled: CGImage
        if cropped.width == outW, cropped.height == outH {
            scaled = cropped
        } else {
            guard let ctx = CPUImageIO.makeBitmapContext(width: outW, height: outH) else { return nil }
            ctx.interpolationQuality = .high
            ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: outW, height: outH))
            guard let drawn = ctx.makeImage() else { return nil }
            scaled = drawn
        }
        guard let data = CPUImageIO.encodeJPEG(cgImage: scaled, quality: 0.85) else { return nil }
        return (data, outW, outH)
    }

    /// Bakes `imageOrientation` with ImageIO. Stays off the GPU, unlike `UIImage.draw`.
    private static func orientedCGImage(from image: UIImage) -> CGImage? {
        guard let cgImage = image.cgImage else { return nil }
        if image.imageOrientation == .up { return cgImage }
        let pixelLong = max(image.size.width, image.size.height) * max(image.scale, 1)
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encoded,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, [
            kCGImagePropertyOrientation: exifOrientation(image.imageOrientation),
            kCGImageDestinationLossyCompressionQuality: 1.0
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return CPUImageIO.decodeOrientedThumbnail(
            from: encoded as Data,
            maxLongEdge: max(pixelLong, 1)
        )
    }

    private static func exifOrientation(_ orientation: UIImage.Orientation) -> Int {
        switch orientation {
        case .up: return 1
        case .upMirrored: return 2
        case .down: return 3
        case .downMirrored: return 4
        case .leftMirrored: return 5
        case .right: return 6
        case .rightMirrored: return 7
        case .left: return 8
        @unknown default: return 1
        }
    }

    /// True when the picker should open a crop editor (aspect outside 1:3…3:1).
    static func needsDMAspectCrop(_ image: UIImage) -> Bool {
        DMImageRules.needsAspectCrop(image)
    }
}
