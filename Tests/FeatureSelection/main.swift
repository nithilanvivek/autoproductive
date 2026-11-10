import Foundation

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) { checks += 1; if !value() { fatalError(message) } }
let before: Set<String> = ["tool.keepAwake", "action.wait"]
var migrated = FeatureSelectionState.migrateExisting(currentFeatureIDs: before)
check(migrated.selected == before, "Migration keeps all current features")
let after = before.union(["tool.audioMixer", "action.new"])
check(migrated.newFeatures(in: after) == ["tool.audioMixer", "action.new"], "Only new features offered")
try migrated.confirm(available: after, chosen: before.union(["tool.audioMixer"]))
check(migrated.newFeatures(in: after).isEmpty, "Declined features not repeatedly offered")
check(!migrated.selected.contains("action.new") && migrated.selected.contains("tool.audioMixer"), "Choice preserved")
try migrated.confirm(available: ["action.wait"], chosen: [])
check(migrated.selected.contains("tool.keepAwake") && migrated.selected.contains("tool.audioMixer"), "Missing catalogue entries are preserved")
check((try? FeatureSelectionState.newInstallation(available: before, selected: ["not.available"])) == nil, "Unknown choice rejected")
let data = try JSONEncoder().encode(migrated)
check((try? JSONDecoder().decode(FeatureSelectionState.self, from: data)) == migrated, "Selection survives storage")
print("Passed \(checks) feature selection and migration checks.")
