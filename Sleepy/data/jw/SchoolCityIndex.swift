// SchoolCityIndex.swift — ← data/jw/SchoolCityIndex.kt
// City metadata is separate from the import directory, so it cannot alter URLs or protocols.

import Foundation

enum SchoolCityIndex {
    /// 解析 school_cities.json → 学校名 → 城市列表。
    /// 与 Android 一致: 坏 JSON / 缺 "schools" 对象 / 城市值不是数组 一律抛错
    /// (Android 对应 JSONObject(text).getJSONObject("schools") / getJSONArray(name) 的 JSONException)。
    /// 调用方 JwImportViewModel 用 try? 兜底为 [:] — 等价 Android 侧 catch → emptyMap。
    static func parse(_ text: String) throws -> [String: [String]] {
        guard let data = text.data(using: .utf8) else {
            throw JwParseError(message: "SchoolCityIndex: text is not valid UTF-8")
        }
        let root = try JSONSerialization.jsonObject(with: data)
        guard let rootObject = root as? [String: Any] else {
            throw JwParseError(message: "SchoolCityIndex: root is not a JSON object")
        }
        guard let schools = rootObject["schools"] as? [String: Any] else {
            throw JwParseError(message: "SchoolCityIndex: missing \"schools\" object")
        }
        var out: [String: [String]] = [:]
        for (name, raw) in schools {
            guard let cities = raw as? [Any] else {
                throw JwParseError(message: "SchoolCityIndex: schools[\"\(name)\"] is not a JSON array")
            }
            var list: [String] = []
            for city in cities {
                guard let value = city as? String else {
                    throw JwParseError(message: "SchoolCityIndex: schools[\"\(name)\"] contains a non-string city")
                }
                if !value.isBlank {
                    list.append(value)
                }
            }
            out[name] = list
        }
        return out
    }

    /// 城市名归一: 去首尾空白 + 去单个"市"后缀 (Android removeSuffix 只剥结尾一次, 不是全局替换)。
    /// ← Android normalizeCity 额外处理两个异名:
    ///   "临夏州" → "临夏回族自治州" (行政区全称归一)
    ///   "昆山"   → "苏州"      (县级市归入地级市)
    static func normalizeCity(_ city: String) -> String {
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.hasSuffix("市") ? String(trimmed.dropLast()) : trimmed
        switch stripped {
        case "临夏州": return "临夏回族自治州"
        case "昆山": return "苏州"
        default: return stripped
        }
    }

    /// 同城学校列表 — 按 supported 优先 + sortKeyFull 字典序。
    /// normalizeCity 后缀"市"的剥离是单向的: "北京市"→"北京", "北京"→"北京"。
    /// ← Android: 去重键用 stableKey (catalogId 优先), 不是 name — 避免同名不同校被吞掉。
    static func schoolsInCity(_ schools: [JwSchoolInfo], city: String) -> [JwSchoolInfo] {
        let normalized = normalizeCity(city)
        if normalized.isEmpty { return [] }
        var seen = Set<String>()
        let matched = schools.filter { school in
            guard !seen.contains(school.stableKey) else { return false }
            if school.cities.contains(where: { normalizeCity($0) == normalized }) {
                seen.insert(school.stableKey)
                return true
            }
            return false
        }
        return matched.sorted { a, b in
            if a.isSupported != b.isSupported { return a.isSupported }
            let ka = a.sortKeyFull.isEmpty ? a.name : a.sortKeyFull
            let kb = b.sortKeyFull.isEmpty ? b.name : b.sortKeyFull
            return ka < kb
        }
    }
}
