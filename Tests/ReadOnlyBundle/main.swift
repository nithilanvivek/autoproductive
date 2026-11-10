import Foundation

@main struct ReadOnlyBundleTest {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Pass the app on a read-only mounted disk image") }
        let app = URL(fileURLWithPath: CommandLine.arguments[1])
        guard try AppArchitectureThinner.needsThinning(bundle: app) else { fatalError("Expected a universal app") }
        guard !AppArchitectureThinner.canReplace(bundle: app) else { fatalError("Read-only volume was not detected") }
        guard try AppArchitectureThinner.prepareAndSwap(bundle: app, architecture: FeatureArchitecture.current) == nil else {
            fatalError("Attempted to replace an app on a read-only volume")
        }
        print("Passed read-only volume fallback without modifying the app.")
    }
}
