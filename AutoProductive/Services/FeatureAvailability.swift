import Foundation

enum FeatureAvailability {
    #if MODULAR_FEATURES
    private static let actions = (try? FeatureComponentDispatcher.currentActionIDs()) ?? []
    private static let tools = Dictionary(uniqueKeysWithValues: FeatureComponentSupport.toolIDs.map {
        ($0, (try? FeatureComponentDispatcher.toolBytes(id: $0)) != nil)
    })
    #endif
    /// Feature changes take effect after reopening, so availability is stable
    /// throughout one app process. The check also verifies package integrity.
    static func tool(_ id: String) -> Bool {
        #if MODULAR_FEATURES
        return tools[id] ?? false
        #else
        return true
        #endif
    }

    static func action(_ action: WorkflowAction) -> Bool {
        #if MODULAR_FEATURES
        return actions.contains(action.packageID)
        #else
        return true
        #endif
    }
}
