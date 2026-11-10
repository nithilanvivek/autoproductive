import Foundation

final class StubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let content = Data((request.url?.lastPathComponent == "large" ? "abcdef" : "abc").utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Length": String(content.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: content)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct Tests {
    static func main() async throws {
        var checks = 0
        func check(_ result: Bool, _ message: String) { checks += 1; if !result { fatalError(message) } }
        let base = "https://nithi.land/apps/autoproductive/"
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let data = try await FeaturePackageDownloader.fetch(URL(string: base + "good")!, maximumBytes: 10, expectedSize: 3, configuration: config)
        check(data == Data("abc".utf8), "A bounded response is delivered")
        do {
            _ = try await FeaturePackageDownloader.fetch(URL(string: base + "large")!, maximumBytes: 3, configuration: config)
            check(false, "Oversized response must fail")
        } catch { check(true, "Oversized response rejected") }
        do {
            _ = try await FeaturePackageDownloader.fetch(URL(string: base + "good")!, maximumBytes: 10, expectedSize: 4, configuration: config)
            check(false, "Wrong size must fail")
        } catch { check(true, "Wrong size rejected") }
        check(!FeaturePackageDownloader.trustedURL(URL(string: "https://example.com/apps/autoproductive/x")!), "Other hosts rejected")
        check(!FeaturePackageDownloader.trustedURL(URL(string: "https://nithi.land/apps/autoproductive/%2e%2e/x")!), "Encoded traversal rejected")
        check(!FeaturePackageDownloader.trustedURL(URL(string: "http://nithi.land/apps/autoproductive/x")!), "Plain HTTP rejected")
        print("Passed \(checks) feature downloader checks.")
    }
}
