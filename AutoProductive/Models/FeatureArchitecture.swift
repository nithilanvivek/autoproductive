import Foundation

enum FeatureArchitecture {
    /// In-process libraries must match the running app, including when an
    /// Intel build is deliberately launched under Rosetta.
    static var current: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unsupported"
        #endif
    }
}
