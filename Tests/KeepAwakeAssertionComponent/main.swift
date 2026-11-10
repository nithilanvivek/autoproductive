import Foundation

@main struct Tests {
    @MainActor static func main() throws {
        let bytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let tool = try FeatureKeepAwakeAssertions(verifiedBytes: bytes)
        defer { tool.stop() }
        let systemOnly = tool.start(displayMaySleep: true)
        guard systemOnly.succeeded, tool.systemAssertion != 0, tool.displayAssertion == 0 else { fatalError("System-only assertion failed") }
        tool.stop()
        guard tool.systemAssertion == 0, tool.displayAssertion == 0 else { fatalError("Assertions did not release") }
        let both = tool.start(displayMaySleep: false)
        guard both.succeeded, tool.systemAssertion != 0, tool.displayAssertion != 0 else { fatalError("Display assertion failed") }
        tool.stop()
        guard tool.systemAssertion == 0, tool.displayAssertion == 0 else { fatalError("Assertions remained active") }
        print("Passed signed Keep Awake assertion creation and release checks.")
    }
}
