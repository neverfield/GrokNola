import Foundation

/// Names confirmed in past meetings, sealed with `Vault` in ~/Library/Application Support/GrokNotes/known-people.json.
/// Older builds kept them in UserDefaults under `knownPeople`; the first read moves them into the sealed file.
enum KnownPeople {
    static let limit = 200
    private static let defaultsKey = "knownPeople"

    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var people: [String]?
        /// A sealed file that could not be opened is never overwritten, so a missing key cannot erase it.
        var readFailed = false
    }

    private static let cache = Cache()

    private static var url: URL {
        AppPaths.support.appendingPathComponent("known-people.json")
    }

    static var all: [String] {
        cache.lock.withLock {
            if let people = cache.people { return people }
            let people = load()
            cache.people = people
            return people
        }
    }

    static func set(_ people: [String]) {
        let people = Array(people.suffix(limit))
        cache.lock.withLock {
            cache.people = people
            guard !cache.readFailed else { return }
            write(people)
        }
    }

    private static func load() -> [String] {
        if Vault.exists(url) {
            do {
                return try JSONDecoder().decode([String].self, from: Vault.read(url))
            } catch {
                cache.readFailed = true
                NSLog("GrokNotes: could not open the remembered people: \(error.localizedDescription)")
                return []
            }
        }
        let legacy = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        if !legacy.isEmpty, write(legacy) { UserDefaults.standard.removeObject(forKey: defaultsKey) }
        return legacy
    }

    @discardableResult
    private static func write(_ people: [String]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Vault.write(JSONEncoder().encode(people), to: url)
            return true
        } catch {
            NSLog("GrokNotes: could not save the remembered people: \(error.localizedDescription)")
            return false
        }
    }
}
