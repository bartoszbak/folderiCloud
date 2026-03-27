import Foundation

/// Wraps a background URLSession so media uploads continue when the user switches away from the app.
/// Uses withCheckedThrowingContinuation to bridge the delegate callbacks back into async/await.
final class MediaUploadSession: NSObject {
    static let shared = MediaUploadSession()
    static let sessionIdentifier = "com.bartbak.fastapp.Folder.uploads"

    var backgroundCompletionHandler: (() -> Void)?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private struct PendingUpload: @unchecked Sendable {
        var responseData = Data()
        let continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>
        let tempURL: URL
    }

    nonisolated(unsafe) private var pending: [Int: PendingUpload] = [:]
    private let lock = NSLock()

    private override init() { super.init() }

    /// Writes `body` to a temporary file and uploads it via a background URLSession task.
    /// Returns the response body and HTTP response. The upload survives app backgrounding.
    func upload(body: Data, request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try body.write(to: tempURL)

        return try await withCheckedThrowingContinuation { continuation in
            let task = session.uploadTask(with: request, fromFile: tempURL)
            lock.lock()
            pending[task.taskIdentifier] = PendingUpload(continuation: continuation, tempURL: tempURL)
            lock.unlock()
            task.resume()
        }
    }
}

// MARK: - URLSessionDataDelegate

extension MediaUploadSession: URLSessionDataDelegate {
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        pending[dataTask.taskIdentifier]?.responseData.append(data)
        lock.unlock()
    }
}

// MARK: - URLSessionTaskDelegate

extension MediaUploadSession: URLSessionTaskDelegate {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        guard let upload = pending.removeValue(forKey: task.taskIdentifier) else {
            lock.unlock()
            return
        }
        lock.unlock()

        try? FileManager.default.removeItem(at: upload.tempURL)

        if let error {
            upload.continuation.resume(throwing: error)
            return
        }
        guard let httpResponse = task.response as? HTTPURLResponse else {
            upload.continuation.resume(throwing: URLError(.badServerResponse))
            return
        }
        upload.continuation.resume(returning: (upload.responseData, httpResponse))
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor [weak self] in
            self?.backgroundCompletionHandler?()
            self?.backgroundCompletionHandler = nil
        }
    }
}
