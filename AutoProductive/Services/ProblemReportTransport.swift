import Foundation

enum ProblemReportTransport {
    static let endpoint = URL(string: "https://nithi.land/api/autoproductive/report")!
    static func send(_ report: ProblemReport, endpoint: URL = endpoint, session: URLSession = .shared) async throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(report)
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "digest", value: ReportChallenge.digest(data))]
        let (challengeData, challengeResponse) = try await session.data(from: components.url!)
        try check(challengeData, response: challengeResponse)
        let challenge = try JSONDecoder().decode(ReportChallenge.self, from: challengeData)
        let work = Task.detached(priority: .utility) { try challenge.solve() }
        let nonce = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
        var request = URLRequest(url: endpoint); request.httpMethod = "POST"; request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["payload": String(decoding: data, as: UTF8.self), "token": challenge.token, "nonce": nonce])
        let (result, response) = try await session.data(for: request)
        try check(result, response: response)
        let receipt = try JSONDecoder().decode(Receipt.self, from: result)
        guard receipt.ok, receipt.reportID == report.id else { throw ReportError.failed("The reporting service returned an invalid receipt. Please try again.") }
    }
    private struct Receipt: Decodable { let ok: Bool; let reportID: String }
    private static func check(_ data: Data, response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            let error = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw ReportError.failed((error?["error"] as? String).map { String($0.prefix(250)) } ?? "Could not send the report. Check your connection and try again.")
        }
    }
}
