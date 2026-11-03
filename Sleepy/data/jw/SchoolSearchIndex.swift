// SchoolSearchIndex.swift — ← data/jw/SchoolSearchIndex.kt
// Build searchable terms once per catalogue, rather than rebuilding pinyin on every keystroke.

import Foundation

/// 学校目录搜索索引 —— 一次构建可搜索词表, 避免每次按键重算拼音。
///
/// ← 原版本 SchoolSearchIndex
struct SchoolSearchIndex {

    private struct Entry {
        let school: JwSchoolInfo
        let terms: [String]
        let aliases: Set<String>
    }

    private let schools: [JwSchoolInfo]
    private let entries: [Entry]

    init(_ schools: [JwSchoolInfo]) {
        self.schools = schools
        self.entries = schools.map { school in
            let aliases = Set(school.aliases.map { $0.lowercased() })
            let terms = [school.name, school.sortKeyFull, PinyinMatcher.namePinyinShort(school.name, school.sortKey)]
                .map { $0.lowercased() } + Array(aliases)
            return Entry(school: school, terms: terms, aliases: aliases)
        }
    }

    /// 搜索 —— 空白查询返回全量目录。
    /// 命中别名(查询串**等于**某个别名)的条目排在前面, 其余保持目录原序(稳定排序)。
    ///
    /// ← 原版本: 过滤用 `q in term`(String → 子串包含), 排序键用 `q in it.aliases`
    /// (Set → 精确相等)。两者语义不同, 不能混用。
    func search(_ query: String) -> [JwSchoolInfo] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return schools }
        let hits = entries.enumerated().filter { $0.element.terms.contains { $0.contains(q) } }
        // ← 原 sortedByDescending { q in it.aliases } 是稳定排序, 别名精确命中者前置。
        // Swift 的 sort 不保证稳定 → 用原始下标做次级键还原同一顺序。
        let aliasFirst = hits.filter { $0.element.aliases.contains(q) }.map { $0.offset }
        let others = hits.filter { !$0.element.aliases.contains(q) }.map { $0.offset }
        let order = aliasFirst + others
        return order.map { entries[$0].school }
    }
}
