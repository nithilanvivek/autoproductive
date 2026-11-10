import Foundation

/// Finder's key interception remains in the app's already-authorized event tap;
/// this signed optional tool owns only the cut/paste state and decisions.
@MainActor
final class FeatureFinderCut {
    private typealias Reset = @convention(c) () -> Void
    private typealias Mark = @convention(c) (Int64, Int32) -> Void
    private typealias Decide = @convention(c) (Int32, Int64, Int32) -> Int32
    private typealias Pending = @convention(c) () -> Int32
    private typealias Matches = @convention(c) (Int64) -> Int32
    private let library: FeatureToolLibrary
    private let resetFunction: Reset
    private let markFunction: Mark
    private let decideFunction: Decide
    private let pendingFunction: Pending
    private let matchesFunction: Matches

    init(verifiedBytes: Data) throws {
        let library = try FeatureToolLibrary.open(verifiedBytes: verifiedBytes, expectedID: "tool.finderCut", requiredSymbols: [
            "autoproductive_finder_cut_reset", "autoproductive_finder_cut_mark", "autoproductive_finder_cut_decide",
            "autoproductive_finder_cut_pending", "autoproductive_finder_cut_matches"])
        resetFunction = unsafeBitCast(try library.symbol("autoproductive_finder_cut_reset"), to: Reset.self)
        markFunction = unsafeBitCast(try library.symbol("autoproductive_finder_cut_mark"), to: Mark.self)
        decideFunction = unsafeBitCast(try library.symbol("autoproductive_finder_cut_decide"), to: Decide.self)
        pendingFunction = unsafeBitCast(try library.symbol("autoproductive_finder_cut_pending"), to: Pending.self)
        matchesFunction = unsafeBitCast(try library.symbol("autoproductive_finder_cut_matches"), to: Matches.self)
        self.library = library
    }
    func reset() { resetFunction() }
    var hasPendingCut: Bool { pendingFunction() != 0 }
    func matches(changeCount: Int) -> Bool { matchesFunction(Int64(changeCount)) != 0 }
    func mark(changeCount: Int, hasFiles: Bool) { markFunction(Int64(changeCount), hasFiles ? 1 : 0) }
    func decide(key: Int, changeCount: Int, hasFiles: Bool) -> Int {
        Int(decideFunction(Int32(clamping: key), Int64(changeCount), hasFiles ? 1 : 0))
    }
}
