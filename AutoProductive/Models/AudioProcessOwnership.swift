import Foundation

enum AudioProcessOwnership {
    /// Read only the services table, never environment values or other metadata.
    /// XPC services have launchd as their parent, so PPID cannot identify the host.
    static func serviceHelpers(in launchdDescription: String) -> Set<Int32> {
        var inServices = false
        var result = Set<Int32>()
        for line in launchdDescription.components(separatedBy: .newlines) {
            let value = line.trimmingCharacters(in: .whitespaces)
            if value == "services = {" { inServices = true; continue }
            if inServices && value == "}" { break }
            guard inServices else { continue }
            let fields = value.split(whereSeparator: \.isWhitespace)
            guard fields.count == 3, let pid = Int32(fields[0]), pid > 0 else { continue }
            result.insert(pid)
        }
        return result
    }

    static func unambiguousOwners(_ memberships: [Int32: Set<Int32>]) -> [Int32: Int32] {
        var candidates: [Int32: Set<Int32>] = [:]
        for (owner, helpers) in memberships {
            for helper in helpers { candidates[helper, default: []].insert(owner) }
        }
        return candidates.compactMapValues { $0.count == 1 ? $0.first : nil }
    }
}
