import Foundation

/// Prepares an entire selection, verifies that every downloaded component can
/// start and identifies itself, then atomically publishes both the packages and
/// the person's choices. No existing generation changes on download/test error.
struct FeatureInstallationCoordinator {
    enum InstallationError: LocalizedError {
        case componentIncompatible(String), selectedFeatureUnavailable, componentNotImplemented, cleanupFailed
        var errorDescription: String? {
            switch self {
            case .componentIncompatible(let id): "The \(id) feature could not be verified on this Mac."
            case .selectedFeatureUnavailable: "A previously selected feature is unavailable. Try again when it is available."
            case .componentNotImplemented: "Some selected features are not yet available as separate components."
            case .cleanupFailed: "Features were installed, but old feature files could not be removed. Try cleaning up again."
            }
        }
    }
    private struct SelfTest: Decodable { let feature: String; let api: Int }

    let repository: FeaturePackageRepository
    let generations: FeaturePackageGenerations


    func install(available: Set<String>, chosen: Set<String>, previous: FeatureSelectionState?, reviewedManifest: Data? = nil,
                 preserveNewFeatureChoices: Bool = false) async throws {
        let selection: FeatureSelectionState
        if var existing = previous {
            if preserveNewFeatureChoices {
                guard chosen == existing.selected else { throw InstallationError.selectedFeatureUnavailable }
            } else {
                try existing.confirm(available: available, chosen: chosen)
            }
            selection = existing
        } else {
            selection = try FeatureSelectionState.newInstallation(available: available, selected: chosen)
        }
        guard selection.selected.isSubset(of: available) else { throw InstallationError.selectedFeatureUnavailable }
        guard selection.selected.isSubset(of: FeatureComponentSupport.actionIDs.union(FeatureComponentSupport.toolIDs)) else { throw InstallationError.componentNotImplemented }
        let prepared = try await repository.prepare(ids: selection.selected, reviewedManifest: reviewedManifest)
        defer { try? FileManager.default.removeItem(at: prepared.directory) }
        let signedCatalogue = try FeaturePackageManifest.verify(prepared.signedManifest, publicKey: repository.publicKey)
        guard available.isSubset(of: Set(signedCatalogue.packages.map(\.id))) else {
            throw InstallationError.selectedFeatureUnavailable
        }
        let store = FeaturePackageStore(directory: prepared.directory)
        for package in prepared.packages {
            try Task.checkCancellation()
            if package.id.hasPrefix("tool.") {
                do {
                    try await FeatureToolValidation.validate(bytes: store.verifiedBytes(for: package), id: package.id)
                }
                catch is CancellationError { throw CancellationError() }
                catch { throw InstallationError.componentIncompatible(package.id) }
            } else {
                let output = try await FeatureComponentRunner.run(package: package, store: store,
                    request: Data(#"{"selfTest":true}"#.utf8), timeout: 10, maximumOutputSize: 4096)
                guard let result = try? JSONDecoder().decode(SelfTest.self, from: output),
                      result.api == 1, result.feature == package.id else {
                    throw InstallationError.componentIncompatible(package.id)
                }
            }
        }
        try Task.checkCancellation()
        try generations.publish(prepared, selection: selection)
        do { try generations.discardSupersededGenerations() }
        catch { throw InstallationError.cleanupFailed }
    }
}
