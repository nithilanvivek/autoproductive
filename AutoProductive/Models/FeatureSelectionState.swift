import Foundation

/// Selection is stored on this Mac; it contains feature identifiers only, not
/// automation contents or input history. Triggers are part of the core app.
struct FeatureSelectionState: Codable, Equatable {
    private(set) var known: Set<String>
    private(set) var selected: Set<String>

    enum SelectionError: Error { case unknownSelection }

    private enum CodingKeys: String, CodingKey { case known, selected }

    private init(known: Set<String>, selected: Set<String>) {
        self.known = known
        self.selected = selected
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let known = try values.decode(Set<String>.self, forKey: .known)
        let selected = try values.decode(Set<String>.self, forKey: .selected)
        guard selected.isSubset(of: known), known.count <= 1024 else { throw SelectionError.unknownSelection }
        self.init(known: known, selected: selected)
    }

    /// Existing installations retain access to every feature that shipped with
    /// their version. Brand-new features will be offered on a later update.
    static func migrateExisting(currentFeatureIDs: Set<String>) -> Self {
        Self(known: currentFeatureIDs, selected: currentFeatureIDs)
    }

    static func newInstallation(available: Set<String>, selected: Set<String>) throws -> Self {
        guard selected.isSubset(of: available), available.count <= 1024 else { throw SelectionError.unknownSelection }
        return Self(known: available, selected: selected)
    }

    func newFeatures(in available: Set<String>) -> Set<String> { available.subtracting(known) }

    /// `chosen` represents the complete selection the person confirmed. Feature
    /// IDs absent from a temporary catalogue remain remembered, so an outage or
    /// incompatible release cannot silently erase existing choices.
    mutating func confirm(available: Set<String>, chosen: Set<String>) throws {
        guard chosen.isSubset(of: available), known.union(available).count <= 1024 else { throw SelectionError.unknownSelection }
        selected = selected.subtracting(available).union(chosen)
        known.formUnion(available)
    }
}
