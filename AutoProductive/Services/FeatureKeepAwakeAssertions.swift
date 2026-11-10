import Foundation

@MainActor
final class FeatureKeepAwakeAssertions {
    struct Result { let succeeded: Bool; let systemError: Int32; let displayError: Int32 }
    private typealias Start = @convention(c) (Int32, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?) -> Int32
    private typealias Stop = @convention(c) () -> Void
    private typealias Assertion = @convention(c) () -> UInt32
    private let library: FeatureToolLibrary
    private let startFunction: Start
    private let stopFunction: Stop
    private let systemAssertionFunction: Assertion
    private let displayAssertionFunction: Assertion

    init(verifiedBytes: Data) throws {
        let library = try FeatureToolLibrary.open(verifiedBytes: verifiedBytes, expectedID: "tool.keepAwake", requiredSymbols: [
            "autoproductive_keep_awake_start", "autoproductive_keep_awake_stop", "autoproductive_keep_awake_system_assertion", "autoproductive_keep_awake_display_assertion"])
        startFunction = unsafeBitCast(try library.symbol("autoproductive_keep_awake_start"), to: Start.self)
        stopFunction = unsafeBitCast(try library.symbol("autoproductive_keep_awake_stop"), to: Stop.self)
        systemAssertionFunction = unsafeBitCast(try library.symbol("autoproductive_keep_awake_system_assertion"), to: Assertion.self)
        displayAssertionFunction = unsafeBitCast(try library.symbol("autoproductive_keep_awake_display_assertion"), to: Assertion.self)
        self.library = library
    }
    func start(displayMaySleep: Bool) -> Result {
        var system: Int32 = 0, display: Int32 = 0
        let success = startFunction(displayMaySleep ? 1 : 0, &system, &display) != 0
        return Result(succeeded: success, systemError: system, displayError: display)
    }
    func stop() { stopFunction() }
    var systemAssertion: UInt32 { systemAssertionFunction() }
    var displayAssertion: UInt32 { displayAssertionFunction() }
    deinit { stopFunction() }
}
