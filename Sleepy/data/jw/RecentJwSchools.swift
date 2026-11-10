import Foundation

enum RecentJwSchools {
    static let maxEntries = 3
    static func sanitize(_ keys: [String], limit: Int = maxEntries) -> [String] {
        precondition(limit > 0)
        var seen = Set<String>()
        return Array(keys.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0).inserted }.prefix(limit))
    }
    static func merge(_ existing: [String], importedKey: String, limit: Int = maxEntries) -> [String] {
        precondition(limit > 0)
        return sanitize(importedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? existing : [importedKey] + existing, limit: limit)
    }
    static func resolve(_ keys: [String], schools: [JwSchoolInfo], limit: Int = maxEntries) -> [JwSchoolInfo] {
        let byKey = Dictionary(schools.map { ($0.stableKey, $0) }, uniquingKeysWith: { _, b in b })
        return sanitize(keys, limit: limit).compactMap { byKey[$0] }
    }
}
