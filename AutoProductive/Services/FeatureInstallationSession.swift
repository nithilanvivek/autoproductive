import Foundation

/// One review uses one signed catalogue. New features start unselected when
/// revisiting an existing installation; choices remain local to this Mac.
struct FeatureInstallationSession {
    enum SessionError: LocalizedError {
        case unavailable(Set<String>), unknownChoice
        var errorDescription: String? {
            switch self {
            case .unavailable: "Some features are not available for installation. Please try again later."
            case .unknownChoice: "The selection contains an unavailable feature."
            }
        }
    }

    let available: Set<String>
    let initiallySelected: Set<String>
    let newFeatures: Set<String>
    let sizes: [String: Int64]
    private let reviewedManifest: Data
    private let previous: FeatureSelectionState?
    private let installer: FeatureInstallationCoordinator

    static func begin(installer: FeatureInstallationCoordinator, expected: Set<String>,
                      previous: FeatureSelectionState?) async throws -> Self {
        let catalogue = try await installer.repository.catalogue()
        let packages = Dictionary(uniqueKeysWithValues: catalogue.manifest.packages.map { ($0.id, $0) })
        let missing = expected.subtracting(packages.keys)
        guard missing.isEmpty else { throw SessionError.unavailable(missing) }
        return Self(available: expected,
                    initiallySelected: previous.map { $0.selected.intersection(expected) } ?? expected,
                    newFeatures: previous.map { $0.newFeatures(in: expected) } ?? [],
                    sizes: Dictionary(uniqueKeysWithValues: expected.map { ($0, packages[$0]!.size) }),
                    reviewedManifest: catalogue.signedManifest, previous: previous, installer: installer)
    }

    func downloadSize(for selection: Set<String>) throws -> Int64 {
        guard selection.isSubset(of: available) else { throw SessionError.unknownChoice }
        return selection.reduce(0) { $0 + (sizes[$1] ?? 0) }
    }

    func install(_ selection: Set<String>) async throws {
        guard selection.isSubset(of: available) else { throw SessionError.unknownChoice }
        try await installer.install(available: available, chosen: selection, previous: previous,
                                    reviewedManifest: reviewedManifest)
    }

    /// Refresh only already-selected packages after an app update. New feature
    /// IDs remain unknown until the person reviews and confirms them.
    func refreshSelected() async throws {
        guard let previous, previous.selected.isSubset(of: available) else { throw SessionError.unknownChoice }
        try await installer.install(available: available, chosen: previous.selected, previous: previous,
                                    reviewedManifest: reviewedManifest, preserveNewFeatureChoices: true)
    }
}
