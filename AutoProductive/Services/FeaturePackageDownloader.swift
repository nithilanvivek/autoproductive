import Foundation

/// Downloads only from the release host and stops receiving data at the signed
/// size limit. Package bytes still require signature/sha256 verification before
/// they may be used.
final class FeaturePackageDownloader: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    enum DownloadError: Error { case invalidURL, invalidResponse, tooLarge, wrongSize }

    private let limit: Int
    private let expectedSize: Int?
    private let configuration: URLSessionConfiguration
    private var bytes = Data()
    private var failure: Error?
    private var continuation: CheckedContinuation<Data, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private let lock = NSLock()
    private var cancelled = false

    private init(limit: Int, expectedSize: Int?, configuration: URLSessionConfiguration) {
        self.limit = limit
        self.expectedSize = expectedSize
        self.configuration = configuration
    }

    static func trustedURL(_ url: URL) -> Bool {
        guard let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath,
              path.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._/")).contains($0) }),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == "." || $0 == ".." }) else { return false }
        return url.scheme?.lowercased() == "https" && url.host?.lowercased() == "nithi.land" &&
        url.port == nil && url.user == nil && url.password == nil &&
        url.query == nil && url.fragment == nil && path.hasPrefix("/apps/autoproductive/")
    }

    static func fetch(_ url: URL, maximumBytes: Int, expectedSize: Int? = nil,
                      configuration: URLSessionConfiguration = .ephemeral) async throws -> Data {
        guard trustedURL(url), maximumBytes > 0, expectedSize.map({ $0 > 0 && $0 <= maximumBytes }) != false else {
            throw DownloadError.invalidURL
        }
        let downloader = FeaturePackageDownloader(limit: maximumBytes, expectedSize: expectedSize, configuration: configuration)
        return try await downloader.run(url)
    }

    private func run(_ url: URL) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if cancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                let config = configuration
                config.timeoutIntervalForRequest = 30
                config.timeoutIntervalForResource = 600
                let queue = OperationQueue()
                queue.maxConcurrentOperationCount = 1
                let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
                self.session = session
                let task = session.dataTask(with: url)
                self.task = task
                task.resume()
                lock.unlock()
            }
        } onCancel: {
            self.lock.lock()
            self.cancelled = true
            self.task?.cancel()
            self.lock.unlock()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, Self.trustedURL(url) else { completionHandler(nil); return }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let url = response.url, Self.trustedURL(url) else {
            failure = DownloadError.invalidResponse; completionHandler(.cancel); return
        }
        if response.expectedContentLength > Int64(limit) {
            failure = DownloadError.tooLarge; completionHandler(.cancel); return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard data.count <= limit - bytes.count else {
            failure = DownloadError.tooLarge
            dataTask.cancel()
            return
        }
        bytes.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let wasCancelled = cancelled
        self.task = nil
        self.session = nil
        lock.unlock()
        defer { session.finishTasksAndInvalidate() }
        guard let continuation else { return }
        if wasCancelled { continuation.resume(throwing: CancellationError()) }
        else if let failure { continuation.resume(throwing: failure) }
        else if let error { continuation.resume(throwing: error) }
        else if let expectedSize, bytes.count != expectedSize { continuation.resume(throwing: DownloadError.wrongSize) }
        else { continuation.resume(returning: bytes) }
    }
}
