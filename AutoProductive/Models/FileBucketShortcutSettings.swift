import Foundation

struct FileBucketShortcutSettings: Codable, Equatable {
    var openEnabled = true
    var addEnabled = true
    var open: KeyboardShortcutDefinition? = .init(keyCode: 3, keyLabel: "F", modifiers: [.command, .option])
    var add: KeyboardShortcutDefinition? = nil
    private static let key = "fileBucketShortcuts.v1"

    static func load(defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }

    func save(defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }

    static func selectionURLs(from data: Data) throws -> [URL] {
        let strings = try JSONDecoder().decode([String].self, from: data)
        return strings.compactMap { value in
            guard let url = URL(string: value), url.isFileURL else { return nil }
            return url
        }
    }
}
