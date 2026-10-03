import Intents
import os
import UIKit
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    private let deliverLock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var fallbackContent: UNMutableNotificationContent?
    private var processTask: Task<Void, Never>?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        guard
            let fallback = request.content.mutableCopy() as? UNMutableNotificationContent,
            let working = request.content.mutableCopy() as? UNMutableNotificationContent
        else {
            contentHandler(request.content)
            return
        }
        fallbackContent = fallback

        processTask = Task { [weak self] in
            let delivered = await Self.personalizedContent(from: working)
            guard !Task.isCancelled else { return }
            self?.deliver(delivered)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        processTask?.cancel()
        if let fallbackContent {
            deliver(fallbackContent)
        }
    }

    private func deliver(_ content: UNNotificationContent) {
        deliverLock.lock()
        defer { deliverLock.unlock() }
        contentHandler?(content)
        contentHandler = nil
        fallbackContent = nil
    }

    private static let logger = Logger(
        subsystem: "com.alton.altonApp.NotificationService",
        category: "push"
    )

    private static func personalizedContent(
        from content: UNMutableNotificationContent
    ) async -> UNNotificationContent {
        let userInfo = content.userInfo
        let actorName = payloadString(userInfo, "actor_name")
        let actorID = payloadString(userInfo, "actor_id")
        let eventType = payloadString(userInfo, "type")
        let avatarURL = payloadString(userInfo, "avatar_url").flatMap(URL.init(string:))
        let imageURL = payloadString(userInfo, "image_url").flatMap(URL.init(string:))

        logger.info("payload type=\(eventType ?? "nil", privacy: .public) hasActor=\(actorID != nil, privacy: .public) hasAvatarURL=\(avatarURL != nil, privacy: .public)")

        if let actorName, !actorName.isEmpty {
            content.title = actorName
        }

        async let avatarData = download(avatarURL)
        async let imageData = download(imageURL)
        let avatar = await avatarData
        let image = await imageData

        var attachments: [UNNotificationAttachment] = []
        if let image, let imageURL, let attachment = makeAttachment(data: image, url: imageURL, identifier: "post") {
            attachments.append(attachment)
        }

        let canShowCommunication = actorID != nil && actorName != nil && !(actorName?.isEmpty ?? true)
            && (NotificationMediaPolicy.isCommunicationEvent(eventType) || eventType == nil)
        if canShowCommunication, let actorID, let actorName {
            if let updated = await communicationContent(
                from: content,
                eventType: eventType ?? "message",
                actorID: actorID,
                actorName: actorName,
                avatarData: avatar,
                attachments: attachments
            ) {
                return updated
            }
        }

        if attachments.isEmpty, let avatar, let avatarURL {
            if let attachment = makeAttachment(data: avatar, url: avatarURL, identifier: "avatar") {
                attachments.append(attachment)
            }
        }
        content.attachments = attachments
        return content
    }

    private static func communicationContent(
        from content: UNMutableNotificationContent,
        eventType: String,
        actorID: String,
        actorName: String,
        avatarData: Data?,
        attachments: [UNNotificationAttachment]
    ) async -> UNNotificationContent? {
        let avatarImage = intentImage(from: avatarData)
        var nameComponents = PersonNameComponents()
        nameComponents.nickname = actorName
        let sender = INPerson(
            personHandle: INPersonHandle(value: actorID, type: .unknown),
            nameComponents: nameComponents,
            displayName: actorName,
            image: avatarImage,
            contactIdentifier: nil,
            customIdentifier: actorID
        )
        // Direct incoming message: Apple adds the current user as recipient.
        // Do not pass a dummy `isMe` person — that breaks communication style.
        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: content.body,
            speakableGroupName: nil,
            conversationIdentifier: "\(eventType):\(actorID)",
            serviceName: nil,
            sender: sender,
            attachments: nil
        )
        if let avatarImage {
            intent.setImage(avatarImage, forParameterNamed: \.sender)
        }

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        do {
            try await interaction.donate()
        } catch {
            logger.error("intent donate failed: \(error.localizedDescription, privacy: .public)")
        }

        do {
            let updated = try content.updating(from: intent)
            guard !attachments.isEmpty else { return updated }
            guard let mutable = updated.mutableCopy() as? UNMutableNotificationContent else {
                return updated
            }
            mutable.attachments = attachments
            return mutable
        } catch {
            logger.error("updating from intent failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func intentImage(from data: Data?) -> INImage? {
        guard let data, !data.isEmpty else { return nil }
        if let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.85) {
            return INImage(imageData: jpeg)
        }
        return INImage(imageData: data)
    }

    private static func payloadString(_ userInfo: [AnyHashable: Any], _ key: String) -> String? {
        if let value = stringValue(userInfo[key]) {
            return value
        }
        if let data = userInfo["data"] as? [AnyHashable: Any], let value = stringValue(data[key]) {
            return value
        }
        return nil
    }

    private static func stringValue(_ raw: Any?) -> String? {
        if let value = raw as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = raw as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private static func download(_ url: URL?) async -> Data? {
        guard let url, NotificationMediaPolicy.isAllowedDownloadURL(url) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        return await CappedImageDownload.fetch(request, maxBytes: NotificationMediaPolicy.maxImageBytes)
    }

    private static func makeAttachment(data: Data, url: URL, identifier: String) -> UNNotificationAttachment? {
        let ext = imageExtension(for: url, data: data)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(identifier)-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        do {
            try data.write(to: fileURL, options: .atomic)
            return try UNNotificationAttachment(identifier: identifier, url: fileURL, options: nil)
        } catch {
            return nil
        }
    }

    private static func imageExtension(for url: URL, data: Data) -> String {
        let pathExt = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif"].contains(pathExt) {
            return pathExt == "jpg" ? "jpeg" : pathExt
        }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if data.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        return "jpeg"
    }
}

private final class CappedImageDownload: NSObject, URLSessionDataDelegate {
    private let maxBytes: Int
    private var buffer = Data()
    private var continuation: CheckedContinuation<Data?, Never>?
    private var session: URLSession?
    private var selfRetain: CappedImageDownload?

    static func fetch(_ request: URLRequest, maxBytes: Int) async -> Data? {
        await withCheckedContinuation { continuation in
            let download = CappedImageDownload(maxBytes: maxBytes, continuation: continuation)
            download.start(request)
        }
    }

    private init(maxBytes: Int, continuation: CheckedContinuation<Data?, Never>) {
        self.maxBytes = maxBytes
        self.continuation = continuation
    }

    private func start(_ request: URLRequest) {
        selfRetain = self
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        session.dataTask(with: request).resume()
    }

    private func finish(_ data: Data?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: data)
        session?.invalidateAndCancel()
        session = nil
        selfRetain = nil
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, NotificationMediaPolicy.isAllowedDownloadURL(url) else {
            task.cancel()
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            completionHandler(.cancel)
            finish(nil)
            return
        }
        let expected = response.expectedContentLength
        if expected > 0 && expected > Int64(maxBytes) {
            completionHandler(.cancel)
            finish(nil)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if buffer.count + data.count > maxBytes {
            dataTask.cancel()
            finish(nil)
            return
        }
        buffer.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil || buffer.isEmpty {
            finish(nil)
        } else {
            finish(buffer)
        }
    }
}
