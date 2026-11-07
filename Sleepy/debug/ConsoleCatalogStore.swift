#if DEBUG && !WIDGET_EXT && !WATCH_APP
import Foundation

/// Android CatalogOverrideStore 同一按 name 覆盖语义；写盘成功后才替换内存。
final class ConsoleCatalogStore {
    static let shared = ConsoleCatalogStore(file: ConsoleStorage.directory.appendingPathComponent("console_catalog_overrides.json"))
    static let didChange = Notification.Name("Sleepy.ConsoleCatalog.didChange")
    private let file: URL
    private let lock = NSLock()
    private var overrides: [String: [String: String]] = [:]
    private var active = false

    init(file: URL) {
        self.file = file
        if let bytes = try? Data(contentsOf: file),
           let rows = try? JSONDecoder().decode([String: [String: String]].self, from: bytes) { overrides = rows }
    }

    func setActive(_ value: Bool) {
        lock.lock(); active = value; lock.unlock()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    func apply(to schools: [JwSchoolInfo]) -> [JwSchoolInfo] {
        lock.lock(); defer { lock.unlock() }
        guard active else { return schools }
        return schools.map { school in
            guard let patch = overrides[school.name] else { return school }
            var next = school
            if let status = patch["status"] { next.status = JwSchoolInfo.normalizeStatus(status) }
            if let type = patch["type"] { next.type = type }
            if let url = patch["url"] { next.url = url }
            return next
        }
    }

    func contains(_ name: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return active && overrides[name] != nil
    }

    func put(name: String, patch: [String: String]) throws {
        lock.lock()
        do {
            guard active else { throw ConsoleFailure(409, "catalog override store inactive") }
            var next = overrides
            next[name] = patch // 上游 put 替换整条 Override，不与上一条 patch 累加。
            try ConsoleStorage.save(JSONEncoder().encode(next), to: file)
            overrides = next
            lock.unlock()
        } catch { lock.unlock(); throw error }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    func clear() throws {
        lock.lock()
        do {
            try ConsoleStorage.save(Data("{}".utf8), to: file)
            overrides = [:]
            lock.unlock()
        } catch { lock.unlock(); throw error }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    @MainActor
    func handle(_ object: [String: Any], consumerWired: Bool,
                base: () throws -> [JwSchoolInfo]) throws -> Any {
        let name = try ConsoleJSON.string(object, "name")
        let op = try ConsoleJSON.string(object, "op")
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConsoleFailure("name required") }
        guard let row = try base().first(where: { $0.name == name }) else { throw ConsoleFailure(404, "school not found") }
        if op == "set" {
            guard consumerWired else { throw ConsoleFailure(501, "catalog consumer not wired") }
            var patch: [String: String] = [:]
            for key in ["status", "type", "url"] where object[key] != nil && !(object[key] is NSNull) {
                let value = try ConsoleJSON.string(object, key)
                if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { patch[key] = value }
            }
            guard !patch.isEmpty else { throw ConsoleFailure("set needs status/type/url") }
            if let value = patch["url"] {
                guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      url.host != nil else { throw ConsoleFailure("url must be http(s)") }
            }
            try put(name: name, patch: patch)
        } else if op != "get" { throw ConsoleFailure("op must be get|set") }
        let result = apply(to: [row])[0]
        var json: [String: Any] = ["name": result.name, "sortKey": result.sortKey, "url": result.url,
            "type": result.type as Any? ?? NSNull(), "status": result.status, "enableFetch": result.enableFetch,
            "overridden": contains(name)]
        if op == "set" { json["persisted"] = true }
        return json
    }
}

enum ConsoleStorage {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DebugConsole", isDirectory: true)
    }

    static func save(_ bytes: Data, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: file, options: .atomic)
    }
}
#endif
