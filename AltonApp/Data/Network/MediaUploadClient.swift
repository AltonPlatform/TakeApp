import CryptoKit
import Foundation

/// Uploads bytes/files to presigned media URLs with long timeouts, retry, and optional progress.
final class MediaUploadClient: @unchecked Sendable {
    private let session: URLSession
    private let maxAttempts: Int
    private let progressDelegate: MediaUploadProgressDelegate?
    private let ownsSession: Bool

    /// Production client: dedicated long-timeout session with progress + cert pinning.
    init(maxAttempts: Int = 3) {
        let progressDelegate = MediaUploadProgressDelegate()
        self.progressDelegate = progressDelegate
        self.maxAttempts = max(1, maxAttempts)
        self.ownsSession = true

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 30 * 60
        configuration.waitsForConnectivity = true
        configuration.urlCache = nil
        self.session = URLSession(
            configuration: configuration,
            delegate: progressDelegate,
            delegateQueue: nil
        )
    }

    /// Injected session (tests / alternate configs). Progress callbacks are best-effort via async upload only.
    init(session: URLSession, maxAttempts: Int = 3) {
        self.session = session
        self.maxAttempts = max(1, maxAttempts)
        self.progressDelegate = nil
        self.ownsSession = false
    }

    deinit {
        if ownsSession {
            session.finishTasksAndInvalidate()
        }
    }

    func upload(
        data: Data,
        to uploadURL: URL,
        contentType: String,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        // Prefer in-memory PUT for small/no-progress uploads (take images / avatars).
        if progress == nil {
            PipelineLogger.media.info(
                "upload start bytes=\(data.count) contentType=\(contentType, privacy: .public) host=\(uploadURL.host ?? "?", privacy: .public)"
            )
            var lastError: Error?
            for attempt in 1...maxAttempts {
                do {
                    var request = URLRequest(url: uploadURL)
                    request.httpMethod = "PUT"
                    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
                    request.httpBody = data
                    let (_, response) = try await session.data(for: request)
                    try validateUploadResponse(response)
                    return
                } catch {
                    lastError = error
                    if NetworkErrorClassifier.isCancellation(error) { throw error }
                    let transient = NetworkErrorClassifier.isTransientNetworkFailure(error)
                        || isRetryableServerError(error)
                    guard transient, attempt < maxAttempts else { throw error }
                    let delayMs = UInt64(pow(2.0, Double(attempt - 1))) * 500
                    try await Task.sleep(for: .milliseconds(delayMs))
                }
            }
            throw lastError ?? APIError.network("Upload failed.")
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("alton-upload-\(UUID().uuidString).bin")
        try data.write(to: tempURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try await upload(fileURL: tempURL, to: uploadURL, contentType: contentType, progress: progress)
    }

    func upload(
        fileURL: URL,
        to uploadURL: URL,
        contentType: String,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        PipelineLogger.media.info(
            "\(PipelineLogger.fileSummary(fileURL), privacy: .public) contentType=\(contentType, privacy: .public) host=\(uploadURL.host ?? "?", privacy: .public)"
        )

        if shouldChunkUpload(fileURL: fileURL, uploadURL: uploadURL) {
            try await uploadChunked(
                fileURL: fileURL,
                to: uploadURL,
                contentType: contentType,
                progress: progress
            )
            return
        }

        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                try await uploadOnce(
                    fileURL: fileURL,
                    to: uploadURL,
                    contentType: contentType,
                    progress: progress
                )
                return
            } catch {
                lastError = error
                if NetworkErrorClassifier.isCancellation(error) {
                    throw error
                }
                let transient = NetworkErrorClassifier.isTransientNetworkFailure(error)
                    || isRetryableServerError(error)
                PipelineLogger.media.error(
                    "upload attempt \(attempt)/\(self.maxAttempts) failed transient=\(transient)"
                )
                guard transient, attempt < maxAttempts else { throw error }
                let delayMs = UInt64(pow(2.0, Double(attempt - 1))) * 500
                try await Task.sleep(for: .milliseconds(delayMs))
            }
        }
        throw lastError ?? APIError.network("Upload failed.")
    }

    private func uploadOnce(
        fileURL: URL,
        to uploadURL: URL,
        contentType: String,
        progress: (@Sendable (Double) -> Void)?
    ) async throws {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        if let progressDelegate, progress != nil {
            try await uploadWithProgressDelegate(
                request: request,
                fileURL: fileURL,
                progressDelegate: progressDelegate,
                progress: progress
            )
            return
        }

        let (_, response) = try await session.upload(for: request, fromFile: fileURL)
        try validateUploadResponse(response)
        progress?(1)
    }

    private func uploadWithProgressDelegate(
        request: URLRequest,
        fileURL: URL,
        progressDelegate: MediaUploadProgressDelegate,
        progress: (@Sendable (Double) -> Void)?
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var taskRef: URLSessionUploadTask?
            let task = session.uploadTask(with: request, fromFile: fileURL) { [progressDelegate] _, response, error in
                if let taskID = taskRef?.taskIdentifier {
                    progressDelegate.clearProgress(for: taskID)
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                do {
                    try self.validateUploadResponse(response)
                    progress?(1)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            taskRef = task
            progressDelegate.setProgress(for: task.taskIdentifier, handler: progress)
            task.resume()
        }
    }

    /// Local r2 tunnel drops a single large PUT. R2 requires every part except the
    /// last to be at least 5 MiB. A failed part is retried without resending the file.
    static var chunkSize = 5 * 1024 * 1024
    private static let chunkAttempts = 5

    private func shouldChunkUpload(fileURL: URL, uploadURL: URL) -> Bool {
        guard Self.objectKey(from: uploadURL) != nil else { return false }
        let size = Self.fileByteCount(fileURL)
        return size > Self.chunkSize
    }

    private func uploadChunked(
        fileURL: URL,
        to uploadURL: URL,
        contentType: String,
        progress: (@Sendable (Double) -> Void)?
    ) async throws {
        let fileSize = Self.fileByteCount(fileURL)
        guard fileSize > 0 else {
            throw APIError.network("Upload file is empty.")
        }
        guard let objectKey = Self.objectKey(from: uploadURL) else {
            throw APIError.network("Upload URL is missing an object key.")
        }

        var checkpoint = MultipartUploadCheckpointStore.current.checkpoint(
            objectKey: objectKey,
            fileSize: fileSize
        ) ?? MultipartUploadCheckpoint(
            objectKey: objectKey,
            postID: "",
            filePath: fileURL.path,
            sourcePath: nil,
            fileSize: fileSize,
            uploadID: nil,
            parts: [],
            bytesUploaded: 0,
            assembled: false
        )
        checkpoint.filePath = fileURL.path
        checkpoint.fileSize = fileSize

        if checkpoint.assembled, checkpoint.bytesUploaded == fileSize {
            progress?(1)
            return
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var didRestartMissingUpload = false
        upload: while true {
            if checkpoint.uploadID == nil || checkpoint.bytesUploaded > fileSize {
                checkpoint = try await beginMultipart(
                    checkpoint: checkpoint,
                    uploadURL: uploadURL,
                    contentType: contentType
                )
            }

            var offset = checkpoint.bytesUploaded
            var partNumber = checkpoint.parts.count + 1
            progress?(min(1, Double(offset) / Double(fileSize)))

            while offset < fileSize {
                try Task.checkCancellation()
                let chunk = try Self.readChunk(
                    handle: handle,
                    offset: offset,
                    fileSize: fileSize,
                    chunkSize: Self.chunkSize
                )
                if !Self.acceptsPart(
                    byteCount: chunk.count,
                    offset: offset,
                    fileSize: fileSize,
                    chunkSize: Self.chunkSize
                ) {
                    throw APIError.network("Upload could not read the next complete part.")
                }

                let partURL = appendingUploadPath(
                    uploadURL,
                    suffix: "multipart/\(Self.pathToken(checkpoint.uploadID ?? ""))/\(partNumber)"
                )
                var partRequest = URLRequest(url: partURL)
                partRequest.httpMethod = "PUT"
                partRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                partRequest.httpBody = chunk

                let partData: Data
                do {
                    (partData, _) = try await sendWithRetry(partRequest, attempts: Self.chunkAttempts)
                } catch let error as APIError where Self.isMissingUpload(error) && !didRestartMissingUpload {
                    didRestartMissingUpload = true
                    checkpoint = Self.resetMultipart(checkpoint)
                    MultipartUploadCheckpointStore.current.save(checkpoint)
                    continue upload
                }
                let uploaded = try JSONDecoder().decode(MultipartPartResponse.self, from: partData)
                checkpoint.parts.append(
                    MultipartCompletedPart(etag: uploaded.etag, partNumber: uploaded.partNumber)
                )
                offset += Int64(chunk.count)
                checkpoint.bytesUploaded = offset
                MultipartUploadCheckpointStore.current.save(checkpoint)

                progress?(min(1, Double(offset) / Double(fileSize)))
                PipelineLogger.media.info(
                    "chunked part \(partNumber) bytes=\(chunk.count) uploaded=\(offset)/\(fileSize)"
                )
                partNumber += 1
            }

            guard offset == fileSize, !checkpoint.parts.isEmpty else {
                throw APIError.network("Upload stopped before the file was fully sent.")
            }
            try Task.checkCancellation()

            let completeURL = appendingUploadPath(
                uploadURL,
                suffix: "multipart/\(Self.pathToken(checkpoint.uploadID ?? ""))/complete"
            )
            var completeRequest = URLRequest(url: completeURL)
            completeRequest.httpMethod = "POST"
            completeRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            completeRequest.httpBody = try JSONEncoder().encode(checkpoint.parts)
            do {
                _ = try await sendWithRetry(completeRequest, attempts: Self.chunkAttempts)
            } catch let error as APIError where Self.isMissingUpload(error) && !didRestartMissingUpload {
                didRestartMissingUpload = true
                checkpoint = Self.resetMultipart(checkpoint)
                MultipartUploadCheckpointStore.current.save(checkpoint)
                continue upload
            }
            checkpoint.assembled = true
            MultipartUploadCheckpointStore.current.save(checkpoint)
            progress?(1)
            PipelineLogger.media.info("chunked upload complete parts=\(checkpoint.parts.count)")
            return
        }
    }

    private static func resetMultipart(_ checkpoint: MultipartUploadCheckpoint) -> MultipartUploadCheckpoint {
        var checkpoint = checkpoint
        checkpoint.uploadID = nil
        checkpoint.parts = []
        checkpoint.bytesUploaded = 0
        checkpoint.assembled = false
        return checkpoint
    }

    private func beginMultipart(
        checkpoint: MultipartUploadCheckpoint,
        uploadURL: URL,
        contentType: String
    ) async throws -> MultipartUploadCheckpoint {
        var checkpoint = checkpoint
        let initURL = appendingUploadPath(uploadURL, suffix: "multipart")
        var initRequest = URLRequest(url: initURL)
        initRequest.httpMethod = "POST"
        initRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (initData, _) = try await sendWithRetry(initRequest, attempts: Self.chunkAttempts)
        let started = try JSONDecoder().decode(MultipartInitResponse.self, from: initData)
        checkpoint.uploadID = started.uploadId
        checkpoint.parts = []
        checkpoint.bytesUploaded = 0
        checkpoint.assembled = false
        MultipartUploadCheckpointStore.current.save(checkpoint)
        PipelineLogger.media.info(
            "chunked upload start bytes=\(checkpoint.fileSize) uploadId=\(started.uploadId, privacy: .public)"
        )
        return checkpoint
    }

    static func fileByteCount(_ fileURL: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    static func modificationDate(of fileURL: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        return attributes?[.modificationDate] as? Date
    }

    static func fileFingerprint(_ fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        try Task.checkCancellation()
        let head = try handle.read(upToCount: 64 * 1024) ?? Data()
        hasher.update(data: head)
        let size = fileByteCount(fileURL)
        if size > 64 * 1024 {
            try Task.checkCancellation()
            try handle.seek(toOffset: UInt64(size - 64 * 1024))
            let tail = try handle.readToEnd() ?? Data()
            hasher.update(data: tail)
        }
        hasher.update(data: Data(String(size).utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Full-file identity. Cancel is observed between 1 MiB reads.
    static func fileSHA256(_ fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            guard let piece = try handle.read(upToCount: 1024 * 1024), !piece.isEmpty else { break }
            hasher.update(data: piece)
        }
        return prefixedSHA256(hasher.finalize())
    }

    static func prefixedSHA256(_ digest: SHA256.Digest) -> String {
        "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }
    static func acceptsPart(byteCount: Int, offset: Int64, fileSize: Int64, chunkSize: Int) -> Bool {
        guard byteCount > 0, offset >= 0, offset < fileSize else { return false }
        let reachesEnd = offset + Int64(byteCount) == fileSize
        return byteCount >= chunkSize || reachesEnd
    }

    static func readChunk(handle: FileHandle, offset: Int64, fileSize: Int64, chunkSize: Int) throws -> Data {
        var chunk = Data()
        var cursor = offset
        while cursor < fileSize && chunk.count < chunkSize {
            let need = min(chunkSize - chunk.count, Int(fileSize - cursor))
            try handle.seek(toOffset: UInt64(cursor))
            guard let piece = try handle.read(upToCount: max(need, 1)), !piece.isEmpty else { break }
            chunk.append(piece)
            cursor += Int64(piece.count)
        }
        return chunk
    }

    static func objectKey(from uploadURL: URL) -> String? {
        let marker = "/upload/"
        guard let range = uploadURL.path.range(of: marker) else { return nil }
        let key = String(uploadURL.path[range.upperBound...])
        guard !key.isEmpty, !key.contains(".."), !key.hasPrefix("/") else { return nil }
        return key
    }

    static func pathToken(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func isMissingUpload(_ error: APIError) -> Bool {
        if case .serverError(let code) = error {
            return code == 404
        }
        return false
    }

    private func appendingUploadPath(_ uploadURL: URL, suffix: String) -> URL {
        guard var components = URLComponents(url: uploadURL, resolvingAgainstBaseURL: false) else {
            return uploadURL
        }
        let base = components.percentEncodedPath
        let extra = suffix.hasPrefix("/") ? String(suffix.dropFirst()) : suffix
        components.percentEncodedPath = base.hasSuffix("/") ? base + extra : base + "/" + extra
        return components.url ?? uploadURL
    }

    private func sendWithRetry(_ request: URLRequest, attempts: Int) async throws -> (Data, HTTPURLResponse) {
        var lastError: Error?
        let attempts = max(1, attempts)
        for attempt in 1...attempts {
            do {
                let (data, response) = try await session.data(for: request)
                try validateUploadResponse(response)
                guard let http = response as? HTTPURLResponse else {
                    throw APIError.network("Invalid upload response.")
                }
                return (data, http)
            } catch {
                lastError = error
                if NetworkErrorClassifier.isCancellation(error) { throw error }
                let transient = NetworkErrorClassifier.isTransientNetworkFailure(error)
                    || isRetryableServerError(error)
                guard transient, attempt < attempts else { throw error }
                let delayMs = UInt64(pow(2.0, Double(attempt - 1))) * 500
                try await Task.sleep(for: .milliseconds(delayMs))
            }
        }
        throw lastError ?? APIError.network("Upload failed.")
    }

    private func validateUploadResponse(_ response: URLResponse?) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.network("Invalid upload response.")
        }
        guard (200...299).contains(http.statusCode) else {
            PipelineLogger.media.error("upload failed status=\(http.statusCode)")
            throw APIError.serverError(http.statusCode)
        }
        PipelineLogger.media.info("upload complete status=\(http.statusCode)")
    }

    private func isRetryableServerError(_ error: Error) -> Bool {
        if case APIError.serverError(let code) = error {
            return code == 408 || code == 429 || (500...599).contains(code)
        }
        return false
    }
}

/// Tracks per-task upload progress for `MediaUploadClient`.
final class MediaUploadProgressDelegate: NSObject, URLSessionTaskDelegate, URLSessionDelegate {
    private let lock = NSLock()
    private var handlers: [Int: (@Sendable (Double) -> Void)] = [:]

    func setProgress(for taskID: Int, handler: (@Sendable (Double) -> Void)?) {
        lock.lock()
        defer { lock.unlock() }
        if let handler {
            handlers[taskID] = handler
        } else {
            handlers.removeValue(forKey: taskID)
        }
    }

    func clearProgress(for taskID: Int) {
        setProgress(for: taskID, handler: nil)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let fraction = min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend))
        lock.lock()
        let handler = handlers[task.taskIdentifier]
        lock.unlock()
        handler?(fraction)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard CertPinningPolicy.isEnabled,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host
        if CertPinningPolicy.validate(serverTrust: serverTrust, host: host) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            PipelineLogger.media.error("cert pinning rejected host=\(host, privacy: .public)")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

private struct MultipartInitResponse: Decodable {
    let uploadId: String

    enum CodingKeys: String, CodingKey {
        case uploadId = "upload_id"
    }
}

private struct MultipartPartResponse: Decodable {
    let etag: String
    let partNumber: Int
}

struct MultipartCompletedPart: Codable, Equatable {
    let etag: String
    let partNumber: Int
}

struct MultipartUploadCheckpoint: Codable, Equatable {
    var objectKey: String
    var postID: String
    /// Durable copy that survives temporary-directory cleanup.
    var filePath: String
    /// Original camera file, when it differs from `filePath`.
    var sourcePath: String?
    var fileSize: Int64
    var uploadID: String?
    var parts: [MultipartCompletedPart]
    var bytesUploaded: Int64
    var assembled: Bool
    var caption: String?
    var lat: Double?
    var lon: Double?
    var geoSource: String?
    var aiGeneratedLabel: Bool?
    var contentHash: String?
    var sourceModifiedAt: Date?
    /// Set when `upload-complete` was cancelled. Automatic relaunch must not send it again.
    var requiresExplicitResume: Bool = false
    /// The complete request may already have reached the server.
    var completeMayHaveLanded: Bool = false
    /// `upload-complete` returned success. Keep the file until the processed video is attached.
    var serverAcceptedComplete: Bool = false

    private enum CodingKeys: String, CodingKey {
        case objectKey, postID, filePath, sourcePath, fileSize, uploadID, parts, bytesUploaded, assembled
        case caption, lat, lon, geoSource, aiGeneratedLabel, contentHash, sourceModifiedAt
        case requiresExplicitResume, completeMayHaveLanded, serverAcceptedComplete
    }

    init(
        objectKey: String,
        postID: String,
        filePath: String,
        sourcePath: String?,
        fileSize: Int64,
        uploadID: String?,
        parts: [MultipartCompletedPart],
        bytesUploaded: Int64,
        assembled: Bool,
        caption: String? = nil,
        lat: Double? = nil,
        lon: Double? = nil,
        geoSource: String? = nil,
        aiGeneratedLabel: Bool? = nil,
        contentHash: String? = nil,
        sourceModifiedAt: Date? = nil,
        requiresExplicitResume: Bool = false,
        completeMayHaveLanded: Bool = false,
        serverAcceptedComplete: Bool = false
    ) {
        self.objectKey = objectKey
        self.postID = postID
        self.filePath = filePath
        self.sourcePath = sourcePath
        self.fileSize = fileSize
        self.uploadID = uploadID
        self.parts = parts
        self.bytesUploaded = bytesUploaded
        self.assembled = assembled
        self.caption = caption
        self.lat = lat
        self.lon = lon
        self.geoSource = geoSource
        self.aiGeneratedLabel = aiGeneratedLabel
        self.contentHash = contentHash
        self.sourceModifiedAt = sourceModifiedAt
        self.requiresExplicitResume = requiresExplicitResume
        self.completeMayHaveLanded = completeMayHaveLanded
        self.serverAcceptedComplete = serverAcceptedComplete
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        objectKey = try container.decode(String.self, forKey: .objectKey)
        postID = try container.decode(String.self, forKey: .postID)
        filePath = try container.decode(String.self, forKey: .filePath)
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath)
        fileSize = try container.decode(Int64.self, forKey: .fileSize)
        uploadID = try container.decodeIfPresent(String.self, forKey: .uploadID)
        parts = try container.decodeIfPresent([MultipartCompletedPart].self, forKey: .parts) ?? []
        bytesUploaded = try container.decodeIfPresent(Int64.self, forKey: .bytesUploaded) ?? 0
        assembled = try container.decodeIfPresent(Bool.self, forKey: .assembled) ?? false
        caption = try container.decodeIfPresent(String.self, forKey: .caption)
        lat = try container.decodeIfPresent(Double.self, forKey: .lat)
        lon = try container.decodeIfPresent(Double.self, forKey: .lon)
        geoSource = try container.decodeIfPresent(String.self, forKey: .geoSource)
        aiGeneratedLabel = try container.decodeIfPresent(Bool.self, forKey: .aiGeneratedLabel)
        contentHash = try container.decodeIfPresent(String.self, forKey: .contentHash)
        sourceModifiedAt = try container.decodeIfPresent(Date.self, forKey: .sourceModifiedAt)
        requiresExplicitResume = try container.decodeIfPresent(Bool.self, forKey: .requiresExplicitResume) ?? false
        completeMayHaveLanded = try container.decodeIfPresent(Bool.self, forKey: .completeMayHaveLanded) ?? false
        serverAcceptedComplete = try container.decodeIfPresent(Bool.self, forKey: .serverAcceptedComplete) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(objectKey, forKey: .objectKey)
        try container.encode(postID, forKey: .postID)
        try container.encode(filePath, forKey: .filePath)
        try container.encodeIfPresent(sourcePath, forKey: .sourcePath)
        try container.encode(fileSize, forKey: .fileSize)
        try container.encodeIfPresent(uploadID, forKey: .uploadID)
        try container.encode(parts, forKey: .parts)
        try container.encode(bytesUploaded, forKey: .bytesUploaded)
        try container.encode(assembled, forKey: .assembled)
        try container.encodeIfPresent(caption, forKey: .caption)
        try container.encodeIfPresent(lat, forKey: .lat)
        try container.encodeIfPresent(lon, forKey: .lon)
        try container.encodeIfPresent(geoSource, forKey: .geoSource)
        try container.encodeIfPresent(aiGeneratedLabel, forKey: .aiGeneratedLabel)
        try container.encodeIfPresent(contentHash, forKey: .contentHash)
        try container.encodeIfPresent(sourceModifiedAt, forKey: .sourceModifiedAt)
        if requiresExplicitResume {
            try container.encode(true, forKey: .requiresExplicitResume)
        }
        if completeMayHaveLanded {
            try container.encode(true, forKey: .completeMayHaveLanded)
        }
        if serverAcceptedComplete {
            try container.encode(true, forKey: .serverAcceptedComplete)
        }
    }
}

final class MultipartUploadCheckpointStore: @unchecked Sendable {
    static let shared = MultipartUploadCheckpointStore()
    /// Production code uses `shared`. Tests can point chunked uploads at a temporary store.
    static var current = shared

    private let lock = NSLock()
    private let fileURL: URL
    private let durableDirectory: URL
    private var cache: [String: MultipartUploadCheckpoint] = [:]
    private var stagedContext: [String: ShotUploadContext] = [:]

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            self.durableDirectory = fileURL.deletingLastPathComponent()
                .appendingPathComponent("pending-uploads", isDirectory: true)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Alton", isDirectory: true)
            self.fileURL = base.appendingPathComponent("multipart-uploads.json")
            self.durableDirectory = base.appendingPathComponent("pending-uploads", isDirectory: true)
        }
        cache = Self.load(self.fileURL)
    }

    func pendingPostID(fileURL: URL) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let checkpoint = cache.values.first(where: { Self.references($0, fileURL: fileURL) }) else {
            return nil
        }
        let durable = URL(fileURLWithPath: checkpoint.filePath)
        guard Self.matches(checkpoint, fileURL: durable) else { return nil }
        return checkpoint.postID
    }

    func pendingFileURLs() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return cache.values.compactMap { checkpoint in
            guard !checkpoint.serverAcceptedComplete else { return nil }
            let url = URL(fileURLWithPath: checkpoint.filePath)
            guard Self.matches(checkpoint, fileURL: url) else { return nil }
            return url
        }
    }

    func uploadContext(fileURL: URL) -> ShotUploadContext? {
        lock.lock()
        defer { lock.unlock() }
        if let checkpoint = cache.values.first(where: { Self.references($0, fileURL: fileURL) }) {
            return Self.context(from: checkpoint)
        }
        return stagedContext[fileURL.path]
    }

    func rememberUploadContext(fileURL: URL, context: ShotUploadContext) {
        lock.lock()
        defer { lock.unlock() }
        if let key = cache.first(where: { Self.references($0.value, fileURL: fileURL) })?.key,
           var checkpoint = cache[key] {
            Self.apply(context, to: &checkpoint)
            cache[key] = checkpoint
            persistLocked()
        } else {
            stagedContext[fileURL.path] = context
        }
    }

    /// Removes the journal entry and leaves the video file in place.
    func detachFile(_ fileURL: URL) {
        lock.lock()
        defer { lock.unlock() }
        let keys = cache.filter { Self.references($0.value, fileURL: fileURL) }.map(\.key)
        guard !keys.isEmpty else { return }
        for key in keys {
            guard let checkpoint = cache.removeValue(forKey: key) else { continue }
            let context = Self.context(from: checkpoint)
            stagedContext[checkpoint.filePath] = context
            stagedContext[fileURL.path] = context
            if let sourcePath = checkpoint.sourcePath {
                stagedContext[sourcePath] = context
            }
        }
        persistLocked()
    }

    /// Copies `fileURL` into Application Support and returns that stable path.
    /// A later bind of the same bytes keeps already uploaded parts.
    func bind(postID: String, objectKey: String, fileURL: URL) throws -> URL {
        let durable = durableURL(for: objectKey)
        let sourceSize = MediaUploadClient.fileByteCount(fileURL)
        guard sourceSize > 0 else {
            throw APIError.network("Upload file is empty.")
        }
        let incomingIsDurable = fileURL.standardizedFileURL.path == durable.standardizedFileURL.path
        let sourceModifiedAt = incomingIsDurable ? nil : MediaUploadClient.modificationDate(of: fileURL)
        let previous: MultipartUploadCheckpoint? = {
            lock.lock()
            defer { lock.unlock() }
            return cache[objectKey]
        }()

        var contentHash = previous?.contentHash
        var replaceBytes = false
        if !incomingIsDurable {
            if let previous, previous.fileSize == sourceSize {
                let durableExists = FileManager.default.fileExists(atPath: durable.path)
                var edgesDiffer = false
                if durableExists {
                    let sourceEdge = try MediaUploadClient.fileFingerprint(fileURL)
                    let durableEdge = try MediaUploadClient.fileFingerprint(durable)
                    edgesDiffer = sourceEdge != durableEdge
                }
                if edgesDiffer {
                    replaceBytes = true
                    contentHash = nil
                } else {
                    let sourceHash = try MediaUploadClient.fileSHA256(fileURL)
                    contentHash = sourceHash
                    if previous.contentHash == sourceHash {
                        replaceBytes = false
                    } else if previous.contentHash?.hasPrefix("sha256:") == true {
                        replaceBytes = true
                    } else if durableExists {
                        replaceBytes = try MediaUploadClient.fileSHA256(durable) != sourceHash
                    } else {
                        replaceBytes = true
                    }
                }
            } else if previous != nil {
                replaceBytes = true
                contentHash = nil
            }
        }

        if let copiedHash = try ensureDurableCopy(
            from: fileURL,
            to: durable,
            expectedSize: sourceSize,
            force: replaceBytes
        ) {
            contentHash = copiedHash
        }
        let storedSize = MediaUploadClient.fileByteCount(durable)
        guard storedSize == sourceSize else {
            throw APIError.network("Upload file could not be saved for resume.")
        }

        lock.lock()
        defer { lock.unlock() }
        let staged = stagedContext.removeValue(forKey: fileURL.path)
        if var existing = cache[objectKey], existing.fileSize == storedSize, !replaceBytes {
            existing.postID = postID
            existing.filePath = durable.path
            if !incomingIsDurable {
                existing.sourcePath = fileURL.path
                existing.sourceModifiedAt = sourceModifiedAt
                existing.contentHash = contentHash
            }
            if let staged {
                Self.apply(staged, to: &existing)
            }
            cache[objectKey] = existing
        } else {
            var created = MultipartUploadCheckpoint(
                objectKey: objectKey,
                postID: postID,
                filePath: durable.path,
                sourcePath: incomingIsDurable ? previous?.sourcePath : fileURL.path,
                fileSize: storedSize,
                uploadID: nil,
                parts: [],
                bytesUploaded: 0,
                assembled: false,
                contentHash: contentHash,
                sourceModifiedAt: incomingIsDurable ? previous?.sourceModifiedAt : sourceModifiedAt
            )
            if let staged {
                Self.apply(staged, to: &created)
            } else if let previous {
                created.caption = previous.caption
                created.lat = previous.lat
                created.lon = previous.lon
                created.geoSource = previous.geoSource
                created.aiGeneratedLabel = previous.aiGeneratedLabel
            }
            cache[objectKey] = created
        }
        sweepUnreferencedCopiesLocked()
        persistLocked()
        return durable
    }

    func checkpoint(objectKey: String, fileSize: Int64) -> MultipartUploadCheckpoint? {
        lock.lock()
        defer { lock.unlock() }
        guard let checkpoint = cache[objectKey], checkpoint.fileSize == fileSize else { return nil }
        return checkpoint
    }

    func requiresExplicitResume(fileURL: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cache.values.contains { checkpoint in
            Self.references(checkpoint, fileURL: fileURL) && checkpoint.requiresExplicitResume
        }
    }

    /// Automatic relaunch must not send `upload-complete` again after a cancelled attempt.
    func blocksAutomaticResume(fileURL: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cache.values.contains { checkpoint in
            Self.references(checkpoint, fileURL: fileURL)
                && (checkpoint.requiresExplicitResume || checkpoint.completeMayHaveLanded)
        }
    }

    func completeMayHaveLanded(objectKey: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cache[objectKey]?.completeMayHaveLanded == true
    }

    /// Keeps the video after a cancelled `upload-complete` and blocks automatic relaunch.
    func markCompleteUnconfirmed(objectKey: String) {
        lock.lock()
        defer { lock.unlock() }
        guard var checkpoint = cache[objectKey] else { return }
        checkpoint.requiresExplicitResume = true
        checkpoint.completeMayHaveLanded = true
        cache[objectKey] = checkpoint
        persistLocked()
    }

    /// The server accepted `upload-complete`. Keep the copy until the video is attached.
    func markServerAcceptedComplete(objectKey: String) {
        lock.lock()
        defer { lock.unlock() }
        guard var checkpoint = cache[objectKey] else { return }
        checkpoint.serverAcceptedComplete = true
        checkpoint.requiresExplicitResume = false
        cache[objectKey] = checkpoint
        persistLocked()
    }

    func serverAcceptedCompletes() -> [AcceptedShotUpload] {
        lock.lock()
        defer { lock.unlock() }
        return cache.values.compactMap { checkpoint in
            guard checkpoint.serverAcceptedComplete else { return nil }
            return AcceptedShotUpload(postID: checkpoint.postID, objectKey: checkpoint.objectKey)
        }
    }

    func removePost(_ postID: String) {
        lock.lock()
        defer { lock.unlock() }
        let keys = cache.filter { $0.value.postID == postID }.map(\.key)
        guard !keys.isEmpty else { return }
        for key in keys {
            if let checkpoint = cache.removeValue(forKey: key) {
                deleteDurableCopy(checkpoint)
            }
        }
        persistLocked()
    }

    /// Blocks automatic relaunch without claiming that `upload-complete` already reached the server.
    func requireExplicitResume(fileURL: URL) {
        lock.lock()
        defer { lock.unlock() }
        var changed = false
        for key in cache.keys {
            guard var checkpoint = cache[key], Self.references(checkpoint, fileURL: fileURL) else { continue }
            guard !checkpoint.requiresExplicitResume else { continue }
            checkpoint.requiresExplicitResume = true
            cache[key] = checkpoint
            changed = true
        }
        if changed { persistLocked() }
    }

    func allowAutomaticResume(fileURL: URL) {
        lock.lock()
        defer { lock.unlock() }
        var changed = false
        for key in cache.keys {
            guard var checkpoint = cache[key], Self.references(checkpoint, fileURL: fileURL) else { continue }
            guard checkpoint.requiresExplicitResume else { continue }
            checkpoint.requiresExplicitResume = false
            cache[key] = checkpoint
            changed = true
        }
        if changed { persistLocked() }
    }

    func save(_ checkpoint: MultipartUploadCheckpoint) {
        lock.lock()
        defer { lock.unlock() }
        cache[checkpoint.objectKey] = checkpoint
        persistLocked()
    }

    func remove(objectKey: String) {
        lock.lock()
        defer { lock.unlock() }
        if let checkpoint = cache.removeValue(forKey: objectKey) {
            deleteDurableCopy(checkpoint)
        }
        persistLocked()
    }

    func removeFile(_ fileURL: URL) {
        lock.lock()
        defer { lock.unlock() }
        let keys = cache.filter { Self.references($0.value, fileURL: fileURL) }.map(\.key)
        guard !keys.isEmpty else { return }
        keys.forEach { key in
            if let checkpoint = cache.removeValue(forKey: key) {
                deleteDurableCopy(checkpoint)
            }
        }
        persistLocked()
    }

    private func persistLocked() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
        var excluded = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
    }

    private func durableURL(for objectKey: String) -> URL {
        let name = objectKey.replacingOccurrences(of: "/", with: "_")
        return durableDirectory.appendingPathComponent(name)
    }

    private func ensureDurableCopy(from source: URL, to destination: URL, expectedSize: Int64, force: Bool) throws -> String? {
        if source.standardizedFileURL.path == destination.standardizedFileURL.path {
            return nil
        }
        if !force,
           FileManager.default.fileExists(atPath: destination.path),
           MediaUploadClient.fileByteCount(destination) == expectedSize {
            return nil
        }
        try Task.checkCancellation()
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let partial = directory.appendingPathComponent(destination.lastPathComponent + ".partial")
        if FileManager.default.fileExists(atPath: partial.path) {
            try FileManager.default.removeItem(at: partial)
        }
        guard FileManager.default.createFile(atPath: partial.path, contents: nil) else {
            throw APIError.network("Upload file could not be saved for resume.")
        }
        let reader = try FileHandle(forReadingFrom: source)
        let writer = try FileHandle(forWritingTo: partial)
        defer { try? reader.close() }
        var hasher = SHA256()
        do {
            while true {
                try Task.checkCancellation()
                guard let piece = try reader.read(upToCount: 1024 * 1024), !piece.isEmpty else { break }
                hasher.update(data: piece)
                try writer.write(contentsOf: piece)
            }
            try writer.close()
            try Task.checkCancellation()
        } catch {
            try? writer.close()
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: partial, to: destination)
        var excluded = destination
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
        return MediaUploadClient.prefixedSHA256(hasher.finalize())
    }

    private func deleteDurableCopy(_ checkpoint: MultipartUploadCheckpoint) {
        let url = URL(fileURLWithPath: checkpoint.filePath)
        let root = durableDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(prefix) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func sweepUnreferencedCopiesLocked() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: durableDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        let live = Set(cache.values.map { URL(fileURLWithPath: $0.filePath).standardizedFileURL.path })
        for file in files where !live.contains(file.standardizedFileURL.path) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func context(from checkpoint: MultipartUploadCheckpoint) -> ShotUploadContext {
        ShotUploadContext(
            caption: checkpoint.caption,
            lat: checkpoint.lat,
            lon: checkpoint.lon,
            geoSource: checkpoint.geoSource,
            aiGeneratedLabel: checkpoint.aiGeneratedLabel
        )
    }

    private static func apply(_ context: ShotUploadContext, to checkpoint: inout MultipartUploadCheckpoint) {
        checkpoint.caption = context.caption
        checkpoint.lat = context.lat
        checkpoint.lon = context.lon
        checkpoint.geoSource = context.geoSource
        checkpoint.aiGeneratedLabel = context.aiGeneratedLabel
    }

    private static func references(_ checkpoint: MultipartUploadCheckpoint, fileURL: URL) -> Bool {
        checkpoint.filePath == fileURL.path || checkpoint.sourcePath == fileURL.path
    }

    private static func matches(_ checkpoint: MultipartUploadCheckpoint, fileURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        guard MediaUploadClient.fileByteCount(fileURL) == checkpoint.fileSize, !checkpoint.postID.isEmpty else { return false }
        return true
    }

    private static func load(_ fileURL: URL) -> [String: MultipartUploadCheckpoint] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? JSONDecoder().decode([String: MultipartUploadCheckpoint].self, from: data)) ?? [:]
    }
}
